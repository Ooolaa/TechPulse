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
//
// Two Sources are also two requests, and the host on the other end counts them
// together. `syncAll` fired every Source at once and discarded failures
// silently, so a second reddit.com Source produced a simultaneous request, one
// of the two came back throttled, and nobody was told (#44). Non-overlap is
// asserted through `StubTransport.peakConcurrency(among:)` rather than through
// timings, because that claim is about overlap and not about duration — but
// non-overlap alone is also true of two requests fired back to back, which is
// the hammering, so the pause itself is pinned as a lower bound on how long a
// same-host sync takes.

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
        StubTransport.stopServing(host: Self.otherHost)
        return context
    }

    /// Serves this suite's feeds and nothing else, so nothing a parallel test
    /// does is affected: `FeedSyncService` builds its own session, so the stub
    /// is registered process-wide and the host is what keeps it narrow.
    private static let host = "feeds.test"

    /// A second host, for the half of the pacing that must *not* happen — and
    /// for every test whose subject is not pacing, which puts its Sources here
    /// rather than paying `HostPacing.betweenRequests` to assert something else.
    private static let otherHost = "other.feeds.test"

    /// A Source whose feed `StubTransport` serves under `path`, carrying
    /// `items` entries with guids unique to that path.
    @discardableResult
    private func source(named name: String, host: String = Self.host, path: String,
                        items: Int, in context: ModelContext) -> FeedSource {
        let url = URL(string: "https://\(host)\(path)")!
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
        source(named: "AI Weekly", host: Self.otherHost, path: "/b.xml", items: 6, in: context)

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
        source(named: "AI Weekly", host: Self.otherHost, path: "/b.xml", items: 6, in: context)
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
        source(named: "AI Weekly", host: Self.otherHost, path: "/b.xml", items: 6, in: context)
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

    // MARK: - One host at a time (#44)

    /// The two share a name as well as a host, so the #23 shape — one bootstrap
    /// ration between them — runs through the paced path here rather than
    /// costing a second two-second test of its own.
    @Test("two Sources on one host are never in flight together, and both contribute")
    func sameHostSourcesAreFetchedOneAtATime() async throws {
        let context = try makeContext()
        source(named: "AI Weekly", path: "/a.xml", items: 3, in: context)
        source(named: "AI Weekly", path: "/b.xml", items: 3, in: context)

        let started = ContinuousClock.now
        let added = await sync(context)
        let elapsed = ContinuousClock.now - started

        #expect(StubTransport.peakConcurrency(among: Self.host) == 1)
        // A lower bound, so a slow machine cannot fail it — and back-to-back
        // requests, which overlap no more than paced ones do, cannot pass it.
        #expect(elapsed >= HostPacing.betweenRequests,
                "the second request waits rather than following straight on")
        #expect(StubTransport.requests(to: Self.host).count == 2,
                "paced is not skipped — both Sources were still asked")
        #expect(added == 6, "and both were heard")
    }

    /// The cold-sync latency win #44 was careful to keep. Without this, pacing
    /// every Source would pass the test above just as well.
    @Test("Sources on different hosts are still fetched at the same time")
    func differentHostsAreFetchedConcurrently() async throws {
        let context = try makeContext()
        source(named: "First", path: "/a.xml", items: 3, in: context)
        source(named: "Second", host: Self.otherHost, path: "/b.xml", items: 3, in: context)

        let added = await sync(context)

        #expect(StubTransport.peakConcurrency(among: Self.host, Self.otherHost) == 2,
                "two hosts share no pacing, so the two requests overlap")
        #expect(added == 6)
    }

    /// The failure the pacing exists for, from the other end: a host that
    /// refuses one request. It must cost that Source and nothing else — and the
    /// Source that follows it in the same group must still be asked.
    @Test("a throttled Source contributes nothing and costs the others nothing")
    func aThrottledSourceIsIsolated() async throws {
        let context = try makeContext()
        let throttled = URL(string: "https://\(Self.host)/throttled.xml")!
        context.insert(FeedSource(name: "Throttled", url: throttled, category: "LLMs"))
        StubTransport.serve(throttled, status: 429, body: "")
        source(named: "Healthy", path: "/healthy.xml", items: 4, in: context)
        source(named: "Elsewhere", host: Self.otherHost, path: "/c.xml", items: 2, in: context)

        let added = await sync(context)

        #expect(added == 6, "the 429 contributed nothing and stopped nothing")
        let names = Set(try context.fetch(FetchDescriptor<Article>()).map(\.sourceName))
        #expect(names == ["Healthy", "Elsewhere"])
        #expect(StubTransport.peakConcurrency(among: Self.host) == 1,
                "a refusal is the worst moment to ask the host again at once")
    }

    /// The pause is paid between *requests*, so a Source that is never asked
    /// cannot spend it. Without this, an http Source ahead of an https one on
    /// the same host bought the reader a two-second wait for a request no host
    /// ever received.
    @Test("a Source that is never asked does not make the next one wait")
    func aSourceThatIsNeverAskedCostsNoPause() async throws {
        let context = try makeContext()
        let insecure = URL(string: "http://\(Self.host)/insecure.xml")!
        context.insert(FeedSource(name: "Insecure", url: insecure, category: "LLMs"))
        source(named: "Healthy", path: "/healthy.xml", items: 3, in: context)

        let started = ContinuousClock.now
        let added = await sync(context)
        let elapsed = ContinuousClock.now - started

        #expect(added == 3, "the http Source was refused, the https one was read")
        #expect(StubTransport.requests(to: Self.host).count == 1,
                "the refused Source was never sent, so there was nothing to pace against")
        #expect(elapsed < HostPacing.betweenRequests)
    }

    /// ADR-0003's finding is that the descriptive agent does not stop reddit
    /// throttling — which is a reason to pace, not a reason to stop sending it.
    @Test("every Source is still asked with the descriptive User-Agent")
    func theUserAgentIsUnchanged() async throws {
        let context = try makeContext()
        source(named: "First", path: "/a.xml", items: 1, in: context)
        source(named: "Second", host: Self.otherHost, path: "/b.xml", items: 1, in: context)

        _ = await sync(context)

        let sent = StubTransport.requests(to: Self.host)
            + StubTransport.requests(to: Self.otherHost)
        #expect(sent.count == 2)
        #expect(sent.allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == FeedSyncService.userAgent
        })
        #expect(FeedSyncService.userAgent == "TechPulse/1.0 (iOS offline RSS reader)")
    }
}
