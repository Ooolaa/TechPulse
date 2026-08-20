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

@Generable
struct ConceptExpansion {
    @Guide(description: "3 to 5 narrower or adjacent technical sub-concepts a learner should explore next to deepen this concept")
    var subConcepts: [ExtractedConcept]
}

@Generable
struct TermDefinition {
    @Guide(description: "Short canonical name for the term, properly capitalized")
    var name: String
    @Guide(description: "One-line beginner-friendly explanation of the term as used in this excerpt")
    var definition: String
}

// MARK: - Service

/// On-device analysis: summarize + extract concepts via Foundation Models,
/// falling back to NaturalLanguage keyword extraction when Apple Intelligence
/// is unavailable (spec §5 rules).
///
/// Summarizing and extracting never leave the device. Two features here do, and
/// only if the reader added their own Anthropic key: "Go deeper" and Explain,
/// each described in `PRIVACY.md` and bounded by `Egress`. This comment used to
/// say "nothing leaves the device" flatly, in the one file where that is not
/// true — the same drift #29 was about.
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
        // Once, for the whole batch: scoring is over every reading at once, so
        // there is nothing to gain from rebuilding after each article.
        KnowledgeEngine.rebuildCoreadLinks(context: context)
    }

    private static func analyze(_ article: Article,
                                vocabulary: [(name: String, category: String, definition: String)]) async -> ArticleAnalysis {
        let body = String(article.content.strippingHTML.prefix(3000))
        if isModelAvailable {
            let session = LanguageModelSession(
                instructions: "You extract technical concepts from tech/AI news articles."
            )
            let prompt = "\(article.title)\n\n\(body)"
            if let response = try? await session.respond(to: prompt, generating: ArticleAnalysis.self),
               !response.content.concepts.isEmpty {
                // An answer naming no Concept is not better information than
                // the Pack's own vocabulary sitting in the text, and taking it
                // would retire the Article from analysis having attached
                // nothing (#38).
                return response.content
            }
        }
        // Fallback works on the body only — echoing the title back as a
        // "summary" is worse than showing nothing.
        return fallbackAnalysis(title: article.title, body: body, vocabulary: vocabulary)
    }

    /// Re-run analysis for one article (e.g. after full text replaced a snippet).
    static func reanalyze(_ article: Article, context: ModelContext) async {
        let vocabulary = ((try? context.fetch(FetchDescriptor<Concept>())) ?? [])
            .map { (name: $0.name, category: $0.category, definition: $0.conceptDefinition) }
        let analysis = await analyze(article, vocabulary: vocabulary)
        apply(analysis, to: article, context: context)
        try? context.save()
        // This article's Concepts changed, so the readings behind the map did.
        KnowledgeEngine.rebuildCoreadLinks(context: context)
    }

    // MARK: "Go deeper" — grow the map outward from a concept (pull direction)

    /// Expands a concept into 3–5 related sub-concepts, added as dim dots on
    /// the same cluster island and linked to the parent. Requires the
    /// on-device model; returns the newly attached concepts.
    static var canDeepen: Bool { isModelAvailable || KeychainStore.hasAnthropicKey }

    private struct RemoteExpansion: Decodable {
        struct Item: Decodable { let name: String; let definition: String }
        let subConcepts: [Item]
    }

    private struct RemoteDefinition: Decodable { let name: String; let definition: String }

    /// Explain a term the reader selected in an article body.
    ///
    /// Mirrors `deepen`'s three tiers so this keeps working on hardware without
    /// Apple Intelligence: on-device model, else the reader's own Anthropic key,
    /// else nil. Persists through `findOrCreateConcept`, which dedupes by name
    /// and embedding similarity — so looking up a synonym of something already
    /// on the map joins that dot instead of creating a twin.
    ///
    /// The two tiers ask different questions, deliberately (ADR-0006). On-device
    /// the excerpt disambiguates and never leaves the phone; on the opt-in path
    /// the reader's own Active Pack does that job instead, so no passage of the
    /// article is sent — only the term the reader selected, which is article
    /// text and is the most of one that ever leaves (#32). `ExplainPrompt`
    /// builds both, purely, so which is which is a test.
    static func define(term: String, excerpt: String,
                       context: ModelContext) async -> Concept? {
        // Chosen once, purely, and then followed. The tier picks the prompt and
        // the transport together, so neither branch can end up holding the
        // other's payload — the slip that would put article text back on the
        // wire is now a change to `ExplainTier`/`forTier`, which a test watches.
        let pack = ActivePack.inUse
        let tier = ExplainTier.choose(modelAvailable: isModelAvailable,
                                      hasKey: KeychainStore.hasAnthropicKey)
        guard let prompt = ExplainPrompt.forTier(tier, term: term, excerpt: excerpt,
                                                 field: pack.field,
                                                 clusters: pack.clusterOrder)
        else { return nil }

        var result: (name: String, definition: String)?

        switch tier {
        case .onDevice:
            let session = LanguageModelSession(instructions: prompt.system)
            guard let response = try? await session.respond(to: prompt.user,
                                                            generating: TermDefinition.self)
            else { return nil }
            result = (response.content.name, response.content.definition)
        case .optIn:
            guard let key = KeychainStore.read(),
                  let text = try? await AnthropicClient().complete(system: prompt.system,
                                                                   user: prompt.user,
                                                                   maxTokens: 512, apiKey: key),
                  let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
                  let parsed = try? JSONDecoder().decode(RemoteDefinition.self,
                                                         from: Data(String(text[start...end]).utf8))
            else { return nil }
            result = (parsed.name, parsed.definition)
        case .unavailable:
            return nil          // unreachable: `forTier` already returned nil
        }

        guard let result, !result.definition.isEmpty else { return nil }

        let allConcepts = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        var cache = Dictionary(allConcepts.map { ($0.name.lowercased(), $0) },
                               uniquingKeysWith: { first, _ in first })

        // Prefer the model's canonical name, but never let it drift into
        // something unrelated to what the reader actually selected.
        let name = result.name.isEmpty ? term : result.name
        guard let concept = KnowledgeEngine.findOrCreateConcept(
            named: name, category: WordSelection.cluster,
            definition: result.definition, context: context, cache: &cache
        ) else { return nil }

        // Asked of the concept that came back, not of the name that went in:
        // an embedding match returns a concept whose name differs from the key.
        if KnowledgeEngine.isNewlyCreated(concept, priorConcepts: allConcepts) {
            concept.masteryLevel = 0.0                     // new dots arrive dim
        }
        try? context.save()
        return concept
    }

    static func deepen(_ concept: Concept, context: ModelContext) async -> [Concept] {
        let prompt = "Concept: \(concept.name)\nDefinition: \(concept.conceptDefinition)\nCluster: \(concept.category)"
        var items: [(name: String, definition: String)] = []

        if isModelAvailable {
            let session = LanguageModelSession(
                instructions: "You suggest narrower technical sub-concepts that deepen a learner's understanding of a given concept. Each needs a one-line beginner definition."
            )
            guard let response = try? await session.respond(to: prompt, generating: ConceptExpansion.self)
            else { return [] }
            items = response.content.subConcepts.map { ($0.name, $0.definition) }
        } else if let key = KeychainStore.read() {
            // BYO key: same request, direct to Anthropic, typed JSON only.
            let system = """
            You suggest 3-5 narrower sub-concepts that deepen a learner's \
            understanding of a concept. Reply ONLY with JSON: \
            {"subConcepts":[{"name":str,"definition":str}]}
            """
            guard let text = try? await AnthropicClient().complete(system: system, user: prompt,
                                                                   maxTokens: 1024, apiKey: key),
                  let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
                  let parsed = try? JSONDecoder().decode(RemoteExpansion.self,
                                                         from: Data(String(text[start...end]).utf8))
            else { return [] }
            items = parsed.subConcepts.map { ($0.name, $0.definition) }
        } else {
            return []
        }

        let allConcepts = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        var cache = Dictionary(allConcepts.map { ($0.name.lowercased(), $0) },
                               uniquingKeysWith: { first, _ in first })
        var added: [Concept] = []
        for extracted in items.prefix(5) {
            guard let child = KnowledgeEngine.findOrCreateConcept(
                named: extracted.name,
                category: concept.category,     // grow on the parent's island
                definition: extracted.definition,
                context: context, cache: &cache
            ), child.name != concept.name else { continue }
            // Asked of the concept that came back, not of the name that went
            // in: an embedding match returns a concept named something else.
            if KnowledgeEngine.isNewlyCreated(child, priorConcepts: allConcepts) {
                child.masteryLevel = 0.0        // brand-new dots arrive dim
            }
            // No Co-read Link is written between parent and child. ADR-0002:
            // a Co-read Link records what you actually read together, and a
            // sub-concept the model just invented is not that. The child joins
            // the map through the reading that turns it up — the same rule
            // that stopped Dependencies being mirrored as Co-read Links in #4.
            added.append(child)
        }
        try? context.save()
        return added
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
        // Attaching the Concepts *is* recording the reading: Co-read Links are
        // derived from this relationship, and rebuilt once the batch is done
        // rather than edge-by-edge as each article lands.
        article.concepts = attached
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
