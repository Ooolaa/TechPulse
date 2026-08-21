import Foundation
import Synchronization

/// The one `URLProtocol` stub the unit tests use.
///
/// Three suites grew their own before this — one per fetcher — and each copy
/// had to re-derive the two properties that make a stub safe (#36). They are
/// properties of this type now, and `StubTransportTests` asserts them:
///
/// - **It serves a host only while that host has routes.** Global registration
///   is process-wide, so a stub that matched everything would intercept another
///   suite's traffic and any real request alongside it. `canInit` says yes only
///   to a host some test has registered, which is what lets suites that run at
///   once stay out of each other's way.
/// - **Its state is behind a lock**, so the write on the main actor before a
///   fetch and the read on `URLSession`'s queue after it are ordered by
///   construction. The three stubs this replaces were `nonisolated(unsafe)`
///   and leaned on each suite remembering to be `.serialized` — true, but true
///   somewhere else. Suites still want `.serialized` so one test's routes
///   outlive its own body; nothing about memory safety rests on it now.
/// - **What one suite installs and forgets is scoped to that suite.** These
///   were three classes before, so registering, unregistering and reading the
///   last request were each private to one suite by construction. One class
///   makes them shared, so routes and served requests are held per host and
///   global registration is counted — a suite tidying up must not disarm one
///   still running, and Swift Testing runs suites in parallel even when each
///   is `.serialized` within itself.
/// - **It answers after a moment, and records when each request was in
///   flight.** A stub that replied inside `startLoading` was finished before
///   its caller could issue a second request, so two requests fired at once
///   never overlapped and "these did not overlap" was true of every sync,
///   paced or not. `peakConcurrency(among:)` is what lets #44's per-host
///   pacing be asserted rather than assumed.
///
/// Two installation modes, because the fetchers differ: `session()` for a
/// caller that takes a `URLSession` (`AnthropicClient`), and
/// `registerGlobally()` for the ones that don't (`FeedSyncService`,
/// `TopicSearchService`). Giving those two a session would be production
/// surface bought for a test, so registering globally is what a fetcher that
/// builds its own session leaves a test to do. ADR-0006 declined a seam of its
/// own — the `IntelligenceService` call site — but said nothing about these
/// two, and this is not the place to decide it.
///
/// `@unchecked Sendable` because the reply is delivered off the loading thread
/// rather than inside `startLoading`. Every piece of mutable state this class
/// declares, shared and per-instance alike, is behind a `Mutex`. What it does
/// *not* own is `client` and `request`, inherited from a `URLProtocol` that
/// predates the checker: `request` is a value fixed before loading starts, and
/// answering `client` from wherever the reply is ready is the arrangement every
/// asynchronous `URLProtocol` has always had.
final class StubTransport: URLProtocol, @unchecked Sendable {

    /// What a stubbed URL answers with.
    private struct Reply {
        let status: Int
        let body: Data
    }

    /// Host and path, so one host can serve several paths and a request for a
    /// path nobody registered can still be told apart from a foreign host. The
    /// query string is deliberately not part of the key: arXiv's search terms
    /// vary per test, and a test that cares can read `requests(to:)`.
    private struct Route: Hashable {
        let host: String
        let path: String

        init?(_ url: URL?) {
            guard let host = url?.host(), let path = url?.path() else { return nil }
            self.host = StubTransport.key(host)
            self.path = path
        }
    }

    /// One request's time in flight. Kept as an interval rather than a running
    /// count so that "were these two ever in flight together" can be asked
    /// afterwards, of whichever hosts the asking suite owns.
    private struct Span {
        let id: Int
        let host: String
        let start: ContinuousClock.Instant
        var end: ContinuousClock.Instant?
    }

    private struct State {
        var replies: [Route: Reply] = [:]
        var served: [URLRequest] = []
        var spans: [Span] = []
        /// Identity rather than position: `stopServing(host:)` can drop spans
        /// while another suite's request is still open, and an index into the
        /// array would then close somebody else's.
        var nextSpanID = 0
        /// How many callers have asked for global registration. Counted rather
        /// than a flag: two suites can be installed at once, and the second one
        /// to finish is the one that may unregister.
        var installs = 0
    }

    private static let state = Mutex(State())

    /// The one form a host is filed and asked for under. Hosts are
    /// case-insensitive and `FeedSyncService` groups by the lowercased one, so
    /// a stub that filed `Reddit.com` apart from `reddit.com` would report no
    /// overlap for a pair production had already put in one group — a green
    /// bought from a disagreement about spelling.
    private static func key(_ host: String?) -> String { host?.lowercased() ?? "" }

    /// How long the stub takes to answer.
    ///
    /// This is the width of the window an overlap can happen in: 50 ms is long
    /// enough that two requests started together are both inside it, and two
    /// orders of magnitude under `HostPacing.betweenRequests`' two seconds, so
    /// a paced pair still never meets. A `DispatchTimeInterval` rather than the
    /// `Duration` that value is, because `startLoading` is not async and GCD is
    /// what it can schedule from: `Task`'s closure is `sending` and so cannot
    /// carry `self`, which the reply has to be delivered through.
    private static let serviceTime: DispatchTimeInterval = .milliseconds(50)

    /// The span this instance opened, until it is closed. One request per
    /// instance, so there is only ever one.
    private let openSpan = Mutex<Int?>(nil)

    // MARK: Registering what to serve

    static func serve(_ url: URL, status: Int = 200, body: Data) {
        guard let route = Route(url) else { return }
        state.withLock { $0.replies[route] = Reply(status: status, body: body) }
    }

    static func serve(_ url: URL, status: Int = 200, body: String) {
        serve(url, status: status, body: Data(body.utf8))
    }

    /// Forgets one host's routes and the requests it served. Per host rather
    /// than wholesale: a suite tidying up after itself must not disarm one that
    /// is still running.
    static func stopServing(host: String) {
        let host = key(host)
        state.withLock { state in
            state.replies = state.replies.filter { $0.key.host != host }
            state.served = state.served.filter { key($0.url?.host()) != host }
            state.spans = state.spans.filter { $0.host != host }
        }
    }

    // MARK: What was asked for

    /// Every request intercepted for `host`, matched or not, oldest first.
    /// Scoped to a host because the record is shared: an unscoped "last
    /// request" would be another suite's the moment two run at once.
    static func requests(to host: String) -> [URLRequest] {
        let host = key(host)
        return state.withLock { $0.served.filter { key($0.url?.host()) == host } }
    }

    static func lastRequest(to host: String) -> URLRequest? {
        requests(to: host).last
    }

    /// The most requests this stub ever had in flight at one moment, counting
    /// only those to `hosts`.
    ///
    /// Scoped for the same reason `requests(to:)` is: the record is shared and
    /// suites run in parallel, so an unscoped peak would count another suite's
    /// traffic and read as concurrency this one never caused. Naming one host
    /// is how "these never overlapped" is asked; naming a pair is how "these
    /// did" is.
    static func peakConcurrency(among hosts: String...) -> Int {
        let wanted = Set(hosts.map(key))
        let spans = state.withLock { $0.spans.filter { wanted.contains($0.host) } }
        // A request still open counts up to now. Ends sort before starts at the
        // same instant, so two requests that merely touch are not an overlap.
        let now = ContinuousClock.now
        let events = spans
            .flatMap { [($0.start, 1), ($0.end ?? now, -1)] }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        var inFlight = 0
        var peak = 0
        for (_, delta) in events {
            inFlight += delta
            peak = max(peak, inFlight)
        }
        return peak
    }

    // MARK: Installing

    /// A session that serves these routes and nothing else — the scoped form,
    /// for a caller with a `URLSession` to inject.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubTransport.self]
        return URLSession(configuration: configuration)
    }

    /// Process-wide, for a fetcher that builds its own session. Pair with
    /// `unregisterGlobally()`; the host check is what keeps this narrow.
    ///
    /// Nesting is counted, so a suite that finishes while another is still
    /// fetching leaves the stub installed rather than sending that suite's next
    /// request to the real host.
    static func registerGlobally() {
        let first = state.withLock { state -> Bool in
            state.installs += 1
            return state.installs == 1
        }
        if first { URLProtocol.registerClass(StubTransport.self) }
    }

    static func unregisterGlobally() {
        let last = state.withLock { state -> Bool in
            state.installs = max(0, state.installs - 1)
            return state.installs == 0
        }
        if last { URLProtocol.unregisterClass(StubTransport.self) }
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host().map(key) else { return false }
        return state.withLock { $0.replies.keys.contains { $0.host == host } }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url
        let host = Self.key(url?.host())
        let (reply, spanID) = Self.state.withLock { state -> (Reply?, Int) in
            state.served.append(request)
            state.nextSpanID += 1
            state.spans.append(Span(id: state.nextSpanID, host: host, start: .now, end: nil))
            return (Route(url).flatMap { state.replies[$0] }, state.nextSpanID)
        }
        openSpan.withLock { $0 = spanID }

        // Answering off this thread rather than from here is what leaves a
        // request in flight long enough for a second to be in flight alongside.
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.serviceTime) { [self] in
            guard closeSpan() else { return }   // cancelled before we answered
            // A path nobody registered fails rather than serving an empty 200:
            // a setup mistake should not read as a Source with no news.
            guard let reply, let url else {
                client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: reply.status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { _ = closeSpan() }

    /// Marks this instance's request no longer in flight. Returns whether it
    /// was this call that closed it, so a cancellation and a late answer cannot
    /// both act.
    private func closeSpan() -> Bool {
        let id = openSpan.withLock { open -> Int? in
            defer { open = nil }
            return open
        }
        guard let id else { return false }
        Self.state.withLock { state in
            if let index = state.spans.firstIndex(where: { $0.id == id }) {
                state.spans[index].end = .now
            }
        }
        return true
    }
}
