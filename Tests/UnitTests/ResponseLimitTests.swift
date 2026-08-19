import Testing
import Foundation
import SwiftData
@testable import TechPulse

// One bound, three fetchers. `FeedSyncService` and `FullTextService` each
// carried their own copy of it and `TopicSearchService` carried none, so a
// search response — a URL built from a search term rather than from a Source
// the reader enabled — was handed to `RSSParser` at whatever size arrived (#28).

@Suite("Response limit")
struct ResponseLimitTests {

    private func ok(_ bytes: Int) -> (Data, URLResponse) {
        (Data(repeating: 0x61, count: bytes),
         HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200,
                         httpVersion: nil, headerFields: nil)!)
    }

    @Test("a response within the cap is worth parsing")
    func underCap() {
        let (data, response) = ok(1_000)
        #expect(ResponseLimit.accepts(data: data, response: response))
    }

    /// The documented promise is that responses *over* 5 MB are discarded, so
    /// exactly 5 MB is accepted. `FullTextService` used `<` and was stricter by
    /// one byte than the sentence in `PRIVACY.md`; this is the sentence.
    @Test("a response of exactly the cap is accepted, because the claim is 'over'")
    func exactlyAtCap() {
        let (data, response) = ok(ResponseLimit.maxBytes)
        #expect(ResponseLimit.accepts(data: data, response: response))
    }

    @Test("a response over the cap is refused")
    func overCap() {
        let (data, response) = ok(ResponseLimit.maxBytes + 1)
        #expect(!ResponseLimit.accepts(data: data, response: response))
    }

    @Test("a non-2xx response is refused whatever its size")
    func badStatus() {
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!,
                                       statusCode: 404, httpVersion: nil, headerFields: nil)!
        #expect(!ResponseLimit.accepts(data: Data("small".utf8), response: response))
    }

    /// Matches what all three fetchers did before: a response that isn't HTTP
    /// has no status to judge, so only the size decides.
    @Test("a non-HTTP response is judged on size alone")
    func nonHTTPResponse() {
        let response = URLResponse(url: URL(string: "https://example.com")!,
                                   mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(ResponseLimit.accepts(data: Data("small".utf8), response: response))
        #expect(!ResponseLimit.accepts(data: Data(repeating: 0x61, count: ResponseLimit.maxBytes + 1),
                                       response: response))
    }
}

// MARK: - Driving the service over a real over-cap response

/// Stubs the arXiv host only, so nothing else a parallel test does is affected.
///
/// Registered globally rather than through an injected `URLSession`, because
/// `TopicSearchService` has no session to inject and adding one would be
/// production surface bought for a test — the trade ADR-0006 weighed for
/// `AnthropicClient` ("transport is not what anyone got wrong"). `AnthropicClient`
/// does carry a `session` property, which `ByoKeyTests` uses through
/// `URLSessionConfiguration.protocolClasses`; that is the scoped form of this
/// same technique, and the reason the two stubs cannot collide.
final class ArxivStub: URLProtocol, @unchecked Sendable {
    /// Written on the main actor before the fetch is awaited and read on
    /// `URLSession`'s queue after — a happens-before the `.serialized` suite
    /// keeps true by never letting two tests overlap on it.
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "export.arxiv.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("Topic search against the cap", .serialized)
struct TopicSearchCapTests {

    private static let sharedContainer: ModelContainer = {
        return try! AppSchema.inMemoryContainer()
    }()

    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        for article in try context.fetch(FetchDescriptor<Article>()) { context.delete(article) }
        for concept in try context.fetch(FetchDescriptor<Concept>()) { context.delete(concept) }
        try context.save()
        return context
    }

    /// A valid Atom entry, padded past the cap by a comment the parser would
    /// otherwise skip — so the *only* reason to refuse it is its size.
    private func atomFeed(id: String, padding: Int) -> Data {
        let filler = String(repeating: "x", count: padding)
        return Data("""
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>A survey of sparse attention</title>
            <id>\(id)</id>
            <link href="https://arxiv.org/abs/2608.00001"/>
            <summary>Short summary.</summary>
            <updated>2026-08-01T08:30:00Z</updated>
          </entry>
          <!-- \(filler) -->
        </feed>
        """.utf8)
    }

    @Test("an over-cap search response is refused before it is parsed")
    func overCapIsNotParsed() async throws {
        let context = try makeContext()
        let concept = Concept(name: "Sparse Attention", category: "LLMs", definition: "d")
        context.insert(concept)

        URLProtocol.registerClass(ArxivStub.self)
        defer { URLProtocol.unregisterClass(ArxivStub.self) }
        ArxivStub.body = atomFeed(id: "arxiv:over-cap", padding: ResponseLimit.maxBytes)

        let tagged = await TopicSearchService.findArticles(for: concept, context: context)

        #expect(tagged == 0)
        #expect(try context.fetch(FetchDescriptor<Article>()).isEmpty,
                "an over-cap response must leave nothing behind, not a partly filed Article")
    }

    /// The control. Without it, the test above passes just as well when the
    /// stub never intercepts and the fetch simply fails — which is exactly the
    /// green-for-the-wrong-reason #26 and #30 were about.
    @Test("the same feed under the cap is parsed, so the refusal is the cap and not the stub")
    func underCapIsParsed() async throws {
        let context = try makeContext()
        let concept = Concept(name: "Rotary Embeddings", category: "LLMs", definition: "d")
        context.insert(concept)

        URLProtocol.registerClass(ArxivStub.self)
        defer { URLProtocol.unregisterClass(ArxivStub.self) }
        ArxivStub.body = atomFeed(id: "arxiv:under-cap", padding: 0)

        let tagged = await TopicSearchService.findArticles(for: concept, context: context)

        #expect(tagged == 1)
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 1)
    }
}
