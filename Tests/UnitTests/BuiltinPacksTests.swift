import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// The AI Engineer map stops being Swift and becomes a Pack file. A reader
/// must see no difference, so these tests compare the shipped file against the
/// compiled pack it replaces, field by field. If the two ever drift, the
/// conversion has silently dropped something and these fail.
@Suite("Built-in Packs")
struct BuiltinPacksTests {

    private func aiEngineer() throws -> PackFile {
        try BuiltinPacks.aiEngineer()
    }

    // MARK: - It is a Pack file, and it loads without a network

    @Test("the AI Engineer Pack ships in the app bundle and passes validation")
    func shipsAndValidates() throws {
        let pack = try aiEngineer()
        try PackValidator.validate(pack)
        #expect(pack.formatVersion == PackFile.currentFormatVersion)
        #expect(pack.field == "AI Engineering")
    }

    @Test("every built-in Pack is discoverable and valid")
    func allBuiltinsLoad() throws {
        #expect(!BuiltinPacks.fileNames.isEmpty)
        for fileName in BuiltinPacks.fileNames {
            try PackValidator.validate(try BuiltinPacks.load(fileName))
        }
    }

    @Test("a Pack that is not in the bundle reports why rather than crashing")
    func missingPackThrows() {
        #expect(throws: PackValidationError.self) {
            _ = try BuiltinPacks.load("no-such-pack")
        }
    }

    // MARK: - Equivalence with the compiled pack

    @Test("Concepts match the compiled pack exactly — name, Cluster and definition")
    func conceptsMatch() throws {
        let pack = try aiEngineer()
        #expect(pack.concepts.count == KnowledgePack.concepts.count)

        let converted = Dictionary(pack.concepts.map { ($0.name, $0) },
                                   uniquingKeysWith: { first, _ in first })
        for compiled in KnowledgePack.concepts {
            let match = try #require(converted[compiled.name],
                                     "converted pack is missing “\(compiled.name)”")
            #expect(match.cluster == compiled.cluster)
            #expect(match.definition == compiled.definition)
        }
    }

    @Test("Concepts appear in the compiled pack's order")
    func conceptOrderMatches() throws {
        #expect(try aiEngineer().concepts.map(\.name) == KnowledgePack.concepts.map(\.name))
    }

    @Test("Dependencies match the compiled pack exactly, in both directions")
    func dependenciesMatch() throws {
        let pack = try aiEngineer()

        func edges(_ pairs: [(String, [String])]) -> Set<String> {
            Set(pairs.flatMap { dependent, dependencies in
                dependencies.map { "\($0)→\(dependent)" }
            })
        }
        let converted = edges(pack.concepts.map { ($0.name, $0.dependencies) })
        let compiled = edges(KnowledgePack.concepts.map { ($0.name, $0.prerequisites) })

        // Stated as two differences rather than one equality: a failure then
        // names the handful of edges at fault instead of dumping all 72.
        #expect(converted.subtracting(compiled).sorted() == [],
                "converted pack invented dependencies")
        #expect(compiled.subtracting(converted).sorted() == [],
                "converted pack dropped dependencies")

        // The edge set alone is order-blind, so compare each Concept's list
        // as authored too.
        let byName = Dictionary(pack.concepts.map { ($0.name, $0.dependencies) },
                                uniquingKeysWith: { first, _ in first })
        for compiled in KnowledgePack.concepts {
            #expect(byName[compiled.name] == compiled.prerequisites,
                    "dependency order drifted for “\(compiled.name)”")
        }
    }

    @Test("Clusters match the compiled pack, in order")
    func clustersMatch() throws {
        #expect(try aiEngineer().clusterOrder == KnowledgePack.clusterOrder)
    }

    @Test("stages match the compiled pack — titles, subtitles and membership")
    func stagesMatch() throws {
        let pack = try aiEngineer()
        #expect(pack.stages.count == KnowledgePack.stages.count)

        for (converted, compiled) in zip(pack.stages, KnowledgePack.stages) {
            #expect(converted.title == compiled.title)
            #expect(converted.subtitle == compiled.subtitle)
            #expect(converted.concepts == compiled.conceptNames)
        }
    }

    @Test("the specialty Cluster matches the compiled pack")
    func specialtyClusterMatches() throws {
        #expect(try aiEngineer().specialtyCluster == KnowledgePack.specialtyCluster)
    }

    @Test("side quests survive as the specialty Cluster's membership")
    func sideQuestsMatch() throws {
        // The format has no side-quest list; it names a specialty Cluster
        // instead. That loses nothing only if the two describe the same set.
        let pack = try aiEngineer()
        let specialty = pack.concepts
            .filter { $0.cluster == pack.specialtyCluster }
            .map(\.name)

        // Compared in order, not as a set: side-quest order is appended
        // verbatim to the reading order, so a reordering is a real change.
        #expect(specialty == KnowledgePack.sideQuestConcepts)
    }

    @Test("the Pack carries its suggested Sources, matching the compiled fixture")
    func carriesSuggestedSources() throws {
        let pack = try aiEngineer()
        #expect(pack.suggestedSources.count == KnowledgePack.suggestedSources.count)

        for (converted, compiled) in zip(pack.suggestedSources, KnowledgePack.suggestedSources) {
            #expect(converted.name == compiled.name)
            #expect(converted.url == compiled.url)
            #expect(converted.category == compiled.category)
        }
        // Every suggestion has to be a URL, or it can never become a Source.
        for source in pack.suggestedSources {
            #expect(URL(string: source.url)?.scheme != nil, "unusable URL: \(source.url)")
        }
    }

    @Test("every Concept the compiled stages name still exists in the Pack")
    func stagesNameRealConcepts() throws {
        let pack = try aiEngineer()
        let names = Set(pack.concepts.map(\.name))
        for stage in pack.stages {
            for concept in stage.concepts {
                #expect(names.contains(concept), "stage names missing concept “\(concept)”")
            }
        }
    }

    // MARK: - It installs

    @Test("the built-in Pack installs, producing the same map the compiled pack seeded")
    @MainActor
    func installsCleanly() throws {
        let container = try AppSchema.inMemoryContainer()
        let context = ModelContext(container)

        let pack = try aiEngineer()
        try PackInstaller.install(pack, origin: .builtin, context: context)

        #expect(try context.fetch(FetchDescriptor<Concept>()).count
                == KnowledgePack.concepts.count)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.clusterOrder == KnowledgePack.clusterOrder)
        #expect(active.conceptNames.count == KnowledgePack.concepts.count)

        // Reading order must still start where the compiled pack started.
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())
        #expect(active.pathOrder(dependencies: deps).first
                == KnowledgePack.stages.first?.conceptNames.first)
    }

    @Test("the built-in Pack round-trips through install and export")
    @MainActor
    func roundTripsThroughInstall() throws {
        let container = try AppSchema.inMemoryContainer()
        let context = ModelContext(container)

        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)
        let exported = try #require(PackInstaller.exportActivePack(context: context))

        try PackValidator.validate(exported)
        #expect(exported.field == "AI Engineering")
        #expect(exported.concepts.map(\.name) == KnowledgePack.concepts.map(\.name))
        #expect(exported.clusterOrder == KnowledgePack.clusterOrder)
    }

    // MARK: - The vote-ranked Source (#46)

    /// ADR-0003 settled that popularity ordering is a property of the URL the
    /// reader subscribed to, not something the app computes about a platform it
    /// knows about. So community attention reaches the 🔥 lane by the flagship
    /// suggesting one vote-ranked feed — and by nothing anywhere in the app
    /// learning that popularity exists.
    @Test("the flagship suggests a vote-ranked Source, in the LLMs cluster")
    func suggestsAVoteRankedSource() throws {
        let community = try #require(
            aiEngineer().suggestedSources.first { $0.url.contains("r/MachineLearning") })
        #expect(community.url == "https://www.reddit.com/r/MachineLearning/top/.rss?t=week")
        #expect(community.category == "LLMs")
    }

    /// One, not several. A single popularity signal is enough, and every extra
    /// reddit.com Source multiplies the throttling #44 had to pace around —
    /// they share a host, so they share a queue.
    @Test("exactly one suggested Source is vote-ranked")
    func onlyOneSourceIsVoteRanked() throws {
        let sources = try aiEngineer().suggestedSources
        #expect(sources.count { $0.url.contains("/top/") } == 1)
        #expect(sources.count { $0.url.contains("reddit.com") } == 2,
                "the vote-ranked one and r/kaggle, and no more than that on one host")
    }

    /// #46 needed this Source in two lists, because the Pack file reached
    /// nobody and a compiled array was what launch actually delivered. Since
    /// #47 there is one list: the Pack file is what a reader's record carries,
    /// and the record is what both first-launch subscription and the standing
    /// offer read. `KnowledgePack.suggestedSources` still pins the conversion,
    /// and delivers nothing.
    @Test("the vote-ranked Source is in the list that actually reaches a reader")
    func voteRankedSourceReachesTheReader() throws {
        #expect(try aiEngineer().suggestedSources.contains {
            $0.url == "https://www.reddit.com/r/MachineLearning/top/.rss?t=week"
                && $0.category == "LLMs"
        })
    }

    /// r/kaggle serves the Data Science Cluster chronologically, which is a
    /// different job from the one the vote-ranked Source does.
    @Test("r/kaggle is left exactly as it was")
    func kaggleIsUnchanged() throws {
        let kaggle = try #require(
            aiEngineer().suggestedSources.first { $0.name.contains("Kaggle") })
        #expect(kaggle.url == "https://www.reddit.com/r/kaggle/.rss")
        #expect(kaggle.category == "Data Science")
    }

    /// A Pack file that changes without the version changing is a Pack file
    /// that never reaches a reader who installed the version before it.
    @MainActor
    @Test("the built-in Pack version moved on with the file")
    func builtinPackVersionMovedOn() {
        #expect(PackMigration.builtinPackVersion >= 2)
    }
}
