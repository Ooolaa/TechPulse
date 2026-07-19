import Testing
import Foundation
@testable import TechPulse

@Suite("Topic search")
struct TopicSearchTests {
    @Test("arXiv query: https, phrase-quoted, separator-safe, capped results")
    func queryURL() throws {
        let url = try #require(TopicSearchService.queryURL(for: "LoRA / QLoRA"))
        let string = url.absoluteString
        #expect(string.hasPrefix("https://export.arxiv.org/api/query?"))
        #expect(string.contains("%22LoRA%20QLoRA%22"))   // slash dropped, phrase quoted
        #expect(string.contains("max_results=3"))
        #expect(string.contains("sortBy=submittedDate"))
    }

    @Test("query with nothing alphanumeric → nil, not a garbage request")
    func emptyQuery() {
        #expect(TopicSearchService.queryURL(for: " /·— ") == nil)
    }
}
