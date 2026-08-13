import Testing
import Foundation
import SwiftData
@testable import TechPulse

@MainActor
@Suite("Knowledge path engine", .serialized)
struct KnowledgePathTests {

    private static let sharedContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: FeedSource.self, Article.self, Concept.self,
            LearningEvent.self, ConceptLink.self, ConceptDependency.self, SemanticLink.self,
            configurations: config
        )
    }()

    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        for article in try context.fetch(FetchDescriptor<Article>()) { context.delete(article) }
        for concept in try context.fetch(FetchDescriptor<Concept>()) { context.delete(concept) }
        for link in try context.fetch(FetchDescriptor<ConceptLink>()) { context.delete(link) }
        for dep in try context.fetch(FetchDescriptor<ConceptDependency>()) { context.delete(dep) }
        try context.save()
        return context
    }

    private func concept(_ name: String, _ category: String, lit: Bool) -> Concept {
        let c = Concept(name: name, category: category, definition: "d")
        c.masteryLevel = lit ? 0.5 : 0.0
        return c
    }

    @Test("frontier: ready only when every prerequisite is lit, pack concepts only")
    func frontier() {
        let linalg = concept("Linear Algebra", "Foundations", lit: true)
        let embeddings = concept("Embeddings", "Foundations", lit: false)     // LA → Emb: ready
        let attention = concept("Attention", "Foundations", lit: false)       // Emb → Att: blocked
        let tokenization = concept("Tokenization", "Foundations", lit: false) // no prereqs: ready
        let junk = concept("LiNO", "Open Source", lit: false)                 // not in pack: excluded
        let deps = [ConceptDependency(prerequisite: "Linear Algebra", dependent: "Embeddings"),
                    ConceptDependency(prerequisite: "Embeddings", dependent: "Attention")]

        let frontier = KnowledgePathEngine.frontier(
            concepts: [linalg, embeddings, attention, tokenization, junk],
            dependencies: deps)
        #expect(frontier == ["Embeddings", "Tokenization"])
    }

    @Test("gap cluster: lowest completion among pack clusters")
    func gap() {
        let concepts = [
            concept("F1", "Foundations", lit: true),
            concept("F2", "Foundations", lit: true),
            concept("E1", "Evaluation", lit: false),
            concept("E2", "Evaluation", lit: false),
            concept("L1", "LLM Engineering", lit: true),
            concept("L2", "LLM Engineering", lit: false),
        ]
        #expect(KnowledgePathEngine.gapCluster(concepts: concepts) == "Evaluation")
    }

    @Test("next dot follows learning-path order and finds matching articles")
    func nextDot() {
        // "Embeddings" (stage 1) and "Tool Use" (stage 5) both frontier →
        // recommendation must pick the stage-1 concept.
        let embeddings = concept("Embeddings", "Foundations", lit: false)
        let toolUse = concept("Tool Use", "Agents", lit: false)
        let linalg = concept("Linear Algebra", "Foundations", lit: true)
        let deps = [ConceptDependency(prerequisite: "Linear Algebra", dependent: "Embeddings")]

        let article = Article(guid: "a1", title: "Embeddings in practice", content: "",
                              publishedAt: .now, sourceName: "s")
        article.concepts = [embeddings]

        let rec = KnowledgePathEngine.nextDot(concepts: [embeddings, toolUse, linalg],
                                              dependencies: deps, articles: [article])
        #expect(rec?.concept.name == "Embeddings")
        #expect(rec?.litPrerequisites == ["Linear Algebra"])
        #expect(rec?.articles.count == 1)
    }

    @Test("gap tag names the frontier concept an article fills")
    func gapTag() {
        let rag = concept("RAG", "LLM Engineering", lit: false)
        let article = Article(guid: "a2", title: "t", content: "", publishedAt: .now, sourceName: "s")
        article.concepts = [rag]
        let tag = KnowledgePathEngine.gapTag(for: article, frontierNames: ["RAG"],
                                             gapClusterName: nil)
        #expect(tag == "Fills your gap: RAG")
    }

    @Test("pack seed: ~68 concepts, dependencies, idempotent, keeps known green")
    func packSeed() throws {
        UserDefaults.standard.removeObject(forKey: "knowledgePackVersion")
        let context = try makeContext()

        // Pre-existing known concept (from the resume) must keep its mastery
        // and join the pack's cluster.
        let fineTuning = Concept(name: "Fine-Tuning", category: "LLMs", definition: "old")
        fineTuning.isMarkedKnown = true
        fineTuning.masteryLevel = 1.0
        context.insert(fineTuning)
        try context.save()

        KnowledgePack.seedIfNeeded(context: context)

        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())
        #expect(concepts.count == KnowledgePack.concepts.count)   // merged, not duplicated
        #expect(deps.count > 40)
        #expect(fineTuning.isMarkedKnown && fineTuning.masteryLevel == 1.0)
        #expect(fineTuning.category == "Foundations")

        // Second call (as after a pack-version bump): merge again, no duplicates.
        UserDefaults.standard.set(0, forKey: "knowledgePackVersion")
        KnowledgePack.seedIfNeeded(context: context)
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == concepts.count)
        UserDefaults.standard.removeObject(forKey: "knowledgePackVersion")
    }

    @Test("stage progress: current stage is first incomplete")
    func stages() {
        var concepts: [Concept] = []
        for name in KnowledgePack.stages[0].conceptNames {
            concepts.append(concept(name, "Foundations", lit: true))   // stage 1 done
        }
        for name in KnowledgePack.stages[1].conceptNames {
            concepts.append(concept(name, "Foundations", lit: false))  // stage 2 open
        }
        let progress = KnowledgePathEngine.stageProgress(concepts: concepts)
        #expect(progress[0].isComplete)
        #expect(!progress[1].isComplete)
        #expect(progress[1].lit == 0)
    }
}
