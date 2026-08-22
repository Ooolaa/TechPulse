import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// The fixture the other suites rest on, asserted rather than assumed (#40).
///
/// Every suite that uses `TestStore` reads its own assertions as "given a store
/// with nothing in it". Nine hand-written copies of that promise each kept it
/// to a different extent, so it is worth one suite of its own.
@MainActor
@Suite("Test store", .serialized)
struct TestStoreTests {

    private static let store = TestStore()
    private func makeContext() throws -> ModelContext { try Self.store.makeContext() }

    /// One row of every model the schema names, so the clear has something of
    /// each to miss. Written out because a row has to be constructed — what
    /// must not be written out is the list the *clear* walks, and that comes
    /// from `AppSchema`.
    ///
    /// Returns the models it seeded, taken from the rows themselves rather than
    /// listed a second time. The premise below is about this fixture and not
    /// about the schema: a model added to `AppSchema` is cleared by derivation,
    /// seeded here or not.
    private func seedEveryTable(_ context: ModelContext) -> Set<String> {
        var seeded: Set<String> = []
        func insert<Model: PersistentModel>(_ row: Model) {
            context.insert(row)
            seeded.insert(String(describing: Model.self))
        }
        let concept = Concept(name: "Attention", category: "Foundations", definition: "d")
        let article = Article(guid: "g", title: "t", content: "c",
                              publishedAt: .now, sourceName: "s")
        article.concepts = [concept]
        insert(concept)
        insert(article)
        insert(FeedSource(name: "Feed", url: URL(string: "https://feeds.test/a.xml")!,
                          category: "Foundations"))
        insert(LearningEvent(kind: "read", conceptName: "Attention", masteryDelta: 0.1))
        insert(ConceptLink(conceptA: "Attention", conceptB: "Embeddings"))
        insert(ConceptDependency(prerequisite: "Embeddings", dependent: "Attention"))
        insert(SemanticLink(conceptA: "Attention", conceptB: "Embeddings", strength: 0.5))
        insert(InstalledPack(field: "AI Engineering", specialtyCluster: nil,
                             clusterOrder: ["Foundations"], stages: [],
                             suggestedSources: [], conceptNames: ["Attention"],
                             sideQuestConcepts: [], origin: .builtin))
        return seeded
    }

    private func rowCounts(_ context: ModelContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for model in AppSchema.models {
            counts[String(describing: model)] = try Self.count(of: model, in: context)
        }
        return counts
    }

    /// Opens a model the same way `TestStore` does, deliberately rather than by
    /// borrowing its opener: a test that counted rows through the code under
    /// test would agree with it by construction.
    private static func count<Model: PersistentModel>(
        of type: Model.Type, in context: ModelContext
    ) throws -> Int {
        try context.fetchCount(FetchDescriptor<Model>())
    }

    // MARK: - Rows

    @Test("a context arrives with no rows of any model the schema names")
    func everyTableIsCleared() throws {
        let dirty = try makeContext()
        let seeded = seedEveryTable(dirty)
        try dirty.save()
        let filled = try rowCounts(dirty).filter { $0.value > 0 }
        #expect(Set(filled.keys) == seeded,
                "the premise: every table this fixture seeds has something in it to be missed")

        let fresh = try makeContext()

        // Counted over `AppSchema`, so this assertion covers a model added to
        // the app without being widened by hand.
        let left = try rowCounts(fresh).filter { $0.value > 0 }
        #expect(left.isEmpty, "rows inherited from the previous test: \(left)")
    }

    // MARK: - What a Pack install writes outside the store

    @Test("the Pack the last test installed is not the next test's Active Pack")
    func packStateIsCleared() throws {
        let context = try makeContext()
        try PackInstaller.install(
            PackFile(field: "Baking", specialtyCluster: nil, clusterOrder: ["Ingredients"],
                     concepts: [.init(name: "Flour", cluster: "Ingredients",
                                      definition: "d", dependencies: [])],
                     stages: [], suggestedSources: []),
            origin: .imported, context: context)
        #expect(ActivePack.load(context: context)?.field == "Baking", "the premise")
        #expect(ActivePackIdentity.recalled?.field == "Baking", "the premise")

        let fresh = try makeContext()

        #expect(ActivePack.load(context: fresh) == nil)
        #expect(ActivePackIdentity.recalled == nil,
                "a Pack remembered outside the store outlives the rows that described it")
    }
}
