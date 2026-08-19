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
///
/// Two installation modes, because the fetchers differ: `session()` for a
/// caller that takes a `URLSession` (`AnthropicClient`), and
/// `registerGlobally()` for the ones that don't (`FeedSyncService`,
/// `TopicSearchService`). Giving those two a session would be production
/// surface bought for a test, so registering globally is what a fetcher that
/// builds its own session leaves a test to do. ADR-0006 declined a seam of its
/// own — the `IntelligenceService` call site — but said nothing about these
/// two, and this is not the place to decide it.
final class StubTransport: URLProtocol {

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
            self.host = host
            self.path = path
        }
    }

    private struct State {
        var replies: [Route: Reply] = [:]
        var served: [URLRequest] = []
        /// How many callers have asked for global registration. Counted rather
        /// than a flag: two suites can be installed at once, and the second one
        /// to finish is the one that may unregister.
        var installs = 0
    }

    private static let state = Mutex(State())

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
        state.withLock { state in
            state.replies = state.replies.filter { $0.key.host != host }
            state.served = state.served.filter { $0.url?.host() != host }
        }
    }

    // MARK: What was asked for

    /// Every request intercepted for `host`, matched or not, oldest first.
    /// Scoped to a host because the record is shared: an unscoped "last
    /// request" would be another suite's the moment two run at once.
    static func requests(to host: String) -> [URLRequest] {
        state.withLock { $0.served.filter { $0.url?.host() == host } }
    }

    static func lastRequest(to host: String) -> URLRequest? {
        requests(to: host).last
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
        guard let host = request.url?.host() else { return false }
        return state.withLock { $0.replies.keys.contains { $0.host == host } }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.state.withLock { state -> Reply? in
            state.served.append(request)
            return Route(request.url).flatMap { state.replies[$0] }
        }
        // A path nobody registered fails rather than serving an empty 200: a
        // setup mistake should not read as a Source with no news.
        guard let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
