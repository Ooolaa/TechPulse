import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// The path engine against a Pack built here in the test, using Concepts and
/// Clusters that appear nowhere in the compiled AI Engineer pack. If any of
/// these pass, the engine is reading the Pack it was handed rather than the one
/// compiled into the app.
@MainActor
@Suite("Pack-driven path engine")
struct PackDrivenPathTests {

    /// A three-Concept map for a field the app has never heard of.
    private func bakingPack(
        stages: [PackFile.PackStage] = [
            .init(title: "Stage 1", subtitle: "Basics", concepts: ["Flour", "Dough"]),
        ],
        sideQuests: [String] = ["Sourdough Starter"]
    ) -> ActivePack {
        ActivePack(
            field: "Baking",
            specialtyCluster: "Fermentation",
            clusterOrder: ["Ingredients", "Technique", "Fermentation"],
            stages: stages,
            suggestedSources: [],
            conceptNames: ["Flour", "Dough", "Sourdough Starter"],
            sideQuestConcepts: sideQuests
        )
    }

    private func concept(_ name: String, _ cluster: String, lit: Bool) -> Concept {
        let concept = Concept(name: name, category: cluster, definition: "d")
        concept.masteryLevel = lit ? 0.5 : 0.0
        return concept
    }

    private func bakingConcepts(doughLit: Bool = false) -> [Concept] {
        [concept("Flour", "Ingredients", lit: true),
         concept("Dough", "Technique", lit: doughLit),
         concept("Sourdough Starter", "Fermentation", lit: false)]
    }

    // MARK: - Frontier and Next Dot

    @Test("the Frontier is computed from the Pack it is handed, not the compiled one")
    func frontierUsesGivenPack() {
        let deps = [ConceptDependency(prerequisite: "Flour", dependent: "Dough"),
                    ConceptDependency(prerequisite: "Dough", dependent: "Sourdough Starter")]

        let frontier = KnowledgePathEngine.frontier(concepts: bakingConcepts(),
                                                    dependencies: deps,
                                                    pack: bakingPack())

        // Flour is lit, so Dough is ready. Sourdough Starter is not — its own
        // dependency is still dim.
        #expect(frontier == ["Dough"])
    }

    @Test("a Concept outside the given Pack never reaches the Frontier")
    func frontierExcludesStrangers() {
        var concepts = bakingConcepts()
        concepts.append(concept("Transformer Architecture", "Ingredients", lit: false))

        let frontier = KnowledgePathEngine.frontier(concepts: concepts, dependencies: [],
                                                    pack: bakingPack())

        // It is a Concept of the *compiled* pack, which is exactly why it must
        // not count here.
        #expect(!frontier.contains("Transformer Architecture"))
        #expect(frontier == ["Dough", "Sourdough Starter"])
    }

    @Test("the Next Dot follows the given Pack's stage order")
    func nextDotFollowsGivenStages() throws {
        let deps = [ConceptDependency(prerequisite: "Flour", dependent: "Dough")]

        // Both Dough and Sourdough Starter are ready; the stage order names
        // Dough, so that is the one recommendation.
        let recommendation = try #require(
            KnowledgePathEngine.nextDot(concepts: bakingConcepts(), dependencies: deps,
                                        articles: [], pack: bakingPack()))

        #expect(recommendation.concept.name == "Dough")
        #expect(recommendation.litPrerequisites == ["Flour"])
    }

    @Test("changing only the Pack's stage order changes the recommendation")
    func nextDotChangesWithStageOrder() throws {
        let reordered = bakingPack(stages: [
            .init(title: "Stage 1", subtitle: "Ferment first",
                  concepts: ["Sourdough Starter", "Flour", "Dough"]),
        ])

        let recommendation = try #require(
            KnowledgePathEngine.nextDot(concepts: bakingConcepts(), dependencies: [],
                                        articles: [], pack: reordered))

        // Same Concepts, same store, same everything but the Pack.
        #expect(recommendation.concept.name == "Sourdough Starter")
    }

    // MARK: - Clusters

    @Test("Cluster stats report the given Pack's Clusters in its order")
    func clusterStatsUseGivenPack() {
        let stats = KnowledgePathEngine.clusterStats(concepts: bakingConcepts(),
                                                     pack: bakingPack())

        #expect(stats.map(\.name) == ["Ingredients", "Technique", "Fermentation"])
        #expect(stats.first?.lit == 1)
        #expect(stats.first?.total == 1)
    }

    @Test("Clusters outside the given Pack sort after its own, and never become the gap")
    func clusterStatsAppendStrangers() {
        var concepts = bakingConcepts()
        concepts.append(concept("Some Article Term", "Vocabulary", lit: false))

        let stats = KnowledgePathEngine.clusterStats(concepts: concepts, pack: bakingPack())
        #expect(stats.map(\.name) == ["Ingredients", "Technique", "Fermentation", "Vocabulary"])

        // The gap must come from the Pack, not from a Cluster reading invented.
        let gap = KnowledgePathEngine.gapCluster(concepts: concepts, pack: bakingPack())
        #expect(gap != "Vocabulary")
        #expect(["Technique", "Fermentation"].contains(gap))
    }

    // MARK: - Stages and side quests

    @Test("stage progress is reported against the given Pack's stages")
    func stageProgressUsesGivenPack() {
        let stages = KnowledgePathEngine.stageProgress(concepts: bakingConcepts(doughLit: true),
                                                       pack: bakingPack())

        #expect(stages.count == 1)
        #expect(stages[0].title == "Stage 1")
        #expect(stages[0].subtitle == "Basics")
        #expect(stages[0].total == 2)
        #expect(stages[0].lit == 2)          // Flour and Dough
    }

    @Test("side-quest progress is reported against the given Pack's specialty Cluster")
    func sideQuestProgressUsesGivenPack() {
        let dim = KnowledgePathEngine.sideQuestProgress(concepts: bakingConcepts(),
                                                        pack: bakingPack())
        #expect(dim.total == 1)
        #expect(dim.lit == 0)

        var lit = bakingConcepts()
        lit[2].masteryLevel = 0.5
        let after = KnowledgePathEngine.sideQuestProgress(concepts: lit, pack: bakingPack())
        #expect(after.lit == 1)
    }

    @Test("a Pack with no side quests reports none, rather than the compiled pack's five")
    func emptySideQuestsAreEmpty() {
        let progress = KnowledgePathEngine.sideQuestProgress(
            concepts: bakingConcepts(), pack: bakingPack(sideQuests: []))

        #expect(progress.total == 0)
        #expect(progress.lit == 0)
    }

    // MARK: - The default is still the compiled pack

    @Test("omitting the Pack still uses the compiled one, so nothing has changed yet")
    func defaultIsCompiledPack() {
        // The engines default to `.current`; today that is the compiled pack.
        // #6 repoints this one property and every engine follows.
        #expect(ActivePack.current.conceptNames == ActivePack.compiled.conceptNames)
        #expect(ActivePack.current.clusterOrder == ActivePack.compiled.clusterOrder)

        let compiled = ActivePack.compiled
        #expect(compiled.clusterOrder == KnowledgePack.clusterOrder)
        #expect(compiled.conceptNames == KnowledgePack.concepts.map(\.name))
        #expect(compiled.sideQuestConcepts == KnowledgePack.sideQuestConcepts)
        #expect(compiled.specialtyCluster == KnowledgePack.specialtyCluster)
        #expect(compiled.stages.map(\.title) == KnowledgePack.stages.map(\.title))

        // The un-passed call and the explicitly-passed call agree.
        let concepts = [concept("Embeddings", "Foundations", lit: true),
                        concept("Attention", "Foundations", lit: false)]
        let deps = [ConceptDependency(prerequisite: "Embeddings", dependent: "Attention")]
        #expect(KnowledgePathEngine.frontier(concepts: concepts, dependencies: deps)
                == KnowledgePathEngine.frontier(concepts: concepts, dependencies: deps,
                                                pack: compiled))
    }
}
