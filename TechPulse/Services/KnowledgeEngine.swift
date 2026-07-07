import Foundation
import NaturalLanguage
import SwiftData

/// Mastery scoring + concept matching (spec §6).
/// Scoring: new = 0.1 · article read = +0.1 · "I know this" = 1.0 ·
/// quiz passed = +0.3 · decay = −0.05/month without review.
/// Every change writes a LearningEvent (fuel for Progress charts).
@MainActor
enum KnowledgeEngine {

    // MARK: Concept matching

    /// Case-insensitive match first, then embedding similarity to catch
    /// near-duplicates ("LLM" ≈ "Large Language Models"). Creates when new.
    static func findOrCreateConcept(named rawName: String, category: String,
                                    definition: String, context: ModelContext,
                                    cache: inout [String: Concept]) -> Concept? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count > 1 else { return nil }

        if let exact = cache[name.lowercased()] { return exact }
        if let similar = embeddingMatch(for: name, in: cache) { return similar }

        let concept = Concept(name: name, category: category, definition: definition)
        context.insert(concept)
        cache[name.lowercased()] = concept
        return concept
    }

    private static func embeddingMatch(for name: String, in cache: [String: Concept]) -> Concept? {
        // O(n) scan is fine at personal-knowledge-base scale; skip past it.
        guard cache.count < 500,
              let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        var best: (concept: Concept, distance: Double)?
        for concept in cache.values {
            let distance = embedding.distance(between: name.lowercased(),
                                              and: concept.name.lowercased())
            // Conservative threshold: merging distinct concepts is worse than
            // occasionally storing near-duplicates.
            if distance < 0.25, distance < (best?.distance ?? .infinity) {
                best = (concept, distance)
            }
        }
        return best?.concept
    }

    // MARK: Mastery events

    /// First read of an article: mark read and bump each attached concept.
    static func recordRead(_ article: Article, context: ModelContext) {
        guard !article.isRead else { return }
        article.isRead = true
        article.readAt = .now
        for concept in article.concepts where !concept.isMarkedKnown {
            let delta = min(1.0, concept.masteryLevel + 0.1) - concept.masteryLevel
            concept.masteryLevel += delta
            concept.lastReviewed = .now
            context.insert(LearningEvent(kind: "read", conceptName: concept.name,
                                         masteryDelta: delta))
        }
        try? context.save()
    }

    /// Quiz result (spec §6): passed = +0.3 mastery; a miss only logs the event
    /// so the concept resurfaces next week.
    static func recordQuizResult(_ concept: Concept, passed: Bool, context: ModelContext) {
        if passed {
            let delta = min(1.0, concept.masteryLevel + 0.3) - concept.masteryLevel
            concept.masteryLevel += delta
            concept.lastReviewed = .now
            context.insert(LearningEvent(kind: "quizPassed", conceptName: concept.name,
                                         masteryDelta: delta))
        } else {
            context.insert(LearningEvent(kind: "quizMissed", conceptName: concept.name,
                                         masteryDelta: 0))
        }
        try? context.save()
    }

    /// Pairwise co-occurrence links between concepts that appeared together
    /// (same article, or same project when seeding from the resume).
    static func linkCooccurring(_ concepts: [Concept], context: ModelContext) {
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

    static func markKnown(_ concept: Concept, context: ModelContext) {
        guard !concept.isMarkedKnown else { return }
        let delta = 1.0 - concept.masteryLevel
        concept.masteryLevel = 1.0
        concept.isMarkedKnown = true
        concept.lastReviewed = .now
        context.insert(LearningEvent(kind: "markedKnown", conceptName: concept.name,
                                     masteryDelta: delta))
        try? context.save()
    }

    /// Spaced-repetition flavor: −0.05 per full month without review.
    /// Call at launch; touching lastReviewed restarts the clock so a decay
    /// is applied at most once per elapsed month.
    static func applyTimeDecay(context: ModelContext) {
        let concepts = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        let month: TimeInterval = 30 * 86_400
        for concept in concepts {
            let reference = concept.lastReviewed ?? concept.firstSeen
            let elapsedMonths = (Date.now.timeIntervalSince(reference) / month).rounded(.down)
            guard elapsedMonths >= 1 else { continue }
            let floorLevel = concept.isMarkedKnown ? 0.8 : 0.05
            let decayed = max(floorLevel, concept.masteryLevel - 0.05 * elapsedMonths)
            let delta = decayed - concept.masteryLevel
            guard delta < 0 else { continue }
            concept.masteryLevel = decayed
            concept.lastReviewed = .now
            context.insert(LearningEvent(kind: "decay", conceptName: concept.name,
                                         masteryDelta: delta))
        }
        try? context.save()
    }
}
