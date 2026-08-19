import Testing
import Foundation
import SwiftData
@testable import TechPulse

// Source names are not unique. Subscription is deduplicated by URL everywhere
// it happens — `SeedData` and `PackSourceOffer` both — so an imported Pack can
// offer a Source whose name matches one the reader already has under a
// different URL. The new-Source bootstrap ration was held in a dictionary keyed
// by name and built with a duplicate-intolerant initializer, so the first sync
// with nothing cached for either of them trapped (#23). Syncing is how a Source
// acquires articles, so the condition could not clear itself.

@MainActor
@Suite("Feed sync", .serialized)
struct FeedSyncTests {

    private static let sharedContainer: ModelContainer = {
        return try! AppSchema.inMemoryContainer()
    }()

    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        for source in try context.fetch(FetchDescriptor<FeedSource>()) { context.delete(source) }
        for article in try context.fetch(FetchDescriptor<Article>()) { context.delete(article) }
        try context.save()
        StubTransport.stopServing(host: Self.host)
        return context
    }

    /// Serves this suite's feeds and nothing else, so nothing a parallel test
    /// does is affected: `FeedSyncService` builds its own session, so the stub
    /// is registered process-wide and the host is what keeps it narrow.
    private static let host = "feeds.test"

    /// A Source whose feed `StubTransport` serves under `path`, carrying
    /// `items` entries with guids unique to that path.
    @discardableResult
    private func source(named name: String, path: String, items: Int,
                        in context: ModelContext) -> FeedSource {
        let url = URL(string: "https://\(Self.host)\(path)")!
        let source = FeedSource(name: name, url: url, category: "LLMs")
        context.insert(source)
        StubTransport.serve(url, body: feed(items: items, guidPrefix: path))
        return source
    }

    private func feed(items: Int, guidPrefix: String) -> Data {
        let entries = (0..<items).map { index in
            """
              <item>
                <title>Item \(index)</title>
                <link>https://example.com\(guidPrefix)/\(index)</link>
                <guid>\(guidPrefix)-\(index)</guid>
                <description>Body text \(index).</description>
                <pubDate>Mon, 06 Jul 2026 08:3\(index % 10):00 GMT</pubDate>
              </item>
            """
        }.joined(separator: "\n")
        return Data("""
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
        \(entries)
        </channel></rss>
        """.utf8)
    }

    /// Articles already cached today, which is what spends the daily intake cap.
    private func cache(_ count: Int, sourceName: String, in context: ModelContext) {
        for index in 0..<count {
            context.insert(Article(guid: "cached-\(sourceName)-\(index)",
                                   title: "Cached \(index)",
                                   content: "Body",
                                   publishedAt: .now,
                                   sourceName: sourceName))
        }
        try? context.save()
    }

    private func sync(_ context: ModelContext) async -> Int {
        StubTransport.registerGlobally()
        defer { StubTransport.unregisterGlobally() }
        return await FeedSyncService.syncAll(context: context)
    }

    @Test("two Sources sharing a name, neither with anything cached, sync instead of trapping")
    func collidingNamesOnAColdSync() async throws {
        let context = try makeContext()
        source(named: "AI Weekly", path: "/a.xml", items: 6, in: context)
        source(named: "AI Weekly", path: "/b.xml", items: 6, in: context)

        let added = await sync(context)

        #expect(added == 12)
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 12)
    }

    /// The other half of the window: once articles exist under the shared name,
    /// both Sources are filtered out of the bootstrap map and the sync has to
    /// keep working.
    @Test("the same pair syncs again once articles exist under that name")
    func collidingNamesOnceCached() async throws {
        let context = try makeContext()
        source(named: "AI Weekly", path: "/a.xml", items: 6, in: context)
        source(named: "AI Weekly", path: "/b.xml", items: 6, in: context)
        cache(2, sourceName: "AI Weekly", in: context)

        let added = await sync(context)

        #expect(added == 12)
    }

    /// The accepted trade: colliding Sources share one ration rather than
    /// getting one each. With the day's intake already spent, the shared ration
    /// is all that can come in.
    @Test("colliding Sources share a single bootstrap ration")
    func collidingNamesShareTheRation() async throws {
        let context = try makeContext()
        source(named: "AI Weekly", path: "/a.xml", items: 6, in: context)
        source(named: "AI Weekly", path: "/b.xml", items: 6, in: context)
        cache(FeedSyncService.dailyIntakeLimit, sourceName: "Something Else", in: context)

        let added = await sync(context)

        #expect(added == FeedSyncService.newSourceAllowance)
    }

    /// The behaviour the bootstrap exists for: a Source added on a day whose
    /// intake is already spent still shows something rather than an empty tag.
    @Test("a Source with nothing cached is bootstrapped past a spent daily cap")
    func bootstrapSurvivesASpentCap() async throws {
        let context = try makeContext()
        source(named: "AI Weekly", path: "/a.xml", items: 10, in: context)
        cache(FeedSyncService.dailyIntakeLimit, sourceName: "Something Else", in: context)

        let added = await sync(context)

        #expect(added == FeedSyncService.newSourceAllowance)
    }

    /// A Source with articles cached takes what is left of the day's intake and
    /// no more. Two syncs, because a cap with nothing left to give returns 0
    /// whether or not the feed was ever read — the first take is what proves
    /// the cap is doing the refusing and the stub is doing the serving.
    @Test("a Source that already has articles cached is held to the daily cap")
    func cappedSourceTakesOnlyWhatTheDayHasLeft() async throws {
        let context = try makeContext()
        source(named: "AI Weekly", path: "/a.xml", items: 10, in: context)
        cache(FeedSyncService.dailyIntakeLimit - 4, sourceName: "AI Weekly", in: context)

        let firstTake = await sync(context)
        let secondTake = await sync(context)

        #expect(firstTake == 4, "four of the day's thirty were unspent, and the feed had ten to offer")
        #expect(secondTake == 0, "the day is spent now, and a cached Source has no bootstrap to fall back on")
    }
}
