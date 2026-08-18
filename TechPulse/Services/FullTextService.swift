import Foundation
import SwiftData

/// Fetches the real article text when the publisher's feed only carried a
/// snippet (Hugging Face and OpenAI ship none; DeepMind one line; The Verge a
/// teaser). Extraction is heuristic readability: prefer the <article> region,
/// take its paragraphs.
@MainActor
enum FullTextService {
    nonisolated static let snippetThreshold = 400

    static func needsFullText(_ article: Article) -> Bool {
        article.content.strippingHTML.count < snippetThreshold
            && article.link != nil
            && article.fullTextAttemptedAt == nil
    }

    /// One attempt per article; failures keep the snippet + Safari footer.
    static func fetchIfNeeded(_ article: Article, context: ModelContext) async {
        guard needsFullText(article),
              let link = article.link, let url = URL(string: link),
              url.scheme == "https" else { return }
        article.fullTextAttemptedAt = .now

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (iPhone) TechPulse/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              ResponseLimit.accepts(data: data, response: response),
              let html = String(data: data, encoding: .utf8)
        else { try? context.save(); return }

        if let text = extractReadableText(html: html),
           text.count > article.content.strippingHTML.count {
            article.content = text
            // Snippet-based summary/concepts are stale — regenerate from real text.
            article.summary = nil
            await IntelligenceService.reanalyze(article, context: context)
        }
        try? context.save()
    }

    /// Heuristic readability: paragraphs from the <article> region (else the
    /// whole page), tags/entities stripped. nil when the page yields too
    /// little (paywall, JS-only rendering). Pure string work — off-actor.
    nonisolated static func extractReadableText(html: String) -> String? {
        // Drop script/style bodies first so their text can't leak in.
        var cleaned = html
        for tag in ["script", "style", "noscript", "svg"] {
            cleaned = cleaned.replacingOccurrences(
                of: "<\(tag)[^>]*>.*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Prefer the semantic article region when present.
        let scope: String
        if let match = cleaned.range(of: "<article[^>]*>.*?</article>",
                                     options: [.regularExpression, .caseInsensitive]) {
            scope = String(cleaned[match])
        } else {
            scope = cleaned
        }

        var paragraphs: [String] = []
        var searchRange = scope.startIndex..<scope.endIndex
        while let match = scope.range(of: "<p[^>]*>.*?</p>",
                                      options: [.regularExpression, .caseInsensitive],
                                      range: searchRange) {
            let paragraph = String(scope[match]).strippingHTML
            // Skip boilerplate crumbs (share buttons, bylines, cookie notices).
            if paragraph.count > 60 {
                paragraphs.append(paragraph)
            }
            searchRange = match.upperBound..<scope.endIndex
        }

        let text = paragraphs.joined(separator: "\n\n")
        return text.count > snippetThreshold ? text : nil
    }
}
