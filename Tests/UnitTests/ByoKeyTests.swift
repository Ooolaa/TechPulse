import Testing
import Foundation
@testable import TechPulse

// Coverage for the BYO-key path — the one place anything leaves the device
// besides a feed fetch and the arXiv topic search. `KeychainStore` and
// `AnthropicClient` were back-ported from CareerPulse on 2026-07-14 without
// their tests; these are those tests, brought across as CareerPulse retires
// (#16).

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
        // (errSecMissingEntitlement, -34018) — an environment limit, not a code
        // bug, since the real app runs signed. Bail on exactly that status, but
        // assert the one thing that must hold when we do: an unreachable
        // Keychain reads as empty. Otherwise this early return would be a way
        // for the whole test to pass having checked nothing, which is the
        // failure mode #16 found in the XXE test next door.
        let status = KeychainStore.saveStatus("sk-ant-test-1", account: account)
        guard status != errSecMissingEntitlement else {
            #expect(KeychainStore.read(account: account) == nil,
                    "Keychain unreachable here, so the round trip did not run")
            return
        }
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

/// Captures the request and replays a canned response, so the request shape can
/// be asserted without a key or a network call. One class rather than one per
/// status code: the status and body are the only things that vary.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func stub(status: Int, body: String) {
        Self.status = status
        Self.responseBody = Data(body.utf8)
        Self.lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Anthropic client", .serialized)
struct AnthropicClientTests {

    private var stubbedClient: AnthropicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return AnthropicClient(session: URLSession(configuration: config))
    }

    @Test("sends the key and version headers to Anthropic, and extracts the text")
    func requestShape() async throws {
        StubURLProtocol.stub(status: 200, body: #"{"content":[{"type":"text","text":"hello"}]}"#)

        let text = try await stubbedClient.complete(system: "sys", user: "usr",
                                                    apiKey: "sk-ant-unit")
        #expect(text == "hello")

        let request = try #require(StubURLProtocol.lastRequest)
        // The destination is part of the privacy claim: the key goes to
        // Anthropic directly and through no server of ours.
        #expect(request.url == AnthropicClient.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-unit")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

        let body = try #require(Self.body(of: request))
        let decoded = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(decoded["model"] as? String == AnthropicClient.model)
        #expect(decoded["system"] as? String == "sys")
        let messages = try #require(decoded["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "usr")
    }

    @Test("a rejected key surfaces the status and a message naming the key")
    func unauthorized() async throws {
        StubURLProtocol.stub(status: 401, body: #"{"error":{"message":"invalid x-api-key"}}"#)

        let error = try #require(await #expect(throws: AnthropicClient.ClientError.self) {
            _ = try await stubbedClient.complete(system: "s", user: "u", apiKey: "bad")
        })
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
        StubURLProtocol.stub(status: 200, body: #"{"content":[]}"#)

        let error = try #require(await #expect(throws: AnthropicClient.ClientError.self) {
            _ = try await stubbedClient.complete(system: "s", user: "u", apiKey: "sk-ant-unit")
        })
        guard case .emptyResponse = error else {
            Issue.record("expected emptyResponse, got \(error)")
            return
        }
    }

    /// The fourth fetcher. `PRIVACY.md` claims the 5 MB cap for every response
    /// the app fetches, and the model's reply is one of them — a claim that was
    /// false the moment it was widened for #28 unless this path is bounded too.
    @Test("an over-cap reply is refused before it is decoded")
    func oversizedResponse() async throws {
        // Valid JSON that would parse to "hello", padded past the cap. The only
        // reason to refuse it is its size.
        let padding = String(repeating: "x", count: ResponseLimit.maxBytes)
        StubURLProtocol.stub(status: 200,
                             body: #"{"content":[{"type":"text","text":"hello"}],"pad":"\#(padding)"}"#)

        let error = try #require(await #expect(throws: AnthropicClient.ClientError.self) {
            _ = try await stubbedClient.complete(system: "s", user: "u", apiKey: "sk-ant-unit")
        })
        guard case .oversizedResponse = error else {
            Issue.record("expected oversizedResponse, got \(error)")
            return
        }
    }

    @Test("the same reply under the cap is decoded, so the refusal is the cap")
    func underCapResponseIsDecoded() async throws {
        StubURLProtocol.stub(status: 200, body: #"{"content":[{"type":"text","text":"hello"}]}"#)
        let text = try await stubbedClient.complete(system: "s", user: "u", apiKey: "sk-ant-unit")
        #expect(text == "hello")
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
