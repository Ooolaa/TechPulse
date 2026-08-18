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

/// Serves feeds for `feeds.test` only, so nothing else a parallel test does is
/// affected. Same technique as `ArxivStub` in `ResponseLimitTests`, and for the
/// same reason: `FeedSyncService` has no session to inject, and adding one
/// would be production surface bought for a test.
final class FeedStub: URLProtocol, @unchecked Sendable {
    /// Body per URL path. Written on the main actor before the fetch is awaited
    /// and read on `URLSession`'s queue after — a happens-before the
    /// `.serialized` suite keeps true by never letting two tests overlap on it.
    nonisolated(unsafe) static var bodies: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "feeds.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.bodies[request.url?.path ?? ""] ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("Feed sync", .serialized)
struct FeedSyncTests {

    private static let sharedContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: FeedSource.self, Article.self, Concept.self,
            LearningEvent.self, ConceptLink.self, ConceptDependency.self,
            SemanticLink.self, InstalledPack.self,
            configurations: config
        )
    }()

    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        for source in try context.fetch(FetchDescriptor<FeedSource>()) { context.delete(source) }
        for article in try context.fetch(FetchDescriptor<Article>()) { context.delete(article) }
        try context.save()
        FeedStub.bodies = [:]
        return context
    }

    /// A Source whose feed is served by `FeedStub` under `path`, carrying
    /// `items` entries with guids unique to that path.
    @discardableResult
    private func source(named name: String, path: String, items: Int,
                        in context: ModelContext) -> FeedSource {
        let source = FeedSource(name: name,
                                url: URL(string: "https://feeds.test\(path)")!,
                                category: "LLMs")
        context.insert(source)
        FeedStub.bodies[path] = feed(items: items, guidPrefix: path)
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
        URLProtocol.registerClass(FeedStub.self)
        defer { URLProtocol.unregisterClass(FeedStub.self) }
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

    @Test("a Source that already has articles cached is held to the daily cap")
    func cappedSourceGetsNothingMore() async throws {
        let context = try makeContext()
        source(named: "AI Weekly", path: "/a.xml", items: 10, in: context)
        cache(FeedSyncService.dailyIntakeLimit, sourceName: "AI Weekly", in: context)

        let added = await sync(context)

        #expect(added == 0)
    }
}
