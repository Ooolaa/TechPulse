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

        for article in pending {
            let analysis = await analyze(article)
            apply(analysis, to: article, context: context)
            try? context.save()
        }
    }

    private static func analyze(_ article: Article) async -> ArticleAnalysis {
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
        return fallbackAnalysis(title: article.title, body: body)
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

        linkCooccurrences(attached, context: context)
    }

    /// Two concepts in the same article get an edge; weight counts co-occurrences.
    private static func linkCooccurrences(_ concepts: [Concept], context: ModelContext) {
        guard concepts.count > 1 else { return }
        let links = (try? context.fetch(FetchDescriptor<ConceptLink>())) ?? []
        var byPair = Dictionary(links.map { ([$0.conceptA, $0.conceptB].sorted().joined(separator: "|"), $0) },
                                uniquingKeysWith: { first, _ in first })
        let names = concepts.map(\.name).sorted()
        for i in names.indices {
            for j in names.indices where j > i {
                let key = "\(names[i])|\(names[j])"
                if let link = byPair[key] {
                    link.weight += 1
                } else {
                    let link = ConceptLink(conceptA: names[i], conceptB: names[j])
                    context.insert(link)
                    byPair[key] = link
                }
            }
        }
    }

    // MARK: Fallback (no Apple Intelligence): NaturalLanguage keyword extraction

    private static func fallbackAnalysis(title: String, body: String) -> ArticleAnalysis {
        // Summary: leading body sentences up to ~260 characters; empty when the
        // feed carries no body text (UI hides empty summaries).
        var summary = ""
        let sentences = NLTokenizer(unit: .sentence)
        sentences.string = body
        sentences.enumerateTokens(in: body.startIndex..<body.endIndex) { range, _ in
            summary += String(body[range])
            return summary.count < 260
        }
        let text = "\(title) \(body)"

        // Concepts: recurring capitalized nouns (crude but offline-safe).
        var counts: [String: Int] = [:]
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            if tag == .noun {
                let word = String(text[range])
                if word.count > 3, word.first?.isUppercase == true {
                    counts[word, default: 0] += 1
                }
            }
            return true
        }
        let concepts = counts.filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ExtractedConcept(name: $0.key, category: "Open Source", definition: "") }

        return ArticleAnalysis(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            concepts: Array(concepts)
        )
    }
}
