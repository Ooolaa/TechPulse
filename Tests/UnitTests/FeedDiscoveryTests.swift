import Testing
import Foundation
import SwiftData
@testable import TechPulse

// #20 answered "may this suggestion become a Source" statically — is it a URL,
// is it https — and asked the host nothing. So a Pack suggesting a 404, or a
// site's homepage, was offered and subscribed exactly like a working feed, and
// the reader found out when the Cluster stayed empty. Since #14 they find out
// from the Settings row instead, which is better and still afterwards.
//
// The three verdicts are the whole design. A refusal is not a verdict about the
// URL: reddit answers 429 to a good feed (ADR-0003), and treating that as "not
// a feed" would cost the reader a Source because a host was busy. Only a host
// that answered, with something that is not a feed, has said anything about the
// URL itself — which is why `couldNotTell` is subscribed and `notAFeed` is not.

@MainActor
@Suite("Feed discovery", .serialized)
struct FeedDiscoveryTests {

    private static let store = TestStore()
    private static let host = "discover.test"
    private static let otherHost = "other.discover.test"

    private func makeContext() throws -> ModelContext {
        let context = try Self.store.makeContext()
        StubTransport.stopServing(host: Self.host)
        StubTransport.stopServing(host: Self.otherHost)
        PackSourceOffer.forgetDeclined()
        return context
    }

    private func url(_ path: String, host: String = Self.host) -> URL {
        URL(string: "https://\(host)\(path)")!
    }

    private func feed(items: Int) -> String {
        let entries = (0..<items).map { index in
            """
              <item>
                <title>Item \(index)</title>
                <guid>guid-\(index)</guid>
                <description>Body.</description>
              </item>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
        \(entries)
        </channel></rss>
        """
    }

    private func probe(_ url: URL) async -> FeedDiscovery.Verdict {
        StubTransport.registerGlobally()
        defer { StubTransport.unregisterGlobally() }
        return await FeedDiscovery.probe(url)
    }

    // MARK: - What one URL is

    @Test("a URL serving a feed is a feed")
    func aFeedIsAFeed() async throws {
        let url = url("/feed.xml")
        StubTransport.serve(url, body: feed(items: 3))

        #expect(await probe(url) == .isAFeed)
    }

    /// The line is the document, not how much is in it. A Pack recommending a
    /// new blog is recommending exactly the feed that has published least, and
    /// turning it away would be the worst possible false negative — which is
    /// also why `RSSParser` had to learn to tell these apart at all.
    @Test("a feed that has published nothing yet is still a feed")
    func anEmptyFeedIsStillAFeed() async throws {
        let url = url("/new.xml")
        StubTransport.serve(url, body: """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Brand new</title></channel></rss>
        """)

        #expect(await probe(url) == .isAFeed)
    }

    @Test("a site's HTML page is not a feed")
    func anHTMLPageIsNotAFeed() async throws {
        let url = url("/index.html")
        StubTransport.serve(url, body: """
        <html><head><title>A blog</title></head>
        <body><item>Looks a bit like a feed entry</item></body></html>
        """)

        #expect(await probe(url) == .notAFeed)
    }

    @Test("a 404 is not a verdict about the URL")
    func aRefusalIsNotAVerdict() async throws {
        let url = url("/gone.xml")
        StubTransport.serve(url, status: 404, body: "")

        #expect(await probe(url) == .couldNotTell(.refused))
    }

    /// The case this distinction exists for. ADR-0003 watched reddit 429 a feed
    /// that is unquestionably a feed.
    @Test("a throttled host has said nothing about whether its URL is a feed")
    func aThrottledHostTellsUsNothing() async throws {
        let url = url("/throttled.xml")
        StubTransport.serve(url, status: 429, body: "")

        #expect(await probe(url) == .couldNotTell(.throttled))
    }

    @Test("zero bytes tells us nothing either")
    func anEmptyAnswerTellsUsNothing() async throws {
        let url = url("/nothing.xml")
        StubTransport.serve(url, body: "")

        #expect(await probe(url) == .couldNotTell(.empty))
    }

    @Test("a probe is sent with the app's one User-Agent")
    func theProbeIdentifiesItselfLikeEverythingElse() async throws {
        let url = url("/agent.xml")
        StubTransport.serve(url, body: feed(items: 1))

        _ = await probe(url)

        let sent = try #require(StubTransport.lastRequest(to: Self.host))
        #expect(sent.value(forHTTPHeaderField: "User-Agent") == FeedSyncService.userAgent)
    }

    // MARK: - Answering an offer

    private func suggestion(_ path: String, host: String = Self.host,
                            name: String? = nil) -> PackFile.PackSource {
        .init(name: name ?? path, url: url(path, host: host).absoluteString, category: "LLMs")
    }

    private func accept(_ offered: [PackFile.PackSource],
                        ticking accepted: Set<String>? = nil,
                        in context: ModelContext) async -> PackSourceOffer.Accepted {
        StubTransport.registerGlobally()
        defer { StubTransport.unregisterGlobally() }
        return await PackSourceOffer.accept(accepted ?? Set(offered.map(\.url)),
                                            of: offered, context: context)
    }

    private func subscribedURLs(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<FeedSource>()).map(\.url.absoluteString))
    }

    @Test("a suggestion that answers with a page instead of a feed is not subscribed")
    func aSuggestionThatIsNotAFeedIsNotAdded() async throws {
        let context = try makeContext()
        let good = suggestion("/good.xml", name: "Good")
        let page = suggestion("/page.html", host: Self.otherHost, name: "Page")
        StubTransport.serve(url("/good.xml"), body: feed(items: 2))
        StubTransport.serve(url("/page.html", host: Self.otherHost),
                            body: "<html><body>Not a feed</body></html>")

        let result = await accept([good, page], in: context)

        #expect(result.subscribed == 1)
        #expect(result.refused.map(\.name) == ["Page"])
        #expect(try subscribedURLs(in: context) == [good.url])
    }

    /// The reader said yes. A suggestion the app turned away is not a
    /// suggestion they declined, so the standing offer must raise it again —
    /// otherwise one bad afternoon on the host's side buries it close to
    /// permanently (ADR-0011, #20 follow-up).
    @Test("a suggestion the app refused is not recorded as one the reader declined")
    func aRefusedSuggestionIsNotADecline() async throws {
        let context = try makeContext()
        let page = suggestion("/page.html", name: "Page")
        StubTransport.serve(url("/page.html"), body: "<html><body>No</body></html>")

        _ = await accept([page], in: context)

        #expect(PackSourceOffer.declined.isEmpty)
        #expect(PackSourceOffer.standing([page], subscribedTo: []).map(\.name) == ["Page"],
                "the app could not use it today; the reader never said not to ask again")
    }

    /// The whole reason there are three verdicts. Subscribing on "could not
    /// tell" is the deliberate choice: post-#14 a Source that keeps failing
    /// says so on its own row, and that is a better place to lose an argument
    /// with a host than at the moment the reader asked for it.
    @Test("a throttled suggestion is still subscribed, because nothing was learned about it")
    func aThrottledSuggestionIsStillAdded() async throws {
        let context = try makeContext()
        let busy = suggestion("/busy.xml", name: "Busy")
        StubTransport.serve(url("/busy.xml"), status: 429, body: "")

        let result = await accept([busy], in: context)

        #expect(result.subscribed == 1)
        #expect(result.refused.isEmpty)
        #expect(try subscribedURLs(in: context) == [busy.url])
    }

    /// Unticked suggestions are never asked: probing what the reader did not
    /// take would spend the host's patience on a Source nobody wanted.
    @Test("only what the reader ticked is asked")
    func onlyTickedSuggestionsAreProbed() async throws {
        let context = try makeContext()
        let taken = suggestion("/taken.xml", name: "Taken")
        let left = suggestion("/left.xml", host: Self.otherHost, name: "Left")
        StubTransport.serve(url("/taken.xml"), body: feed(items: 1))
        StubTransport.serve(url("/left.xml", host: Self.otherHost), body: feed(items: 1))

        let result = await accept([taken, left], ticking: [taken.url], in: context)

        #expect(result.subscribed == 1)
        #expect(StubTransport.requests(to: Self.otherHost).isEmpty,
                "the Source the reader left unticked was never asked")
    }

    /// #44's property, which probing must not reintroduce: a Pack may suggest
    /// 30 Sources, and asking a host all of them at once is how it starts
    /// refusing. Asserted through overlap rather than timing, as `FeedSyncTests`
    /// does, because the claim is about overlap and not about duration.
    @Test("suggestions sharing a host are probed one at a time")
    func probingIsPacedByHost() async throws {
        let context = try makeContext()
        let first = suggestion("/a.xml", name: "A")
        let second = suggestion("/b.xml", name: "B")
        StubTransport.serve(url("/a.xml"), body: feed(items: 1))
        StubTransport.serve(url("/b.xml"), body: feed(items: 1))

        let started = ContinuousClock.now
        let result = await accept([first, second], in: context)
        let elapsed = ContinuousClock.now - started

        #expect(StubTransport.peakConcurrency(among: Self.host) == 1)
        #expect(elapsed >= HostPacing.betweenRequests,
                "the second probe waits rather than following straight on")
        #expect(StubTransport.requests(to: Self.host).count == 2, "and both were still asked")
        #expect(result.subscribed == 2)
    }

    @Test("suggestions on different hosts are probed at the same time")
    func differentHostsAreProbedConcurrently() async throws {
        let context = try makeContext()
        let here = suggestion("/a.xml", name: "A")
        let there = suggestion("/b.xml", host: Self.otherHost, name: "B")
        StubTransport.serve(url("/a.xml"), body: feed(items: 1))
        StubTransport.serve(url("/b.xml", host: Self.otherHost), body: feed(items: 1))

        let result = await accept([here, there], in: context)

        #expect(StubTransport.peakConcurrency(among: Self.host, Self.otherHost) == 2)
        #expect(result.subscribed == 2)
    }

    /// The bound that matters at a Pack's full size, asserted the way
    /// `aPackAtTheCapFansOutByHostNotBySource` asserts it rather than by
    /// timing: at `PackFile.maxSuggestedSources` the fan-out is bounded by how
    /// many *hosts* the suggestions sit on and not by how many suggestions
    /// there are. Two sources on one host would pass against any
    /// implementation that merely serialised everything.
    @Test("a Pack's worth of suggestions is probed a host at a time, not all at once")
    func probingAPackAtTheCapFansOutByHostNotBySuggestion() async throws {
        let context = try makeContext()
        let hostCount = 10
        let hosts = (0..<hostCount).map { "cap-\($0).discover.test" }
        defer { for host in hosts { StubTransport.stopServing(host: host) } }
        // Three per host, so suggestions outnumber hosts three to one and the
        // two possible bounds are far enough apart to tell apart.
        let offered = (0..<PackFile.maxSuggestedSources).map { index in
            suggestion("/rss-\(index).xml", host: hosts[index % hostCount], name: "Feed \(index)")
        }
        for source in offered {
            StubTransport.serve(URL(string: source.url)!, body: feed(items: 1))
        }

        let result = await accept(offered, in: context)

        #expect(StubTransport.peakConcurrency(among: hosts) <= hostCount,
                "the probe opened more requests at once than there are hosts to ask")
        #expect(hosts.allSatisfy { StubTransport.requests(to: $0).count == 3 },
                "one suggestion is one request — a retry would double the fan-out")
        #expect(result.subscribed == PackFile.maxSuggestedSources)
    }

    /// `Egress` leaves over TLS only, and the offer is where that is enforced
    /// for a suggestion: an http one is never put to the reader, so it can
    /// never be ticked and the probe never sees it. Without this the guard was
    /// three doc comments and no test at this seam.
    @Test("an http suggestion is never offered, so it is never asked")
    func anHTTPSuggestionIsNeverOffered() async throws {
        let context = try makeContext()
        let plaintext = PackFile.PackSource(name: "Plaintext",
                                            url: "http://\(Self.host)/feed.xml",
                                            category: "LLMs")
        let secure = suggestion("/secure.xml", name: "Secure")
        StubTransport.serve(url("/secure.xml"), body: feed(items: 1))

        let offer = PackSourceOffer.pending([plaintext, secure], context: context)

        #expect(offer.map(\.name) == ["Secure"], "the http suggestion never reached the sheet")
        let result = await accept(offer, in: context)
        #expect(result.subscribed == 1)
        #expect(StubTransport.requests(to: Self.host).count == 1,
                "and nothing was sent for the one that was refused")
    }

    /// The trap a second tap on Add used to spring. `accept` reads its
    /// pre-ticked rule off the list it is handed, so answering again with the
    /// *original* offer would record everything already subscribed — and every
    /// Source the app itself turned away — as a decline. The sheet narrows what
    /// it is asking about; this pins the rule that makes the narrowing
    /// necessary.
    @Test("answering again with only what is left declines nothing that was taken or refused")
    func answeringAgainDoesNotDeclineWhatWasTakenOrRefused() async throws {
        let context = try makeContext()
        let good = suggestion("/good.xml", name: "Good")
        let page = suggestion("/page.html", host: Self.otherHost, name: "Page")
        StubTransport.serve(url("/good.xml"), body: feed(items: 2))
        StubTransport.serve(url("/page.html", host: Self.otherHost),
                            body: "<html><body>Not a feed</body></html>")

        let first = await accept([good, page], in: context)
        #expect(first.refused.map(\.name) == ["Page"])
        // What the sheet does next: it asks again about what is left, still
        // ticked, rather than re-offering the whole list.
        let second = await accept(first.refused, in: context)

        #expect(second.refused.map(\.name) == ["Page"], "asked again, and answered the same way")
        #expect(PackSourceOffer.declined.isEmpty,
                "nothing the reader said yes to was recorded as a refusal")
        #expect(try subscribedURLs(in: context) == [good.url],
                "and the one that worked was not subscribed twice")
    }

    /// The hazard the narrowing avoids, written down rather than left as a
    /// warning in a doc comment. Answering a *second* time with the original
    /// list turns everything not still ticked into a decline — the Sources
    /// already subscribed and the one the app itself turned away — which is why
    /// `PackSourceOfferView` narrows what it asks about instead. If this ever
    /// stops being true, the comment on `remaining` can go.
    @Test("re-answering with the whole original offer is what would bury a refusal")
    func reAnsweringWithTheWholeOfferWouldBuryARefusal() async throws {
        let context = try makeContext()
        let good = suggestion("/good.xml", name: "Good")
        let page = suggestion("/page.html", host: Self.otherHost, name: "Page")
        StubTransport.serve(url("/good.xml"), body: feed(items: 2))
        StubTransport.serve(url("/page.html", host: Self.otherHost),
                            body: "<html><body>Not a feed</body></html>")
        let offered = [good, page]

        _ = await accept(offered, in: context)
        // The mistake: the whole offer again, with only what worked still
        // ticked — which is what "untick the ones that failed" would produce.
        _ = await accept(offered, ticking: [good.url], in: context)

        #expect(PackSourceOffer.declined == [page.url],
                "silence on a re-answer reads as a decline, so the sheet must not re-answer")
    }

    /// The other half of `accept`, unchanged by probing: above
    /// `preCheckedUpTo` nothing arrives ticked, so an unticked box is not an
    /// answer and must not be recorded as a decline (#20 follow-up).
    @Test("what silence means is still decided by whether the offer arrived ticked")
    func silenceStillMeansNothingOnAnUntickedOffer() async throws {
        let context = try makeContext()
        let offered = (0...PackSourceOffer.preCheckedUpTo).map { index in
            suggestion("/s\(index).xml", host: "h\(index).discover.test", name: "S\(index)")
        }
        defer { for index in offered.indices { StubTransport.stopServing(host: "h\(index).discover.test") } }
        for (index, source) in offered.enumerated() {
            StubTransport.serve(url("/s\(index).xml", host: "h\(index).discover.test"),
                                body: feed(items: 1))
        }

        _ = await accept(offered, ticking: [offered[0].url], in: context)

        #expect(PackSourceOffer.declined.isEmpty,
                "a reader who ticked one of sixteen said nothing about the other fifteen")
    }
}
