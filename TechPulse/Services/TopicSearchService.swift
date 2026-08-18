import Foundation
import SwiftData

/// On-demand article discovery for a single topic — the "pull" direction for
/// content, like Go deeper is for concepts: when a topic has few or no
/// articles, fetch the newest matching papers from the arXiv API (Atom, the
/// same format the feed parser already speaks) and file them as articles
/// tagged to that concept. User-initiated, so results bypass the daily
/// intake cap the same way Go deeper does.
@MainActor
enum TopicSearchService {
    /// arXiv search: newest submissions matching the topic as a phrase.
    /// Pack names can carry separators ("LoRA / QLoRA") that break the query —
    /// normalize to plain words first. Returns nil if nothing queryable remains.
    nonisolated static func queryURL(for topic: String, limit: Int = 3) -> URL? {
        let words = topic
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [
            .init(name: "search_query", value: "all:\"\(words.joined(separator: " "))\""),
            .init(name: "sortBy", value: "submittedDate"),
            .init(name: "sortOrder", value: "descending"),
            .init(name: "max_results", value: String(limit)),
        ]
        return components.url
    }

    /// Fetches up to `limit` fresh articles for the concept and tags them to
    /// it. Returns how many articles are newly tagged (inserted or, if the
    /// paper was already cached, linked).
    @discardableResult
    static func findArticles(for concept: Concept, context: ModelContext,
                             limit: Int = 3) async -> Int {
        guard let url = queryURL(for: concept.name, limit: limit) else { return 0 }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(FeedSyncService.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              ResponseLimit.accepts(data: data, response: response)
        else { return 0 }

        let existing = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        let byGuid = Dictionary(existing.map { ($0.guid, $0) },
                                uniquingKeysWith: { first, _ in first })
        var tagged = 0
        for item in RSSParser.parse(data).prefix(limit) where !item.guid.isEmpty {
            let article: Article
            if let cached = byGuid[item.guid] {
                article = cached
            } else {
                article = Article(
                    guid: item.guid,
                    title: item.title.strippingHTML,
                    content: item.content,
                    publishedAt: min(item.publishedAt ?? .now, .now),
                    sourceName: "arXiv topic search",
                    link: item.link.isEmpty ? nil : item.link
                )
                context.insert(article)
            }
            if !article.concepts.contains(where: { $0.name == concept.name }) {
                article.concepts.append(concept)
                tagged += 1
            }
        }
        try? context.save()
        return tagged
    }
}
