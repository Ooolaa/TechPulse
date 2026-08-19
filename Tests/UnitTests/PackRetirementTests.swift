import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// Switching Packs is a tap since #7, and every tap used to leave a full
/// `InstalledPack` behind — `conceptNames`, `stages` and `suggestedSources`
/// JSON per switch, which nothing could reclaim (#18).
@MainActor
@Suite("Pack retirement", .serialized)
struct PackRetirementTests {

    private static let sharedContainer: ModelContainer = {
        try! AppSchema.inMemoryContainer()
    }()

    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        for concept in try context.fetch(FetchDescriptor<Concept>()) { context.delete(concept) }
        for dep in try context.fetch(FetchDescriptor<ConceptDependency>()) { context.delete(dep) }
        for link in try context.fetch(FetchDescriptor<SemanticLink>()) { context.delete(link) }
        for link in try context.fetch(FetchDescriptor<ConceptLink>()) { context.delete(link) }
        for event in try context.fetch(FetchDescriptor<LearningEvent>()) { context.delete(event) }
        for article in try context.fetch(FetchDescriptor<Article>()) { context.delete(article) }
        for pack in try context.fetch(FetchDescriptor<InstalledPack>()) { context.delete(pack) }
        try context.save()
        // Install writes both of these; leaving them set would hand the next
        // suite a Pack this one installed.
        ActivePackIdentity.forget()
        ActivePack.resetCache()
        return context
    }

    private func pack(field: String, concept: String) -> PackFile {
        PackFile(field: field, specialtyCluster: nil,
                 clusterOrder: ["Foundations"],
                 concepts: [.init(name: concept, cluster: "Foundations",
                                  definition: "d", dependencies: [])],
                 stages: [.init(title: "Start", subtitle: "s", concepts: [concept])],
                 suggestedSources: [.init(name: "Feed", url: "https://feeds.test/a.xml",
                                          category: "Foundations")])
    }

    @discardableResult
    private func install(_ pack: PackFile, origin: PackOrigin = .builtin,
                         into context: ModelContext) throws -> InstalledPack {
        try PackInstaller.install(pack, origin: origin, context: context, vector: { _ in nil })
    }

    private func records(_ context: ModelContext) throws -> [InstalledPack] {
        try context.fetch(FetchDescriptor<InstalledPack>())
    }

    // MARK: Storage stops growing

    @Test("switching between two Packs any number of times leaves one record each")
    func switchingIsFlat() throws {
        let context = try makeContext()
        let ai = pack(field: "AI Engineering", concept: "Attention")
        let security = pack(field: "Security Engineering", concept: "Threat Modelling")

        for _ in 0..<4 {
            try install(ai, into: context)
            try install(security, into: context)
        }

        #expect(try records(context).count == 2, "eight taps must not leave eight records")
        #expect(try records(context).filter(\.isActive).count == 1)
        #expect(try records(context).first(where: \.isActive)?.field == "Security Engineering")
    }

    @Test("reinstalling the same Pack replaces its record rather than adding one")
    func reinstallingReplaces() throws {
        let context = try makeContext()
        let ai = pack(field: "AI Engineering", concept: "Attention")

        try install(ai, into: context)
        try install(ai, into: context)
        try install(ai, into: context)

        #expect(try records(context).count == 1)
    }

    @Test("a Pack the reader brought keeps its own record, field name notwithstanding")
    func sameFieldDifferentOriginKeepsBoth() throws {
        // Origin is part of which Pack this is: a built-in can be reinstalled
        // from the file it ships in, and an imported one cannot, so collapsing
        // the two would throw away the only copy of the imported Pack's Stages.
        let context = try makeContext()
        let builtin = pack(field: "AI Engineering", concept: "Attention")
        let brought = pack(field: "AI Engineering", concept: "Attention")

        try install(builtin, origin: .builtin, into: context)
        try install(brought, origin: .imported, into: context)

        #expect(try records(context).count == 2)
        #expect(try records(context).filter(\.isActive).count == 1)
    }

    // MARK: What pruning must not touch

    @Test("switching Packs repeatedly leaves Mastery, history and the Streak alone")
    func learningSurvivesEverySwitch() throws {
        let context = try makeContext()
        let ai = pack(field: "AI Engineering", concept: "Attention")
        let security = pack(field: "Security Engineering", concept: "Threat Modelling")
        try install(ai, into: context)

        let attention = try #require(try context.fetch(FetchDescriptor<Concept>())
            .first { $0.name == "Attention" })
        attention.masteryLevel = 0.75
        attention.isMarkedKnown = true
        context.insert(LearningEvent(kind: "read", conceptName: "Attention", masteryDelta: 0.1))
        context.insert(LearningEvent(kind: "quizPassed", conceptName: "Attention", masteryDelta: 0.2))
        let article = Article(guid: "read-1", title: "t", content: "c",
                              publishedAt: .now, sourceName: "s")
        article.isRead = true
        article.readAt = .now
        context.insert(article)
        try context.save()

        for _ in 0..<3 {
            try install(security, into: context)
            try install(ai, into: context)
        }

        let after = try #require(try context.fetch(FetchDescriptor<Concept>())
            .first { $0.name == "Attention" })
        #expect(after.masteryLevel == 0.75)
        #expect(after.isMarkedKnown)
        #expect(try context.fetch(FetchDescriptor<LearningEvent>()).count == 2)
        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(HabitEngine.streakDays(articles: articles) == 1)
    }

    @Test("the record a lost Pack would be recovered from survives being retired")
    func retiredRecordStaysIntactForRecovery() throws {
        // `PackMigration.openOnTheRememberedPack` reactivates an intact record
        // rather than rebuilding a narrower Pack from the map (#37). Pruning
        // duplicates must not take that record with them.
        let context = try makeContext()
        let ai = pack(field: "AI Engineering", concept: "Attention")
        let security = pack(field: "Security Engineering", concept: "Threat Modelling")

        try install(ai, into: context)
        try install(security, into: context)

        let retired = try #require(try records(context).first { $0.field == "AI Engineering" })
        #expect(!retired.isActive)
        #expect(retired.stages.count == 1, "the Stages are what reactivating saves over rebuilding")
        #expect(retired.suggestedSources.count == 1)
        #expect(retired.conceptNames == ["Attention"])
    }
}

// MARK: - What Settings reports

@Suite("Store size")
struct StoreSizeTests {

    private func write(_ bytes: Int, to url: URL) throws {
        try Data(repeating: 0x61, count: bytes).write(to: url)
    }

    @Test("the figure counts the write-ahead log, not just the store file")
    func sumsEveryStoreFile() throws {
        // SQLite in WAL mode holds recent writes — including the deletes that
        // reclaim a retired Pack — in `-wal` until it checkpoints. Reporting
        // the store file alone understates what the app is using on disk.
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = directory.appending(path: "default.store")
        try write(1_000, to: store)
        try write(2_000, to: directory.appending(path: "default.store-wal"))
        // Present while the store is open, the same size whatever the reader
        // has, and so not theirs to be charged for.
        try write(500, to: directory.appending(path: "default.store-shm"))

        #expect(StoreSize.onDisk(store) == 3_000)
    }

    @Test("a store that isn't there is zero, not a crash")
    func missingStoreIsZero() {
        #expect(StoreSize.onDisk(URL.temporaryDirectory.appending(path: "\(UUID()).store")) == 0)
    }
}
