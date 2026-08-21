import Testing
import Foundation
@testable import TechPulse

/// The stub is fixture, so the properties the suites depend on are asserted
/// here rather than restated as comments in each of them: it serves what it was
/// given, it fails what it was not, and it never touches a host nobody asked it
/// to.
@Suite("Stub transport", .serialized)
struct StubTransportTests {

    private let host = "stub.test"
    private func url(_ path: String) -> URL { URL(string: "https://stub.test\(path)")! }

    private func body(from url: URL, session: URLSession) async throws -> (Data, Int?) {
        let (data, response) = try await session.data(from: url)
        return (data, (response as? HTTPURLResponse)?.statusCode)
    }

    @Test("serves the body and status registered for a URL")
    func servesWhatItWasGiven() async throws {
        StubTransport.stopServing(host: host)
        defer { StubTransport.stopServing(host: host) }
        StubTransport.serve(url("/one"), body: "first")
        StubTransport.serve(url("/two"), status: 401, body: "second")

        let (first, firstStatus) = try await body(from: url("/one"), session: StubTransport.session())
        #expect(String(decoding: first, as: UTF8.self) == "first")
        #expect(firstStatus == 200)

        let (second, secondStatus) = try await body(from: url("/two"), session: StubTransport.session())
        #expect(String(decoding: second, as: UTF8.self) == "second")
        #expect(secondStatus == 401)
    }

    @Test("a path nobody registered fails the request rather than serving nothing")
    func unregisteredPathFails() async throws {
        StubTransport.stopServing(host: host)
        defer { StubTransport.stopServing(host: host) }
        StubTransport.serve(url("/registered"), body: "here")

        await #expect(throws: (any Error).self) {
            // An empty 200 would read as a Source with no news — a setup
            // mistake has to look like a failure, not like quiet weather.
            _ = try await StubTransport.session().data(from: url("/absent"))
        }
    }

    @Test("a host nobody registered is left alone")
    func foreignHostsAreNotIntercepted() {
        StubTransport.stopServing(host: host)
        defer { StubTransport.stopServing(host: host) }
        StubTransport.serve(url("/one"), body: "first")

        // The global installation mode makes this load-bearing: two suites
        // running at once must not intercept each other, or a real request.
        #expect(StubTransport.canInit(with: URLRequest(url: url("/one"))))
        #expect(!StubTransport.canInit(with: URLRequest(url: URL(string: "https://elsewhere.test/one")!)))
    }

    @Test("records the requests it intercepted, per host")
    func recordsRequests() async throws {
        StubTransport.stopServing(host: host)
        defer { StubTransport.stopServing(host: host) }
        StubTransport.serve(url("/one"), body: "first")

        var request = URLRequest(url: url("/one"))
        request.httpMethod = "POST"
        request.setValue("value", forHTTPHeaderField: "X-Header")
        request.httpBody = Data("sent".utf8)
        _ = try await StubTransport.session().data(for: request)

        let served = try #require(StubTransport.lastRequest(to: host))
        #expect(served.url == url("/one"))
        #expect(served.httpMethod == "POST")
        #expect(served.value(forHTTPHeaderField: "X-Header") == "value")
        #expect(StubTransport.requests(to: host).count == 1)
    }

    @Test("serves the same routes when registered globally")
    func globalRegistrationServesTheSameRoutes() async throws {
        StubTransport.stopServing(host: host)
        StubTransport.registerGlobally()
        defer {
            StubTransport.unregisterGlobally()
            StubTransport.stopServing(host: host)
        }
        StubTransport.serve(url("/global"), body: "served")

        let (data, _) = try await body(from: url("/global"), session: .shared)
        #expect(String(decoding: data, as: UTF8.self) == "served")
    }

    @Test("global registration is counted, so one suite's teardown cannot disarm another's")
    func globalRegistrationIsCounted() async throws {
        StubTransport.stopServing(host: host)
        StubTransport.registerGlobally()
        StubTransport.registerGlobally()   // a second suite, still fetching
        defer {
            StubTransport.unregisterGlobally()
            StubTransport.stopServing(host: host)
        }
        StubTransport.serve(url("/counted"), body: "still served")

        StubTransport.unregisterGlobally()  // the first suite finishes

        let (data, _) = try await body(from: url("/counted"), session: .shared)
        #expect(String(decoding: data, as: UTF8.self) == "still served")
    }

    @Test("two requests issued at once read as in flight together")
    func concurrentRequestsOverlap() async throws {
        StubTransport.stopServing(host: host)
        defer { StubTransport.stopServing(host: host) }
        StubTransport.serve(url("/one"), body: "first")
        StubTransport.serve(url("/two"), body: "second")

        let session = StubTransport.session()
        async let first = session.data(from: url("/one"))
        async let second = session.data(from: url("/two"))
        _ = try await (first, second)

        // The property #44's pacing is asserted against. A stub that answered
        // inside `startLoading` would report 1 here and would then report 1 for
        // a sync that paced nothing.
        #expect(StubTransport.peakConcurrency(among: host) == 2)
    }

    @Test("requests made one after another never read as in flight together")
    func sequentialRequestsDoNotOverlap() async throws {
        StubTransport.stopServing(host: host)
        defer { StubTransport.stopServing(host: host) }
        StubTransport.serve(url("/one"), body: "first")
        StubTransport.serve(url("/two"), body: "second")

        let session = StubTransport.session()
        _ = try await session.data(from: url("/one"))
        _ = try await session.data(from: url("/two"))

        #expect(StubTransport.peakConcurrency(among: host) == 1)
    }

    @Test("a host nobody named is not counted as concurrency")
    func concurrencyIsScopedToTheHostsNamed() async throws {
        let other = "other.test"
        defer {
            StubTransport.stopServing(host: host)
            StubTransport.stopServing(host: other)
        }
        StubTransport.stopServing(host: host)
        StubTransport.stopServing(host: other)
        StubTransport.serve(url("/one"), body: "first")
        StubTransport.serve(URL(string: "https://\(other)/one")!, body: "other")

        let session = StubTransport.session()
        async let first = session.data(from: url("/one"))
        async let second = session.data(from: URL(string: "https://\(other)/one")!)
        _ = try await (first, second)

        // Suites run in parallel, so an unscoped peak would be another suite's.
        #expect(StubTransport.peakConcurrency(among: host) == 1)
        #expect(StubTransport.peakConcurrency(among: host, other) == 2)
    }

    @Test("clearing one host leaves another serving")
    func clearingIsPerHost() async throws {
        defer {
            StubTransport.stopServing(host: host)
            StubTransport.stopServing(host: "other.test")
        }
        StubTransport.serve(url("/one"), body: "first")
        StubTransport.serve(URL(string: "https://other.test/one")!, body: "other")

        StubTransport.stopServing(host: host)
        #expect(!StubTransport.canInit(with: URLRequest(url: url("/one"))))

        let (data, _) = try await body(from: URL(string: "https://other.test/one")!,
                                       session: StubTransport.session())
        #expect(String(decoding: data, as: UTF8.self) == "other")
        #expect(StubTransport.requests(to: host).isEmpty)
        #expect(StubTransport.peakConcurrency(among: host) == 0,
                "what it served is forgotten along with when it served it")
    }
}
