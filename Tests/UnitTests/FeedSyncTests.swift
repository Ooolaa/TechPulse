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

    private static let store = TestStore()

    /// The routes are this suite's, not the store's: a stub serves a host only
    /// while that host has routes, and these two are the hosts it registered.
    private func makeContext() throws -> ModelContext {
        let context = try Self.store.makeContext()
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

    /// A feed served in exactly the order given, each entry dated `daysAgo`
    /// days back. Separating order from date is the whole point: a vote-ranked
    /// Source lists its best first and its newest wherever it falls, and the
    /// allocator must not quietly reorder that into a date sort.
    private func orderedFeed(_ entries: [(guid: String, daysAgo: Int)]) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let items = entries.map { entry in
            let date = formatter.string(from: .now.addingTimeInterval(-Double(entry.daysAgo) * 86_400))
            return """
              <item>
                <title>Item \(entry.guid)</title>
                <link>https://example.com/\(entry.guid)</link>
                <guid>\(entry.guid)</guid>
                <description>Body text.</description>
                <pubDate>\(date)</pubDate>
              </item>
            """
        }.joined(separator: "\n")
        return Data("""
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
        \(items)
        </channel></rss>
        """.utf8)
    }

    /// A Source serving `entries` in that order, on its own host so nothing
    /// here pays for pacing it is not asserting.
    @discardableResult
    private func orderedSource(named name: String, host: String, path: String,
                               entries: [(guid: String, daysAgo: Int)],
                               in context: ModelContext) -> FeedSource {
        let url = URL(string: "https://\(host)\(path)")!
        let source = FeedSource(name: name, url: url, category: "LLMs")
        context.insert(source)
        StubTransport.serve(url, body: orderedFeed(entries))
        return source
    }

    private func cachedGuids(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<Article>()).map(\.guid))
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

    /// What the format's cap on suggested Sources actually buys (#20).
    ///
    /// A cap of thirty makes "at most thirty requests at once" true by
    /// arithmetic, so asserting *that* would pass against any implementation and
    /// would still pass if the cap were five hundred. The claim worth pinning is
    /// the one that can break: at a Pack's worth of Sources, the fan-out is
    /// bounded by how many *hosts* they sit on and not by how many Sources there
    /// are (#44). Thirty Sources over ten hosts must be ten requests in flight,
    /// not thirty — and this fails the moment anything stops grouping by host.
    @Test("a Pack's worth of Sources is still fetched a host at a time, not all at once")
    func aPackAtTheCapFansOutByHostNotBySource() async throws {
        let context = try makeContext()
        let hostCount = 10
        let hosts = (0..<hostCount).map { "cap-\($0).feeds.test" }
        defer { for host in hosts { StubTransport.stopServing(host: host) } }
        // Three Sources per host, so Sources outnumber hosts three to one and
        // the two possible bounds are far enough apart to tell apart.
        for index in 0..<PackFile.maxSuggestedSources {
            // A path of its own as well as a host: guids are derived from the
            // path, and Sources sharing one would arrive as one article the
            // reader already had.
            source(named: "Feed \(index)", host: hosts[index % hostCount],
                   path: "/rss-\(index).xml", items: 1, in: context)
        }

        let added = await sync(context)

        #expect(StubTransport.peakConcurrency(among: hosts) <= hostCount,
                "the sync opened more requests at once than there are hosts to ask")
        #expect(hosts.allSatisfy { StubTransport.requests(to: $0).count == 3 },
                "one Source is one request — a retry would double the fan-out")
        #expect(added == PackFile.maxSuggestedSources, "and every Source was heard")
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

    // MARK: - The cap is shared, not won by recency (#45, ADR-0009)

    /// The fault ADR-0009 names: the cap was spent newest-first across the
    /// pooled candidates of every Source, so a Source publishing thirty items
    /// today took the lot and a quiet one took nothing. Both Sources have an
    /// article cached, so neither has a bootstrap ration and the day's
    /// allowance is the only thing paying.
    @Test("a quiet Source is represented beside one offering far more")
    func aQuietSourceIsRepresentedBesideAFirehose() async throws {
        let context = try makeContext()
        orderedSource(named: "Firehose", host: Self.host, path: "/firehose.xml",
                      entries: (0..<30).map { (guid: "firehose-\($0)", daysAgo: 0) },
                      in: context)
        orderedSource(named: "Quiet", host: Self.otherHost, path: "/quiet.xml",
                      entries: [("quiet-0", 5), ("quiet-1", 6)], in: context)
        cache(1, sourceName: "Firehose", in: context)
        cache(1, sourceName: "Quiet", in: context)

        let added = await sync(context)

        let guids = try cachedGuids(in: context)
        #expect(guids.isSuperset(of: ["quiet-0", "quiet-1"]),
                "the quiet Source's items are five and six days old and still arrive")
        #expect(added == FeedSyncService.dailyIntakeLimit - 2,
                "the two already cached today are what the day had spent")
    }

    /// The half of the same claim that #46 rests on: an item's age is not what
    /// decides whether it is taken, so a Source whose best is days old is not
    /// outranked by whatever was published this morning.
    @Test("an older item reaches the cache beside a Source full of same-day ones")
    func anOlderItemReachesTheCacheBesideSameDayItems() async throws {
        let context = try makeContext()
        orderedSource(named: "Firehose", host: Self.host, path: "/firehose.xml",
                      entries: (0..<30).map { (guid: "firehose-\($0)", daysAgo: 0) },
                      in: context)
        orderedSource(named: "Community", host: Self.otherHost, path: "/top.xml",
                      entries: [("top-0", 6)], in: context)
        // Spend all but two of the day, so recency would have to fight for a
        // place rather than being handed thirty of them — and leave exactly two,
        // one turn each, so which Source the store hands back first cannot
        // decide the outcome.
        cache(FeedSyncService.dailyIntakeLimit - 3, sourceName: "Firehose", in: context)
        cache(1, sourceName: "Community", in: context)

        _ = await sync(context)

        #expect(try cachedGuids(in: context).contains("top-0"),
                "a six-day-old item takes its turn like any other")
    }

    /// Round-robin governs *how many* items a Source contributes and never
    /// *which*: a Source's own ordering is part of what the reader subscribed
    /// to (`CONTEXT.md`, **Source**). Re-sorting each Source's own items
    /// newest-first would reproduce ADR-0009's fault inside every Source and
    /// delete the only property a vote-ranked Source has.
    @Test("a Source's own ordering decides which of its items are taken")
    func aSourcesOwnOrderingDecidesWhichItemsAreTaken() async throws {
        let context = try makeContext()
        // A vote-ranked shape: best first, and the newest entry last.
        orderedSource(named: "Community", host: Self.host, path: "/top.xml",
                      entries: [("top-best", 6), ("top-second", 5),
                                ("top-third", 3), ("top-newest", 0)],
                      in: context)
        cache(FeedSyncService.dailyIntakeLimit - 2, sourceName: "Community", in: context)

        let added = await sync(context)

        #expect(added == 2)
        #expect(try cachedGuids(in: context).isSuperset(of: ["top-best", "top-second"]),
                "the two the Source put first, not the two published most recently")
        #expect(try cachedGuids(in: context).isDisjoint(with: ["top-newest"]),
                "the newest entry is last in this feed, and that is the Source's business")
    }

    @Test("the cap is spent exactly, and fully, when the Sources have items to give")
    func theCapIsSpentExactlyAndFully() async throws {
        let context = try makeContext()
        for (index, host) in [Self.host, Self.otherHost].enumerated() {
            orderedSource(named: "Source \(index)", host: host, path: "/s\(index).xml",
                          entries: (0..<20).map { (guid: "s\(index)-\($0)", daysAgo: 0) },
                          in: context)
            cache(1, sourceName: "Source \(index)", in: context)
        }

        let added = await sync(context)

        #expect(added == FeedSyncService.dailyIntakeLimit - 2)
        #expect(try context.fetch(FetchDescriptor<Article>()).count
                == FeedSyncService.dailyIntakeLimit)
    }

    /// A Source with nothing left to offer is skipped rather than spending a
    /// turn, so the cap is not left partly unspent because one Source ran dry.
    /// A guard on the loop's stopping rule rather than on the old fault: the
    /// obvious round-robin, which stops as soon as any Source empties, leaves
    /// the day two-thirds unspent here.
    @Test("a Source that runs out does not hold back the cap")
    func anExhaustedSourceDoesNotHoldBackTheCap() async throws {
        let context = try makeContext()
        orderedSource(named: "Deep", host: Self.host, path: "/deep.xml",
                      entries: (0..<30).map { (guid: "deep-\($0)", daysAgo: 0) },
                      in: context)
        orderedSource(named: "Shallow", host: Self.otherHost, path: "/shallow.xml",
                      entries: [("shallow-0", 1)], in: context)
        cache(1, sourceName: "Deep", in: context)
        cache(1, sourceName: "Shallow", in: context)

        let added = await sync(context)

        #expect(added == FeedSyncService.dailyIntakeLimit - 2,
                "Shallow had one to give; Deep spent the rest of the day rather than leaving it")
        #expect(try cachedGuids(in: context).contains("shallow-0"))
    }

    /// An item the reader already has is not an item offered, so passing over
    /// it must not cost that Source its turn.
    @Test("a Source whose newest items are already cached still contributes")
    func alreadyCachedItemsDoNotCostATurn() async throws {
        let context = try makeContext()
        orderedSource(named: "Repeat", host: Self.host, path: "/repeat.xml",
                      entries: [("repeat-0", 2), ("repeat-1", 1), ("repeat-2", 0)],
                      in: context)
        orderedSource(named: "Other", host: Self.otherHost, path: "/other.xml",
                      entries: (0..<10).map { (guid: "other-\($0)", daysAgo: 0) },
                      in: context)
        cache(1, sourceName: "Repeat", in: context)
        cache(1, sourceName: "Other", in: context)
        // The first two of Repeat's three are already here.
        for guid in ["repeat-0", "repeat-1"] {
            context.insert(Article(guid: guid, title: "Seen", content: "Body",
                                   publishedAt: .now, sourceName: "Repeat"))
        }
        try context.save()

        _ = await sync(context)

        #expect(try cachedGuids(in: context).contains("repeat-2"),
                "two known guids were passed over without spending the Source's turn")
    }
}
