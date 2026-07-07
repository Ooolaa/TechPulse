import Foundation
import FoundationModels
import NaturalLanguage
import SwiftData

// MARK: - Structured output (spec §5)

@Generable
struct ArticleAnalysis {
    @Guide(description: "3-sentence plain-language summary of the article")
    var summary: String
    @Guide(description: "3 to 8 key technical concepts mentioned in the article")
    var concepts: [ExtractedConcept]
}

@Generable
struct ExtractedConcept {
    @Guide(description: "Short canonical concept name, e.g. 'RAG', 'Quantization', 'Mixture of Experts'")
    var name: String
    @Guide(description: "Exactly one of: LLMs, Agents, Vision, Robotics, Hardware/Chips, Policy/Safety, Open Source")
    var category: String
    @Guide(description: "One-line beginner-friendly explanation of the concept")
    var definition: String
}

// MARK: - Service

/// On-device analysis: summarize + extract concepts via Foundation Models,
/// falling back to NaturalLanguage keyword extraction when Apple Intelligence
/// is unavailable (spec §5 rules). Nothing leaves the device.
@MainActor
enum IntelligenceService {
    static var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Analyze up to `limit` articles that have no summary yet, newest first.
    /// Batched so a large first sync doesn't monopolize launch or battery.
    static func analyzePending(context: ModelContext, limit: Int = 8) async {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.summary == nil },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        let vocabulary = ((try? context.fetch(FetchDescriptor<Concept>())) ?? [])
            .map { (name: $0.name, category: $0.category, definition: $0.conceptDefinition) }
        for article in pending {
            let analysis = await analyze(article, vocabulary: vocabulary)
            apply(analysis, to: article, context: context)
            try? context.save()
        }
    }

    private static func analyze(_ article: Article,
                                vocabulary: [(name: String, category: String, definition: String)]) async -> ArticleAnalysis {
        let body = String(article.content.strippingHTML.prefix(3000))
        if isModelAvailable {
            let session = LanguageModelSession(
                instructions: "You extract technical concepts from tech/AI news articles."
            )
            let prompt = "\(article.title)\n\n\(body)"
            if let response = try? await session.respond(to: prompt, generating: ArticleAnalysis.self) {
                return response.content
            }
        }
        // Fallback works on the body only — echoing the title back as a
        // "summary" is worse than showing nothing.
        return fallbackAnalysis(title: article.title, body: body, vocabulary: vocabulary)
    }

    // MARK: Apply results to the store

    private static func apply(_ analysis: ArticleAnalysis, to article: Article, context: ModelContext) {
        article.summary = analysis.summary

        let allConcepts = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        var cache = Dictionary(allConcepts.map { ($0.name.lowercased(), $0) },
                               uniquingKeysWith: { first, _ in first })

        var attached: [Concept] = []
        for extracted in analysis.concepts where attached.count < 8 {
            guard let concept = KnowledgeEngine.findOrCreateConcept(
                named: extracted.name, category: extracted.category,
                definition: extracted.definition, context: context, cache: &cache
            ) else { continue }
            if !attached.contains(where: { $0.name == concept.name }) {
                attached.append(concept)
            }
        }
        article.concepts = attached

        KnowledgeEngine.linkCooccurring(attached, context: context)
    }

    // MARK: Fallback (no Apple Intelligence): vocabulary matching

    /// Match article text against concepts the app already knows (pack +
    /// resume + model-extracted). High precision, zero junk: no new concepts
    /// are invented on this path — that needs the real model.
    static func fallbackAnalysis(title: String, body: String,
                                 vocabulary: [(name: String, category: String, definition: String)]) -> ArticleAnalysis {
        // Summary: leading body sentences up to ~260 characters; empty when the
        // feed carries no body text (UI hides empty summaries).
        var summary = ""
        let sentences = NLTokenizer(unit: .sentence)
        sentences.string = body
        sentences.enumerateTokens(in: body.startIndex..<body.endIndex) { range, _ in
            summary += String(body[range])
            return summary.count < 260
        }

        let haystack = "\(title) \(body)"
        var concepts: [ExtractedConcept] = []
        for item in vocabulary {
            guard item.name.count > 2, concepts.count < 8 else { continue }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: item.name))\\b"
            if haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                concepts.append(ExtractedConcept(name: item.name, category: item.category,
                                                 definition: item.definition))
            }
        }

        return ArticleAnalysis(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            concepts: concepts
        )
    }
}
