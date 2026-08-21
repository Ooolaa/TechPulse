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

    /// Case-insensitive match first, then meaning. Creates when new.
    ///
    /// This used to say it catches "LLM" ≈ "Large Language Models". Measured,
    /// the embedding puts that pair at 1.26 against a threshold of 0.25 — five
    /// times outside it — and a plural at 0.42. So the meaning half currently
    /// merges nothing a name match would miss, which `ConceptDedupeTests`
    /// records. Removing the 500-Concept ceiling (#11) makes the scan run at
    /// any map size; what it admits is a separate question, and answering it
    /// means calibrating the threshold against real Concept names the way
    /// `SemanticLinker` calibrated its floor.
    ///
    /// Both halves live in `ConceptIndex`, which holds each name's meaning
    /// rather than recomputing it — the cost that used to make this give up
    /// entirely above 500 Concepts (#11). Synchronous, and callable from inside
    /// loops that already hold the main actor, because the index arrives with
    /// the map's meanings already computed: see `ConceptIndex.prepared` (#42).
    static func findOrCreateConcept(named rawName: String, category: String,
                                    definition: String, context: ModelContext,
                                    index: inout ConceptIndex) -> Concept? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count > 1 else { return nil }

        if let existing = index.match(name) { return existing }

        let concept = Concept(name: name, category: category, definition: definition)
        context.insert(concept)
        index.insert(concept)
        return concept
    }

    /// True when `concept` wasn't in the store before this dedup pass.
    /// Checked by identity, not name: `findOrCreateConcept` may return a
    /// pre-existing concept matched by meaning, whose name won't equal the
    /// lowercased key a caller checked beforehand.
    static func isNewlyCreated(_ concept: Concept, priorConcepts: [Concept]) -> Bool {
        !priorConcepts.contains { $0 === concept }
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
        WidgetRefresh.refresh(context: context)
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

    /// Rebuilds every Co-read Link from the readings that justify them.
    ///
    /// Derived rather than accumulated, which is what makes ADR-0002's pruning
    /// safe: the reading record — the Concepts an Article carries, the Concepts
    /// a project used — is the truth, and the links are a scored view of it.
    /// Dropping a weak link therefore throws no evidence away, so a pair that
    /// goes on being read together earns its way back. A counter that pruned
    /// itself could not: every prune would reset the count that was meant to
    /// prove the pair mattered.
    ///
    /// Idempotent, and cheap enough to run at launch — which is also how a
    /// store written before scoring existed gets recomputed rather than left
    /// half-scored.
    static func rebuildCoreadLinks(context: ModelContext) {
        let known = Set(((try? context.fetch(FetchDescriptor<Concept>())) ?? []).map(\.name))

        // A reading is a group of Concepts met together. Filtered against the
        // store, so a group can never name a Concept no fetch would find.
        //
        // Only articles the reader actually opened count. Analysis attaches
        // Concepts to every *cached* article, so counting those would wire the
        // map from a feed nobody read — and `isRead` is already the app's
        // definition of reading, the one Mastery, Lit state and the Streak use.
        // Semantic Links are what made this affordable: before them, a reader
        // on day one would have been left with the unconnected dust ADR-0002
        // set out to end.
        var readings: [[String]] = []
        let articles = FetchDescriptor<Article>(predicate: #Predicate { $0.isRead })
        for article in (try? context.fetch(articles)) ?? [] {
            let names = article.concepts.map(\.name).filter(known.contains)
            if names.count > 1 { readings.append(names) }
        }
        for project in SeedData.resumeCoreadGroups {
            let names = project.filter(known.contains)
            if names.count > 1 { readings.append(names) }
        }

        for link in (try? context.fetch(FetchDescriptor<ConceptLink>())) ?? [] {
            context.delete(link)
        }
        for edge in CoreadScoring.score(readings) {
            context.insert(ConceptLink(conceptA: edge.conceptA, conceptB: edge.conceptB,
                                       weight: edge.readings, strength: edge.strength))
        }
        try? context.save()
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
        WidgetRefresh.refresh(context: context)
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
