import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// The core journey's premise, at store level: the planted Article names Pack
/// Concepts, analysis attaches them, and reading it joins them to each other.
///
/// The journey asserts all of this through the UI and takes three minutes to do
/// it. Here it takes a second, and it runs on a machine whose simulator has no
/// on-device model — which is the case the fallback exists for.
@MainActor
@Suite("Seeded reading", .serialized)
struct SeededReadingTests {

    private static let store = TestStore()
    private static func freshContext() throws -> ModelContext { try store.makeContext() }

    private func installedFlagship(_ context: ModelContext) throws {
        try PackInstaller.install(try BuiltinPacks.aiEngineer(), origin: .builtin, context: context)
    }

    @Test("the planted Article's own text names Concepts the flagship Pack has")
    func seededArticleNamesPackConcepts() throws {
        let context = try Self.freshContext()
        try installedFlagship(context)
        let vocabulary = try context.fetch(FetchDescriptor<Concept>())
            .map { (name: $0.name, category: $0.category, definition: $0.conceptDefinition) }

        let analysis = IntelligenceService.fallbackAnalysis(
            title: UITestSupport.SeededArticle.title,
            body: UITestSupport.SeededArticle.body,
            vocabulary: vocabulary
        )
        #expect(analysis.concepts.count >= 2,
                "the planted Article names Pack Concepts, so vocabulary matching must find them")
    }

    @Test("analysis attaches Concepts to the planted Article with no model available")
    func analysisAttachesConceptsWithoutAModel() async throws {
        let context = try Self.freshContext()
        try installedFlagship(context)
        UITestSupport.seedArticle(context: context)

        await IntelligenceService.analyzePending(context: context)

        let seeded = try #require(try context.fetch(FetchDescriptor<Article>())
            .first { $0.guid == UITestSupport.SeededArticle.guid })
        #expect(!seeded.concepts.isEmpty, """
            the journey taps a Concept chip on this Article; with no chip there is no sheet, \
            and every step after it is unreachable
            """)
        #expect(seeded.summary != nil)
    }

    @Test("reading the planted Article joins its Concepts to each other")
    func readingTheArticleMakesCoreadLinks() async throws {
        let context = try Self.freshContext()
        try installedFlagship(context)
        UITestSupport.seedArticle(context: context)

        await IntelligenceService.analyzePending(context: context)

        // Co-read Links are what the Article's own sheet offers as "Read
        // together" — the step this Article exists to make deterministic.
        let coread = try context.fetch(FetchDescriptor<ConceptLink>())
        #expect(!coread.isEmpty)
    }
}
