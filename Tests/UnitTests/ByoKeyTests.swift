import Testing
import Foundation
@testable import TechPulse

// Coverage for the BYO-key path — the one place anything leaves the device
// besides a public feed fetch. `KeychainStore` and `AnthropicClient` were
// back-ported from CareerPulse on 2026-07-14 without their tests; these are
// those tests, brought across as CareerPulse retires (#16).

// MARK: - Keychain

@Suite("Keychain store", .serialized)
struct KeychainStoreTests {
    /// Not the real account name: a failed cleanup must never be able to delete
    /// the key the app is actually using on this simulator.
    private let account = "unit-test-key"

    @Test("save → read → update → delete round trip")
    func roundTrip() {
        KeychainStore.delete(account: account)

        // Unsigned simulator test hosts can't reach the Keychain at all
        // (errSecMissingEntitlement, -34018). That's an environment limit, not
        // a code bug — the real app runs signed — so skip on exactly that
        // status rather than weakening the assertions for everyone.
        let status = KeychainStore.saveStatus("sk-ant-test-1", account: account)
        guard status != errSecMissingEntitlement else { return }
        #expect(status == errSecSuccess)
        #expect(KeychainStore.read(account: account) == "sk-ant-test-1")

        // Saving twice must update in place. `saveStatus` calls `SecItemUpdate`
        // first and only adds on `errSecItemNotFound`; get that order wrong and
        // the second save fails as a duplicate item.
        #expect(KeychainStore.save("sk-ant-test-2", account: account))
        #expect(KeychainStore.read(account: account) == "sk-ant-test-2")

        #expect(KeychainStore.delete(account: account))
        #expect(KeychainStore.read(account: account) == nil)
    }
}

// MARK: - Anthropic client

/// Captures the request and replays a canned 200, so the request shape can be
/// asserted without a key or a network call.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Replays a 401 — a rejected key, the failure a reader is most likely to hit.
final class UnauthorizedURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":{"message":"invalid x-api-key"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Anthropic client", .serialized)
struct AnthropicClientTests {

    private func client(stubbing protocolClass: URLProtocol.Type) -> AnthropicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [protocolClass]
        return AnthropicClient(session: URLSession(configuration: config))
    }

    @Test("sends the key and version headers to Anthropic, and extracts the text")
    func requestShape() async throws {
        StubURLProtocol.responseBody = Data(#"{"content":[{"type":"text","text":"hello"}]}"#.utf8)

        let text = try await client(stubbing: StubURLProtocol.self)
            .complete(system: "sys", user: "usr", apiKey: "sk-ant-unit")
        #expect(text == "hello")

        let request = try #require(StubURLProtocol.lastRequest)
        // The destination is part of the privacy claim: the key goes to
        // Anthropic directly and through no server of ours.
        #expect(request.url == AnthropicClient.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-unit")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

        let body = try #require(Self.body(of: request))
        let decoded = try #require(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(decoded["model"] as? String == AnthropicClient.model)
        #expect(decoded["system"] as? String == "sys")
        let messages = try #require(decoded["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "usr")
    }

    @Test("a rejected key surfaces the status and a message naming the key")
    func unauthorized() async throws {
        let thrown: (any Error)? = await {
            do {
                _ = try await client(stubbing: UnauthorizedURLProtocol.self)
                    .complete(system: "s", user: "u", apiKey: "bad")
                return nil
            } catch { return error }
        }()

        let error = try #require(thrown as? AnthropicClient.ClientError)
        guard case .badStatus(let code, _) = error else {
            Issue.record("expected badStatus, got \(error)")
            return
        }
        #expect(code == 401)
        // The reader has to be told to go fix the key, not shown a raw 401.
        #expect(error.errorDescription?.contains("key") == true)
    }

    @Test("a 200 carrying no text block is an error, not an empty answer")
    func emptyResponse() async throws {
        // Anthropic answers 200 with a `content` array that need not hold a
        // text block. Returning "" here would render as a blank explanation
        // rather than as the failure it is.
        StubURLProtocol.responseBody = Data(#"{"content":[]}"#.utf8)

        let thrown: (any Error)? = await {
            do {
                _ = try await client(stubbing: StubURLProtocol.self)
                    .complete(system: "s", user: "u", apiKey: "sk-ant-unit")
                return nil
            } catch { return error }
        }()

        let error = try #require(thrown as? AnthropicClient.ClientError)
        guard case .emptyResponse = error else {
            Issue.record("expected emptyResponse, got \(error)")
            return
        }
    }

    /// `URLProtocol` may deliver a body as a stream rather than as `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
