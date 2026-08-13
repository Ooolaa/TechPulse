import Testing
import Foundation
import SwiftData
@testable import TechPulse

@MainActor
@Suite("Knowledge engine", .serialized)
struct KnowledgeEngineTests {

    /// One in-memory container for the whole suite: repeated ModelContainer
    /// creation alongside the host app's live container traps in SwiftData.
    private static let sharedContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: FeedSource.self, Article.self, Concept.self,
            LearningEvent.self, ConceptLink.self, ConceptDependency.self, SemanticLink.self,
            configurations: config
        )
    }()

    /// Fresh logical state per test. Row-by-row deletes (not batch) so the
    /// Article↔Concept inverse relationship is nullified properly.
    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        for article in try context.fetch(FetchDescriptor<Article>()) { context.delete(article) }
        for concept in try context.fetch(FetchDescriptor<Concept>()) { context.delete(concept) }
        for link in try context.fetch(FetchDescriptor<ConceptLink>()) { context.delete(link) }
        for event in try context.fetch(FetchDescriptor<LearningEvent>()) { context.delete(event) }
        for source in try context.fetch(FetchDescriptor<FeedSource>()) { context.delete(source) }
        try context.save()
        return context
    }

    @Test("reading an article bumps concept mastery by 0.1 and logs an event")
    func readBump() throws {
        let context = try makeContext()
        let concept = Concept(name: "RAG", category: "LLMs", definition: "d")
        let article = Article(guid: "g", title: "t", content: "c",
                              publishedAt: .now, sourceName: "s")
        article.concepts = [concept]
        context.insert(article)

        KnowledgeEngine.recordRead(article, context: context)

        #expect(article.isRead)
        #expect(abs(concept.masteryLevel - 0.2) < 0.001)   // 0.1 new + 0.1 read
        let events = try context.fetch(FetchDescriptor<LearningEvent>())
        #expect(events.count == 1)
        #expect(events[0].kind == "read")

        // Second visit must not double-count.
        KnowledgeEngine.recordRead(article, context: context)
        #expect(abs(concept.masteryLevel - 0.2) < 0.001)
    }

    @Test("mark known sets mastery to 1.0 and pins the state")
    func markKnown() throws {
        let context = try makeContext()
        let concept = Concept(name: "LoRA", category: "LLMs", definition: "d")
        context.insert(concept)

        KnowledgeEngine.markKnown(concept, context: context)

        #expect(concept.masteryLevel == 1.0)
        #expect(concept.isMarkedKnown)
        #expect(concept.masteryState == .known)
    }

    @Test("pre-existing check tracks identity, not name — catches concepts matched via embedding similarity")
    func isNewlyCreatedTracksByIdentity() throws {
        let context = try makeContext()
        let concept = Concept(name: "Transformer", category: "LLMs", definition: "d")
        context.insert(concept)
        try context.save()

        let prior = try context.fetch(FetchDescriptor<Concept>())

        // Same instance as returned via any dedup path — including an
        // embedding-similarity match whose name never equals the lowercased
        // lookup key a caller checked beforehand.
        #expect(KnowledgeEngine.isNewlyCreated(concept, priorConcepts: prior) == false)

        let freshlyMade = Concept(name: "New concept", category: "LLMs", definition: "d")
        #expect(KnowledgeEngine.isNewlyCreated(freshlyMade, priorConcepts: prior) == true)
    }

    @Test("quiz pass adds 0.3, quiz miss only logs")
    func quizScoring() throws {
        let context = try makeContext()
        let concept = Concept(name: "MoE", category: "LLMs", definition: "d")
        context.insert(concept)

        KnowledgeEngine.recordQuizResult(concept, passed: true, context: context)
        #expect(abs(concept.masteryLevel - 0.4) < 0.001)   // 0.1 + 0.3

        KnowledgeEngine.recordQuizResult(concept, passed: false, context: context)
        #expect(abs(concept.masteryLevel - 0.4) < 0.001)

        let kinds = try context.fetch(FetchDescriptor<LearningEvent>()).map(\.kind).sorted()
        #expect(kinds == ["quizMissed", "quizPassed"])
    }

    @Test("time decay: -0.05 per stale month, marked-known floors at 0.8")
    func decay() throws {
        let context = try makeContext()
        let stale = Concept(name: "CNN", category: "Vision", definition: "d")
        stale.masteryLevel = 0.5
        stale.lastReviewed = .now.addingTimeInterval(-65 * 86_400)   // ~2 months
        let known = Concept(name: "SGD", category: "LLMs", definition: "d")
        known.isMarkedKnown = true
        known.masteryLevel = 1.0
        known.lastReviewed = .now.addingTimeInterval(-400 * 86_400)
        context.insert(stale)
        context.insert(known)

        KnowledgeEngine.applyTimeDecay(context: context)

        #expect(abs(stale.masteryLevel - 0.4) < 0.001)     // 0.5 - 2×0.05
        #expect(known.masteryLevel >= 0.8)                 // floor for known
    }

    @Test("Co-read Links are rebuilt from the readings, once per pair")
    func links() throws {
        let context = try makeContext()
        let a = Concept(name: "A", category: "LLMs", definition: "")
        let b = Concept(name: "B", category: "LLMs", definition: "")
        context.insert(a)
        context.insert(b)
        for index in 0..<2 {
            let article = Article(guid: "g\(index)", title: "t", content: "c",
                                  publishedAt: .now, sourceName: "s")
            article.concepts = [a, b]
            context.insert(article)
        }
        try context.save()

        KnowledgeEngine.rebuildCoreadLinks(context: context)

        let links = try context.fetch(FetchDescriptor<ConceptLink>())
        #expect(links.count == 1)
        #expect(links[0].weight == 2)               // two readings joined them
        #expect(links[0].strength > 0)
    }

    @Test("rebuilding twice leaves one scored link, not two")
    func rebuildIsIdempotent() throws {
        let context = try makeContext()
        let a = Concept(name: "A", category: "LLMs", definition: "")
        let b = Concept(name: "B", category: "LLMs", definition: "")
        context.insert(a)
        context.insert(b)
        let article = Article(guid: "g", title: "t", content: "c",
                              publishedAt: .now, sourceName: "s")
        article.concepts = [a, b]
        context.insert(article)
        try context.save()

        KnowledgeEngine.rebuildCoreadLinks(context: context)
        let first = try context.fetch(FetchDescriptor<ConceptLink>())
        KnowledgeEngine.rebuildCoreadLinks(context: context)
        let second = try context.fetch(FetchDescriptor<ConceptLink>())

        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(first[0].strength == second[0].strength)
    }

    @Test("a store scored before association existed is recomputed, never left half-scored")
    func staleLinksAreRescored() throws {
        let context = try makeContext()
        let a = Concept(name: "A", category: "LLMs", definition: "")
        let b = Concept(name: "B", category: "LLMs", definition: "")
        let c = Concept(name: "C", category: "LLMs", definition: "")
        for concept in [a, b, c] { context.insert(concept) }
        let article = Article(guid: "g", title: "t", content: "c",
                              publishedAt: .now, sourceName: "s")
        article.concepts = [a, b]
        context.insert(article)
        // What the old raw counter left behind: unscored, and naming a pair no
        // reading supports.
        context.insert(ConceptLink(conceptA: "A", conceptB: "C", weight: 9))
        try context.save()

        KnowledgeEngine.rebuildCoreadLinks(context: context)

        let links = try context.fetch(FetchDescriptor<ConceptLink>())
        #expect(links.allSatisfy { $0.strength > 0 })
        #expect(!links.contains { $0.conceptB == "C" || $0.conceptA == "C" })
    }

    @Test("a Concept no longer in the store leaves no link behind")
    func linksNeverNameMissingConcepts() throws {
        let context = try makeContext()
        let a = Concept(name: "A", category: "LLMs", definition: "")
        let b = Concept(name: "B", category: "LLMs", definition: "")
        context.insert(a)
        context.insert(b)
        let article = Article(guid: "g", title: "t", content: "c",
                              publishedAt: .now, sourceName: "s")
        article.concepts = [a, b]
        context.insert(article)
        try context.save()
        KnowledgeEngine.rebuildCoreadLinks(context: context)
        #expect(try context.fetch(FetchDescriptor<ConceptLink>()).count == 1)

        context.delete(b)
        try context.save()
        KnowledgeEngine.rebuildCoreadLinks(context: context)

        let stored = Set(try context.fetch(FetchDescriptor<Concept>()).map(\.name))
        let links = try context.fetch(FetchDescriptor<ConceptLink>())
        #expect(links.allSatisfy { stored.contains($0.conceptA) && stored.contains($0.conceptB) })
    }

    @Test("resume seed populates mastered concepts with links, and only once")
    func resumeSeed() throws {
        UserDefaults.standard.removeObject(forKey: "resumeKnowledgeSeeded")
        let context = try makeContext()

        SeedData.seedResumeKnowledgeIfNeeded(context: context)
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        #expect(concepts.count > 15)
        #expect(concepts.allSatisfy { $0.isMarkedKnown && $0.masteryLevel == 1.0 })

        // Seeding records the projects; the rebuild is what scores them. A
        // project's Concepts were met together, so they join up.
        #expect(try context.fetch(FetchDescriptor<ConceptLink>()).isEmpty)
        KnowledgeEngine.rebuildCoreadLinks(context: context)
        #expect(try !context.fetch(FetchDescriptor<ConceptLink>()).isEmpty)

        // Idempotent: second call must not duplicate.
        SeedData.seedResumeKnowledgeIfNeeded(context: context)
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == concepts.count)
        UserDefaults.standard.removeObject(forKey: "resumeKnowledgeSeeded")
    }
}
