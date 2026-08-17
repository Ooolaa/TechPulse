import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// Installing a Pack gives the reader a map; installing again over the top
/// leaves what they have learned alone. Everything here runs over an
/// in-memory store.
@MainActor
@Suite("Pack installer", .serialized)
struct PackInstallerTests {

    private static let sharedContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: FeedSource.self, Article.self, Concept.self,
            LearningEvent.self, ConceptLink.self, ConceptDependency.self,
            SemanticLink.self, InstalledPack.self,
            configurations: config
        )
    }()

    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        for article in try context.fetch(FetchDescriptor<Article>()) { context.delete(article) }
        for concept in try context.fetch(FetchDescriptor<Concept>()) { context.delete(concept) }
        for link in try context.fetch(FetchDescriptor<ConceptLink>()) { context.delete(link) }
        for dep in try context.fetch(FetchDescriptor<ConceptDependency>()) { context.delete(dep) }
        for link in try context.fetch(FetchDescriptor<SemanticLink>()) { context.delete(link) }
        for event in try context.fetch(FetchDescriptor<LearningEvent>()) { context.delete(event) }
        for source in try context.fetch(FetchDescriptor<FeedSource>()) { context.delete(source) }
        for pack in try context.fetch(FetchDescriptor<InstalledPack>()) { context.delete(pack) }
        try context.save()
        return context
    }

    // MARK: - Fixtures

    /// Foundations → Agents, with a Dependency spine and one stage.
    private func aiPack(
        field: String = "AI Engineering",
        concepts: [PackFile.PackConcept]? = nil,
        stages: [PackFile.PackStage]? = nil,
        suggestedSources: [PackFile.PackSource] = [
            .init(name: "Import AI", url: "https://jack-clark.net/feed", category: "LLMs"),
        ]
    ) -> PackFile {
        PackFile(
            field: field,
            specialtyCluster: "Agents",
            clusterOrder: ["Foundations", "Agents"],
            concepts: concepts ?? [
                .init(name: "Embeddings", cluster: "Foundations",
                      definition: "Meaning as vectors.", dependencies: []),
                .init(name: "RAG", cluster: "Agents",
                      definition: "Ground answers in your data.", dependencies: ["Embeddings"]),
                .init(name: "Agent Memory", cluster: "Agents",
                      definition: "Scratchpads and recall.", dependencies: ["RAG"]),
            ],
            stages: stages ?? [
                .init(title: "Stage 1", subtitle: "Start here", concepts: ["Embeddings", "RAG"]),
            ],
            suggestedSources: suggestedSources
        )
    }

    private func concept(_ name: String, in context: ModelContext) throws -> Concept? {
        try context.fetch(FetchDescriptor<Concept>()).first { $0.name == name }
    }

    /// Dependency ordering differs between a Pack and a store fetch, so
    /// comparisons sort what the format leaves free.
    private func normalized(_ pack: PackFile) -> PackFile {
        var copy = pack
        copy.concepts = pack.concepts
            .map { var c = $0; c.dependencies.sort(); return c }
            .sorted { $0.name < $1.name }
        copy.suggestedSources = pack.suggestedSources.sorted { $0.url < $1.url }
        return copy
    }

    // MARK: - Installing

    @Test("installing a Pack creates its Concepts in its Clusters, dim")
    func installCreatesConcepts() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        let concepts = try context.fetch(FetchDescriptor<Concept>())
        #expect(concepts.count == 3)
        let embeddings = try #require(try concept("Embeddings", in: context))
        #expect(embeddings.category == "Foundations")
        #expect(embeddings.conceptDefinition == "Meaning as vectors.")
        #expect(embeddings.masteryLevel == 0.0)
        #expect(embeddings.masteryState == .new)
        #expect(try concept("RAG", in: context)?.category == "Agents")
    }

    @Test("installing a Pack creates its authored Dependencies")
    func installCreatesDependencies() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())
        let edges = Set(deps.map { "\($0.prerequisite)→\($0.dependent)" })
        #expect(edges == ["Embeddings→RAG", "RAG→Agent Memory"])
    }

    @Test("a Dependency is not mirrored as a Co-read Link — the two mean different things")
    func installDoesNotFabricateCoreadLinks() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        // ADR-0002: a Co-read Link records what you actually read. Installing a
        // Pack is not reading, so it must not manufacture one.
        #expect(try context.fetch(FetchDescriptor<ConceptLink>()).isEmpty)
    }

    // MARK: - Semantic Links (ADR-0002)

    @Test("installing a Pack joins related Concepts with no reading history present")
    func installComputesSemanticLinks() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        // The point of the whole feature: a map that means something before
        // the reader has read a single article.
        let links = try context.fetch(FetchDescriptor<SemanticLink>())
        #expect(!links.isEmpty)
        #expect(try context.fetch(FetchDescriptor<LearningEvent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ConceptLink>()).isEmpty)
    }

    @Test("Semantic Links are stored apart from Co-read Links and authored Dependencies")
    func semanticLinksAreStoredDistinctly() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        // Three kinds of edge, three stores. A Semantic Link must not show up
        // as either of the other two, or the map cannot draw them differently.
        #expect(!(try context.fetch(FetchDescriptor<SemanticLink>())).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ConceptLink>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ConceptDependency>()).count == 2)
    }

    @Test("a Semantic Link names Concepts that really exist, undirected and once each")
    func semanticLinksAreWellFormed() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        let stored = Set(try context.fetch(FetchDescriptor<Concept>()).map(\.name))
        let links = try context.fetch(FetchDescriptor<SemanticLink>())
        for link in links {
            #expect(stored.contains(link.conceptA))
            #expect(stored.contains(link.conceptB))
            #expect(link.conceptA < link.conceptB)      // sorted, so undirected
            #expect(link.strength >= 0 && link.strength <= 1)
        }
        let pairs = links.map { "\($0.conceptA)|\($0.conceptB)" }
        #expect(Set(pairs).count == pairs.count)        // no duplicate edge
    }

    @Test("reinstalling rebuilds Semantic Links rather than piling more on")
    func reinstallRebuildsSemanticLinks() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)
        let first = try context.fetch(FetchDescriptor<SemanticLink>()).count

        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        // Derived from the Pack, so the Pack owns them outright — the same
        // rule Dependencies follow, and nothing of the reader's is lost by it.
        #expect(try context.fetch(FetchDescriptor<SemanticLink>()).count == first)
    }

    @Test("a Semantic Link to a dropped Concept does not survive the Pack that dropped it")
    func reinstallDropsLinksToRemovedConcepts() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        try PackInstaller.install(aiPack(concepts: [
            .init(name: "Embeddings", cluster: "Foundations",
                  definition: "Meaning as vectors.", dependencies: []),
            .init(name: "RAG", cluster: "Agents",
                  definition: "Ground answers in your data.", dependencies: ["Embeddings"]),
        ], stages: []), origin: .builtin, context: context)

        // "Agent Memory" keeps its Mastery and history, but it is no longer
        // part of the map this Pack draws.
        let links = try context.fetch(FetchDescriptor<SemanticLink>())
        #expect(!links.contains { $0.conceptA == "Agent Memory" || $0.conceptB == "Agent Memory" })
    }

    @Test("a Concept the reader's own reading discovered is not wired into the Pack's map")
    func semanticLinksCoverOnlyThePacksConcepts() throws {
        let context = try makeContext()
        context.insert(Concept(name: "Some Stray Term", category: "Foundations",
                               definition: "Something an article mentioned once."))
        try context.save()

        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        // Semantic Links are computed from the Pack's own definitions. What the
        // reader's reading turned up is theirs, and is not part of the Pack.
        let links = try context.fetch(FetchDescriptor<SemanticLink>())
        #expect(!links.contains { $0.conceptA == "Some Stray Term" || $0.conceptB == "Some Stray Term" })
    }

    @Test("installing a Pack whose Concepts cannot be embedded still installs")
    func installSurvivesWithoutAnEmbedding() throws {
        let context = try makeContext()
        // Hardware without the embedding model: a poorer map, not a failed
        // install. Nothing here depends on Apple Intelligence either way.
        try PackInstaller.install(aiPack(), origin: .builtin, context: context,
                                  vector: { _ in nil })

        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 3)
        #expect(try context.fetch(FetchDescriptor<SemanticLink>()).isEmpty)
        #expect(ActivePack.load(context: context)?.field == "AI Engineering")
    }

    @Test("installing a Pack of realistic size does not hold the reader up")
    func installOfRealisticPackIsPrompt() throws {
        let context = try makeContext()
        let flagship = try BuiltinPacks.aiEngineer()

        let started = Date.now
        try PackInstaller.install(flagship, origin: .builtin, context: context)
        let elapsed = Date.now.timeIntervalSince(started)

        // 68 Concepts, the flagship's real size. Generous against a debug
        // simulator build — a regression guard on the shape of the work, not a
        // benchmark. Measured at ~0.5s, nearly all of it the embedding calls.
        #expect(elapsed < 5, "installing \(flagship.concepts.count) Concepts took \(elapsed)s")
        #expect(!(try context.fetch(FetchDescriptor<SemanticLink>())).isEmpty)
    }

    @Test("a Pack's suggested Sources are kept to offer, not subscribed to")
    func installOffersSourcesWithoutSubscribing() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(suggestedSources: [
            .init(name: "Import AI", url: "https://jack-clark.net/feed", category: "LLMs"),
            .init(name: "arXiv cs.AI", url: "https://arxiv.org/rss/cs.AI", category: "Research"),
        ]), origin: .builtin, context: context)

        // A Source is chosen by the reader. Installing a Pack must not sign
        // them up to anything.
        #expect(try context.fetch(FetchDescriptor<FeedSource>()).isEmpty)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.suggestedSources.map(\.name) == ["Import AI", "arXiv cs.AI"])
    }

    @Test("installing an invalid Pack throws and changes nothing")
    func installValidates() throws {
        let context = try makeContext()
        let broken = aiPack(concepts: [
            .init(name: "RAG", cluster: "Foundations", definition: "d",
                  dependencies: ["Nonexistent"]),
        ], stages: [])

        #expect(throws: PackValidationError.self) {
            try PackInstaller.install(broken, origin: .imported, context: context)
        }
        #expect(try context.fetch(FetchDescriptor<Concept>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<InstalledPack>()).isEmpty)
    }

    // MARK: - The active-Pack seam

    @Test("the installed Pack is readable through one load point")
    func activePackIsReadable() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "AI Engineering")
        #expect(active.clusterOrder == ["Foundations", "Agents"])
        #expect(active.specialtyCluster == "Agents")
        #expect(active.conceptNames == ["Embeddings", "RAG", "Agent Memory"])
        #expect(active.stages.map(\.title) == ["Stage 1"])
    }

    @Test("with no Pack installed there is no active Pack")
    func noActivePackWhenNothingInstalled() throws {
        let context = try makeContext()
        #expect(ActivePack.load(context: context) == nil)
    }

    @Test("installing a different Pack retires the previous one — exactly one is active")
    func installingRetiresPrevious() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)
        try PackInstaller.install(aiPack(field: "Data Science"), origin: .imported,
                                  context: context)

        let records = try context.fetch(FetchDescriptor<InstalledPack>())
        #expect(records.count == 2)
        #expect(records.filter(\.isActive).count == 1)
        #expect(ActivePack.load(context: context)?.field == "Data Science")
    }

    // MARK: - Reinstalling over the top

    @Test("reinstalling preserves Mastery, Lit state and learning history")
    func reinstallPreservesProgress() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        let rag = try #require(try concept("RAG", in: context))
        rag.masteryLevel = 0.7
        rag.isMarkedKnown = true
        rag.lastReviewed = .now
        context.insert(LearningEvent(kind: "read", conceptName: "RAG", masteryDelta: 0.1))
        try context.save()

        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        let after = try #require(try concept("RAG", in: context))
        #expect(after.masteryLevel == 0.7)
        #expect(after.isMarkedKnown)
        #expect(after.masteryState == .known)
        #expect(after.lastReviewed != nil)
        #expect(try context.fetch(FetchDescriptor<LearningEvent>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 3)   // no twins
    }

    @Test("reinstalling a corrected Pack adopts its new definitions and Cluster moves")
    func reinstallAdoptsCorrections() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        try PackInstaller.install(aiPack(concepts: [
            .init(name: "Embeddings", cluster: "Foundations",
                  definition: "Meaning as vectors.", dependencies: []),
            .init(name: "RAG", cluster: "Foundations",          // moved cluster
                  definition: "Retrieval-augmented generation.", // corrected text
                  dependencies: ["Embeddings"]),
        ], stages: []), origin: .builtin, context: context)

        let rag = try #require(try concept("RAG", in: context))
        #expect(rag.conceptDefinition == "Retrieval-augmented generation.")
        #expect(rag.category == "Foundations")
    }

    @Test("a Concept the reader's reading already created under different casing keeps its history")
    func installReusesCaseDifferingConcept() throws {
        let context = try makeContext()
        // Reading created "rag" before any Pack was installed; the Pack says "RAG".
        let stray = Concept(name: "rag", category: "Foundations", definition: "old")
        stray.masteryLevel = 0.7
        context.insert(stray)
        context.insert(LearningEvent(kind: "read", conceptName: "rag", masteryDelta: 0.1))
        try context.save()

        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        // One row, not twins, and its Mastery survived.
        let matches = try context.fetch(FetchDescriptor<Concept>())
            .filter { $0.name.lowercased() == "rag" }
        #expect(matches.count == 1)
        #expect(matches.first?.masteryLevel == 0.7)
        // Its history is keyed by the name it still has, so it must keep it.
        #expect(matches.first?.name == "rag")

        // Every name the active Pack claims must resolve to a Concept that
        // really exists, or the map points at nothing.
        let active = try #require(ActivePack.load(context: context))
        let stored = Set(try context.fetch(FetchDescriptor<Concept>()).map(\.name))
        #expect(active.conceptNames.allSatisfy(stored.contains))

        // And its Dependencies must name that same row.
        let exported = try #require(PackInstaller.exportActivePack(context: context))
        try PackValidator.validate(exported)
    }

    @Test("reinstalling a Pack that drops a Dependency does not leave the old edge behind")
    func reinstallRebuildsDependencies() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        // The corrected Pack reverses Embeddings → RAG. Keeping both edges
        // would be a cycle, and no Frontier can advance past one.
        try PackInstaller.install(aiPack(concepts: [
            .init(name: "Embeddings", cluster: "Foundations",
                  definition: "Meaning as vectors.", dependencies: ["RAG"]),
            .init(name: "RAG", cluster: "Agents",
                  definition: "Ground answers in your data.", dependencies: []),
        ], stages: []), origin: .builtin, context: context)

        let edges = try context.fetch(FetchDescriptor<ConceptDependency>())
            .map { "\($0.prerequisite)→\($0.dependent)" }
        #expect(edges == ["RAG→Embeddings"])

        let exported = try #require(PackInstaller.exportActivePack(context: context))
        try PackValidator.validate(exported)      // would throw .dependencyCycle
    }

    @Test("a Pack that drops a Concept does not destroy that Concept or its history")
    func droppedConceptKeepsHistory() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)

        let memory = try #require(try concept("Agent Memory", in: context))
        memory.masteryLevel = 0.6
        context.insert(LearningEvent(kind: "read", conceptName: "Agent Memory",
                                     masteryDelta: 0.1))
        try context.save()

        // The corrected Pack no longer contains "Agent Memory".
        try PackInstaller.install(aiPack(concepts: [
            .init(name: "Embeddings", cluster: "Foundations",
                  definition: "Meaning as vectors.", dependencies: []),
            .init(name: "RAG", cluster: "Agents",
                  definition: "Ground answers in your data.", dependencies: ["Embeddings"]),
        ], stages: []), origin: .builtin, context: context)

        let survivor = try #require(try concept("Agent Memory", in: context))
        #expect(survivor.masteryLevel == 0.6)
        #expect(try context.fetch(FetchDescriptor<LearningEvent>()).count == 1)
        // It is simply no longer part of the active Pack.
        #expect(ActivePack.load(context: context)?.conceptNames.contains("Agent Memory") == false)
    }

    // MARK: - Export

    @Test("an active Pack exports back to the Pack file format and round-trips")
    func exportRoundTrips() throws {
        let context = try makeContext()
        // A Concept carrying several Dependencies, so per-Concept dependency
        // order is actually exercised rather than trivially a single element.
        let original = aiPack(concepts: [
            .init(name: "Embeddings", cluster: "Foundations",
                  definition: "Meaning as vectors.", dependencies: []),
            .init(name: "RAG", cluster: "Agents",
                  definition: "Ground answers in your data.", dependencies: ["Embeddings"]),
            .init(name: "Agent Memory", cluster: "Agents", definition: "Scratchpads.",
                  dependencies: ["RAG", "Embeddings"]),
        ], stages: [])
        try PackInstaller.install(original, origin: .builtin, context: context)

        let exported = try #require(PackInstaller.exportActivePack(context: context))
        #expect(normalized(exported) == normalized(original))
        try PackValidator.validate(exported)
    }

    @Test("exporting what was just installed is a fixed point")
    func exportIsAFixedPoint() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)
        let first = try #require(PackInstaller.exportActivePack(context: context))

        try PackInstaller.install(first, origin: .imported, context: context)
        let second = try #require(PackInstaller.exportActivePack(context: context))

        #expect(second == first)
    }

    @Test("export carries the Pack's own suggested Sources, not the reader's subscriptions")
    func exportDoesNotLeakSubscriptions() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)
        context.insert(FeedSource(name: "My private newsletter",
                                  url: URL(string: "https://example.com/secret")!,
                                  category: "Personal"))
        try context.save()

        let exported = try #require(PackInstaller.exportActivePack(context: context))
        #expect(exported.suggestedSources.map(\.name) == ["Import AI"])
    }

    @Test("export excludes Concepts the reader's own reading discovered")
    func exportExcludesStrayConcepts() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)
        context.insert(Concept(name: "Some Stray Term", category: "Foundations", definition: "d"))
        try context.save()

        let exported = try #require(PackInstaller.exportActivePack(context: context))
        #expect(exported.concepts.map(\.name) == ["Embeddings", "RAG", "Agent Memory"])
    }

    @Test("with no Pack installed there is nothing to export")
    func exportNilWhenNothingInstalled() throws {
        let context = try makeContext()
        #expect(PackInstaller.exportActivePack(context: context) == nil)
    }

    // MARK: - Reading order (ADR-0004)

    @Test("path order follows the authored Stages first")
    func pathOrderFollowsStages() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)
        let active = try #require(ActivePack.load(context: context))
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())

        #expect(active.pathOrder(dependencies: deps) == ["Embeddings", "RAG", "Agent Memory"])
    }

    @Test("a Pack with no Stages falls back to Dependency order, never alphabetical")
    func pathOrderFallsBackToTopologicalSort() throws {
        let context = try makeContext()
        // Alphabetically this is Agent Memory, Embeddings, RAG — which would
        // recommend the deepest Concept first. Dependency order must win.
        try PackInstaller.install(aiPack(stages: []), origin: .generated, context: context)
        let active = try #require(ActivePack.load(context: context))
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())

        #expect(active.pathOrder(dependencies: deps) == ["Embeddings", "RAG", "Agent Memory"])
    }

    @Test("Concepts the Stages miss are appended in Dependency order")
    func pathOrderAppendsUnstagedConcepts() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(stages: [
            .init(title: "Stage 1", subtitle: "s", concepts: ["Agent Memory"]),
        ]), origin: .builtin, context: context)
        let active = try #require(ActivePack.load(context: context))
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())

        // The authored stage wins outright, then the remainder in Dependency order.
        #expect(active.pathOrder(dependencies: deps) == ["Agent Memory", "Embeddings", "RAG"])
    }

    @Test("path order covers every Concept in the Pack exactly once")
    func pathOrderIsATotalOrder() throws {
        let context = try makeContext()
        try PackInstaller.install(aiPack(), origin: .builtin, context: context)
        let active = try #require(ActivePack.load(context: context))
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())

        let order = active.pathOrder(dependencies: deps)
        #expect(Set(order) == Set(active.conceptNames))
        #expect(order.count == active.conceptNames.count)
    }

    @Test("a record naming one Concept twice is read as naming it once")
    func recordNamingOneConceptTwiceIsNormalized() throws {
        let context = try makeContext()
        // What a build without the case-folding check could leave behind: the
        // Pack declared "RAG" and "rag", both resolved onto the one stored row.
        let rag = Concept(name: "rag", category: "Agents",
                          definition: "Ground answers in your data.")
        context.insert(rag)
        context.insert(InstalledPack(
            field: "AI Engineering", specialtyCluster: "Agents",
            clusterOrder: ["Foundations", "Agents"],
            stages: [], suggestedSources: [],
            conceptNames: ["rag", "rag"], sideQuestConcepts: ["rag", "rag"],
            origin: .imported))
        try context.save()

        // The reader is shown a count, and a Concept counted twice is a Pack
        // that never finishes: one dot, reported as two.
        let active = try #require(ActivePack.load(context: context))
        #expect(active.conceptNames == ["rag"])
        #expect(active.sideQuestConcepts == ["rag"])

        // Sharing it must not produce a file this build would refuse to import.
        let exported = try #require(PackInstaller.exportActivePack(context: context))
        #expect(exported.concepts.map(\.name) == ["rag"])
        try PackValidator.validate(exported)
    }

    @Test("a record left holding a name twice still orders, rather than killing the app")
    func pathOrderToleratesRepeatedConceptName() {
        // A Pack installed before the validator compared names without case
        // could resolve two of its Concepts onto one stored row, leaving the
        // record naming it twice. That record is on disk and is read on every
        // launch, so ordering it has to degrade rather than trap.
        let active = ActivePack(
            field: "AI Engineering", specialtyCluster: nil,
            clusterOrder: ["Foundations"], stages: [], suggestedSources: [],
            conceptNames: ["rag", "rag", "Embeddings"],
            sideQuestConcepts: [], origin: .imported)

        let order = active.pathOrder(dependencies: [
            ConceptDependency(prerequisite: "Embeddings", dependent: "rag"),
        ])

        // The repeat collapses; the Dependency it carries is still honoured.
        #expect(order == ["Embeddings", "rag"])
    }
}
