import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// The cutover, from the returning reader's side: they open a build where the
/// map comes from a Pack file instead of compiled Swift, and find their map
/// exactly as they left it.
@MainActor
@Suite("Pack migration", .serialized)
struct PackMigrationTests {

    private func makeContext() throws -> ModelContext {
        let container = try AppSchema.inMemoryContainer()
        UserDefaults.standard.removeObject(forKey: "builtinPackVersion")
        ActivePackIdentity.forget()
        // The cache is process-global; a previous test's Pack must not leak in.
        ActivePack.resetCache()
        return ModelContext(container)
    }

    /// The store as it looked before Packs were data: Concepts seeded by the
    /// compiled pack, with the reader's progress on them.
    private func legacyInstall(_ context: ModelContext) throws {
        KnowledgePack.seed(KnowledgePack.concepts, context: context)
        try context.save()
    }

    private func concept(_ name: String, in context: ModelContext) throws -> Concept? {
        try context.fetch(FetchDescriptor<Concept>()).first { $0.name == name }
    }

    // MARK: - Fresh install

    @Test("a fresh install ends up on the built-in Pack with the same map as before")
    func freshInstall() throws {
        let context = try makeContext()
        PackMigration.ensureBuiltinInstalled(context: context)

        let concepts = try context.fetch(FetchDescriptor<Concept>())
        #expect(concepts.count == KnowledgePack.concepts.count)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "AI Engineering")
        #expect(active.clusterOrder == KnowledgePack.clusterOrder)
        #expect(active.sideQuestConcepts == KnowledgePack.sideQuestConcepts)

        // Everything starts dim, exactly as compiled seeding left it.
        #expect(concepts.allSatisfy { $0.masteryState == .new })
    }

    @Test("a fresh install opens on a connected map, with no Co-read Links")
    func freshInstallHasNoLinks() throws {
        let context = try makeContext()
        PackMigration.ensureBuiltinInstalled(context: context)

        // Compiled seeding used to mirror every Dependency into a Co-read Link,
        // so a brand-new map had structure. ADR-0002 forbids that — a Co-read
        // Link records what you actually read, and a launch is not reading.
        #expect(try context.fetch(FetchDescriptor<ConceptLink>()).isEmpty)
        // The Dependency spine is there, so the map is not structureless.
        #expect(try !context.fetch(FetchDescriptor<ConceptDependency>()).isEmpty)

        // And #9's Semantic Links close the gap that left behind: the reader
        // reaches the map through this launch path, so it is where "opens
        // connected, not as dust" has to be true. Every Concept the built-in
        // Pack installs is joined to something before a word has been read.
        let semantic = try context.fetch(FetchDescriptor<SemanticLink>())
        #expect(!semantic.isEmpty)

        var degree: [String: Int] = [:]
        for link in semantic {
            degree[link.conceptA, default: 0] += 1
            degree[link.conceptB, default: 0] += 1
        }
        let packConcepts = try #require(ActivePack.load(context: context)).conceptNames
        let isolated = packConcepts.filter { (degree[$0] ?? 0) == 0 }
        #expect(isolated.isEmpty, "isolated Concepts on a fresh install: \(isolated)")
    }

    @Test("a reader already on the current Pack still gets Semantic Links")
    func semanticLinksReachExistingInstalls() throws {
        let context = try makeContext()
        PackMigration.ensureBuiltinInstalled(context: context)

        // Exactly the shape of an upgrade from a build before #9: the Pack is
        // installed and current, so launch installs nothing — and Semantic
        // Links are only ever computed *at install*. Without a backfill the map
        // opens as the dust the feature was meant to end, and only switching
        // Packs would ever fix it.
        for link in try context.fetch(FetchDescriptor<SemanticLink>()) { context.delete(link) }
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SemanticLink>()).isEmpty)

        PackMigration.ensureBuiltinInstalled(context: context)
        PackMigration.ensureSemanticLinks(context: context)

        let links = try context.fetch(FetchDescriptor<SemanticLink>())
        #expect(!links.isEmpty)
        // The same map installing would have produced: nothing isolated.
        var degree: [String: Int] = [:]
        for link in links {
            degree[link.conceptA, default: 0] += 1
            degree[link.conceptB, default: 0] += 1
        }
        let packConcepts = try #require(ActivePack.load(context: context)).conceptNames
        #expect(packConcepts.allSatisfy { (degree[$0] ?? 0) > 0 })
    }

    @Test("the backfill leaves an install that already has its links alone")
    func semanticBackfillIsOneShot() throws {
        let context = try makeContext()
        PackMigration.ensureBuiltinInstalled(context: context)
        let installed = try context.fetch(FetchDescriptor<SemanticLink>())
            .map { "\($0.conceptA)|\($0.conceptB)" }.sorted()

        PackMigration.ensureSemanticLinks(context: context)

        let after = try context.fetch(FetchDescriptor<SemanticLink>())
            .map { "\($0.conceptA)|\($0.conceptB)" }.sorted()
        #expect(after == installed)
    }

    @Test("running migration twice changes nothing")
    func migrationIsIdempotent() throws {
        let context = try makeContext()
        PackMigration.ensureBuiltinInstalled(context: context)
        let firstCount = try context.fetch(FetchDescriptor<Concept>()).count

        PackMigration.ensureBuiltinInstalled(context: context)

        #expect(try context.fetch(FetchDescriptor<Concept>()).count == firstCount)
        #expect(try context.fetch(FetchDescriptor<InstalledPack>()).filter(\.isActive).count == 1)
    }

    // MARK: - The reader whose Pack record went missing (#37)

    /// The store as #21 left it: everything the reader learned is still there,
    /// and the one row that said which Pack it was is not.
    private func loseThePackRecord(_ context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<InstalledPack>()) {
            context.delete(record)
        }
        try context.save()
        ActivePack.resetCache()
    }

    @Test("a reader on the other built-in comes back on that Pack, not the flagship")
    func lostRecordRestoresTheRightBuiltin() throws {
        let context = try makeContext()
        let security = try BuiltinPacks.load(BuiltinPacks.securityEngineeringFileName)
        try PackInstaller.install(security, origin: .builtin, context: context)

        // This path reinstalls the Pack over the top, which rewrites Clusters
        // and definitions and rebuilds every edge — so it is the path where
        // what the reader learned could plausibly be lost.
        let lit = try #require(try concept("Threat Modeling", in: context))
        lit.masteryLevel = 0.6
        lit.isMarkedKnown = true
        context.insert(LearningEvent(kind: "read", conceptName: "Threat Modeling",
                                     masteryDelta: 0.1))
        try context.save()
        try loseThePackRecord(context)

        PackMigration.ensureBuiltinInstalled(context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "Security Engineering")
        #expect(active.origin == .builtin)
        // Reinstalled from the file, so the whole Pack is back, Stages and all.
        #expect(active.stages.count == security.stages.count)

        let after = try #require(try concept("Threat Modeling", in: context))
        #expect(after.masteryLevel == 0.6)
        #expect(after.isMarkedKnown)
        #expect(try context.fetch(FetchDescriptor<LearningEvent>()).count == 1)
    }

    @Test("a reader on a Pack of their own keeps its name, its Clusters and its map")
    func lostRecordAdoptsAnImportedMap() throws {
        let context = try makeContext()
        let mine = PackFile(
            field: "Product Design",
            specialtyCluster: nil,
            clusterOrder: ["Research", "Craft"],
            concepts: [
                .init(name: "User interviews", cluster: "Research",
                      definition: "Asking before building.", dependencies: []),
                .init(name: "Affordances", cluster: "Craft",
                      definition: "What a thing looks like it does.",
                      dependencies: ["User interviews"]),
            ],
            stages: [],
            suggestedSources: [])
        try PackInstaller.install(mine, origin: .imported, context: context, vector: { _ in nil })
        try loseThePackRecord(context)

        PackMigration.ensureBuiltinInstalled(context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "Product Design")
        #expect(active.origin == .imported)
        #expect(Set(active.conceptNames) == ["User interviews", "Affordances"])
        // In the order the Concepts arrived, which for a Pack is its author's.
        #expect(active.clusterOrder == ["Research", "Craft"])
        // The flagship was not installed over the top: its Concepts are absent
        // and the reader's own Dependency is still the only edge on the map.
        #expect(try concept("RAG", in: context) == nil)
        let edges = try context.fetch(FetchDescriptor<ConceptDependency>())
        #expect(edges.count == 1)
        #expect(edges.first?.dependent == "Affordances")
    }

    @Test("recovering a Pack leaves Mastery and history where they were")
    func recoveryKeepsWhatWasLearned() throws {
        let context = try makeContext()
        let mine = PackFile(
            field: "Product Design", specialtyCluster: nil,
            clusterOrder: ["Research"],
            concepts: [.init(name: "User interviews", cluster: "Research",
                             definition: "Asking before building.", dependencies: [])],
            stages: [], suggestedSources: [])
        try PackInstaller.install(mine, origin: .imported, context: context, vector: { _ in nil })
        let lit = try #require(try concept("User interviews", in: context))
        lit.masteryLevel = 0.6
        lit.isMarkedKnown = true
        context.insert(LearningEvent(kind: "read", conceptName: "User interviews",
                                     masteryDelta: 0.1))
        try context.save()
        try loseThePackRecord(context)

        PackMigration.ensureBuiltinInstalled(context: context)

        let after = try #require(try concept("User interviews", in: context))
        #expect(after.masteryLevel == 0.6)
        #expect(after.isMarkedKnown)
        #expect(try context.fetch(FetchDescriptor<LearningEvent>()).count == 1)
    }

    @Test("the recovered Pack holds the Pack's Concepts, not everything the reader read")
    func recoveryLeavesStrayConceptsOutOfThePack() throws {
        let context = try makeContext()
        // Coordinates rather than embeddings, so the Semantic Links a real
        // install would draw are drawn here exactly.
        let places: [String: [Double]] = [
            "User interviews": [1.0, 0.0], "Affordances": [0.9, 0.1],
        ]
        let mine = PackFile(
            field: "Product Design", specialtyCluster: nil,
            clusterOrder: ["Research", "Craft"],
            concepts: [
                .init(name: "User interviews", cluster: "Research",
                      definition: "Asking before building.", dependencies: []),
                .init(name: "Affordances", cluster: "Craft",
                      definition: "What a thing looks like it does.", dependencies: []),
            ],
            stages: [], suggestedSources: [])
        try PackInstaller.install(mine, origin: .imported, context: context,
                                  vector: { text in
            places.first { text.hasPrefix($0.key) }?.value
        })
        #expect(try !context.fetch(FetchDescriptor<SemanticLink>()).isEmpty)

        // A Concept the reader's own reading discovered. It is theirs, but it
        // was never part of the Pack — and a Concept with no Dependencies that
        // counts as a Pack member is trivially on the Frontier (ADR-0001).
        context.insert(Concept(name: "Kerning", category: "Articles",
                               definition: "Space between letters."))
        try context.save()
        try loseThePackRecord(context)

        PackMigration.ensureBuiltinInstalled(context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(Set(active.conceptNames) == ["User interviews", "Affordances"])
        #expect(!active.clusterOrder.contains("Articles"))
        // Still on the map, still the reader's — just not part of the Pack.
        #expect(try concept("Kerning", in: context) != nil)
    }

    @Test("a remembered built-in that no longer ships falls back to the flagship")
    func rememberedBuiltinThatIsGoneFallsBack() throws {
        let context = try makeContext()
        try legacyInstall(context)
        ActivePackIdentity.remember(field: "Bioinformatics", origin: .builtin)

        PackMigration.ensureBuiltinInstalled(context: context)

        let active = try #require(ActivePack.load(context: context))
        // Never a record claiming to be a built-in no build has: matching by
        // field is how the version bump finds it, so it could never be updated.
        #expect(active.field == "AI Engineering")
        #expect(!active.stages.isEmpty)
    }

    @Test("a record that is merely inactive is reactivated, not rebuilt narrower")
    func inactiveRecordIsReactivated() throws {
        let context = try makeContext()
        let security = try BuiltinPacks.load(BuiltinPacks.securityEngineeringFileName)
        try PackInstaller.install(security, origin: .builtin, context: context)
        // The record is intact; only its flag says otherwise. Rebuilding from
        // the map would throw away Stages and Sources it still has.
        for record in try context.fetch(FetchDescriptor<InstalledPack>()) {
            record.isActive = false
        }
        try context.save()
        ActivePack.resetCache()

        PackMigration.ensureBuiltinInstalled(context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "Security Engineering")
        #expect(active.stages.count == security.stages.count)
        #expect(active.suggestedSources.count == security.suggestedSources.count)
        #expect(try context.fetch(FetchDescriptor<InstalledPack>()).count == 1)
    }

    @Test("a store from before Packs were data still opens on the flagship")
    func nothingRememberedStillInstallsTheFlagship() throws {
        let context = try makeContext()
        try legacyInstall(context)

        PackMigration.ensureBuiltinInstalled(context: context)

        #expect(try #require(ActivePack.load(context: context)).field == "AI Engineering")
    }

    // MARK: - The returning reader

    @Test("an existing install migrates with Mastery, Lit state and history intact")
    func existingInstallKeepsEverything() throws {
        let context = try makeContext()
        try legacyInstall(context)

        // The reader has been using the app: some Mastery, one Concept they
        // marked known, and a history of reading.
        let rag = try #require(try concept("RAG", in: context))
        rag.masteryLevel = 0.6
        rag.lastReviewed = .now
        let pytorch = try #require(try concept("PyTorch", in: context))
        pytorch.isMarkedKnown = true
        pytorch.masteryLevel = 1.0
        for day in 0..<3 {
            context.insert(LearningEvent(kind: "read", conceptName: "RAG", masteryDelta: 0.1,
                                         date: .now.addingTimeInterval(Double(-day) * 86_400)))
        }
        try context.save()
        let conceptsBefore = try context.fetch(FetchDescriptor<Concept>()).count

        PackMigration.ensureBuiltinInstalled(context: context)

        // Mastery and Lit state survive.
        let ragAfter = try #require(try concept("RAG", in: context))
        #expect(ragAfter.masteryLevel == 0.6)
        #expect(ragAfter.masteryState == .learning)
        #expect(ragAfter.lastReviewed != nil)

        let pytorchAfter = try #require(try concept("PyTorch", in: context))
        #expect(pytorchAfter.isMarkedKnown)
        #expect(pytorchAfter.masteryState == .known)

        // Learning history survives untouched.
        #expect(try context.fetch(FetchDescriptor<LearningEvent>()).count == 3)

        // No twins: the Pack adopted the Concepts already there.
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == conceptsBefore)
        #expect(ActivePack.load(context: context) != nil)
    }

    @Test("the Streak survives migration")
    func streakSurvives() throws {
        let context = try makeContext()
        try legacyInstall(context)

        // Three consecutive days of reading, today included. The Streak is
        // counted off `Article.readAt`, which installing a Pack never touches.
        for day in 0..<3 {
            let when = Date.now.addingTimeInterval(Double(-day) * 86_400)
            let article = Article(guid: "g\(day)", title: "t\(day)", content: "c",
                                  publishedAt: when, sourceName: "s")
            article.isRead = true
            article.readAt = when
            context.insert(article)
        }
        try context.save()
        let before = HabitEngine.streakDays(
            articles: try context.fetch(FetchDescriptor<Article>()))
        #expect(before == 3)

        PackMigration.ensureBuiltinInstalled(context: context)

        let after = HabitEngine.streakDays(
            articles: try context.fetch(FetchDescriptor<Article>()))
        #expect(after == before)
    }

    @Test("a Concept the reader's own reading discovered survives migration")
    func strayConceptSurvives() throws {
        let context = try makeContext()
        try legacyInstall(context)
        let stray = Concept(name: "Some Article Term", category: "Vocabulary", definition: "d")
        stray.masteryLevel = 0.4
        context.insert(stray)
        try context.save()

        PackMigration.ensureBuiltinInstalled(context: context)

        let survivor = try #require(try concept("Some Article Term", in: context))
        #expect(survivor.masteryLevel == 0.4)
        // It is not part of the Pack, so it stays out of the Frontier.
        #expect(!ActivePack.inUse.conceptNames.contains("Some Article Term"))
    }

    // MARK: - A Pack the reader chose

    @Test("launch leaves a Pack the reader chose alone, even when the built-in moves on")
    func chosenPackSurvivesLaunch() throws {
        let context = try makeContext()
        let chosen = try BuiltinPacks.load(BuiltinPacks.securityEngineeringFileName)
        try PackInstaller.install(chosen, origin: .imported, context: context)
        // As if the app had shipped a new version of its built-in Pack.
        UserDefaults.standard.removeObject(forKey: "builtinPackVersion")
        ActivePackIdentity.forget()

        PackMigration.ensureBuiltinInstalled(context: context)

        // The flagship must not have installed itself over the reader's choice.
        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == chosen.field)
        #expect(active.origin == .imported)
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == chosen.concepts.count)
    }

    @Test("the built-in Pack that gets refreshed is the one the reader is actually on")
    func refreshFollowsTheActiveBuiltin() throws {
        let context = try makeContext()
        let chosen = try BuiltinPacks.load(BuiltinPacks.securityEngineeringFileName)
        try PackInstaller.install(chosen, origin: .builtin, context: context)
        UserDefaults.standard.removeObject(forKey: "builtinPackVersion")
        ActivePackIdentity.forget()

        PackMigration.ensureBuiltinInstalled(context: context)

        #expect(ActivePack.load(context: context)?.field == chosen.field)
        #expect(try context.fetch(FetchDescriptor<InstalledPack>()).filter(\.isActive).count == 1)
        // Refreshed from its file rather than skipped: the version is recorded,
        // so the next launch has nothing to do.
        #expect(UserDefaults.standard.integer(forKey: "builtinPackVersion")
                == PackMigration.builtinPackVersion)
    }

    // MARK: - The engines now read the installed Pack

    @Test("after migration the engines read the installed Pack, not the compiled one")
    func enginesReadInstalledPack() throws {
        let context = try makeContext()
        PackMigration.ensureBuiltinInstalled(context: context)

        // `current` is the installed Pack, not the compiled fallback.
        let installed = try #require(ActivePack.load(context: context))
        #expect(ActivePack.inUse.conceptNames == installed.conceptNames)

        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())

        // Frontier, stages and side quests all answer against it.
        let frontier = KnowledgePathEngine.frontier(concepts: concepts, dependencies: deps)
        #expect(!frontier.isEmpty)
        #expect(frontier.allSatisfy(Set(installed.conceptNames).contains))

        #expect(KnowledgePathEngine.stageProgress(concepts: concepts).count
                == installed.stages.count)
        #expect(KnowledgePathEngine.sideQuestProgress(concepts: concepts).total
                == installed.sideQuestConcepts.count)
    }

    @Test("the Next Dot is a Concept with no unlit Dependencies, in reading order")
    func nextDotIsSane() throws {
        let context = try makeContext()
        PackMigration.ensureBuiltinInstalled(context: context)
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())

        let recommendation = try #require(
            KnowledgePathEngine.nextDot(concepts: concepts, dependencies: deps, articles: []))

        // Nothing is lit yet, so the recommendation must be a root — a Concept
        // that depends on nothing. ADR-0004 having removed the alphabetical
        // fallback, this is the Pack's order talking, not the alphabet.
        let itsDependencies = deps.filter { $0.dependent == recommendation.concept.name }
        #expect(itsDependencies.isEmpty)
        #expect(recommendation.concept.name == KnowledgePack.stages[0].conceptNames[0])
    }
}
