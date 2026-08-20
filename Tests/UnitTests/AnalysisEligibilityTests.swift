import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// What analysis records about an Article decides whether it is ever looked at
/// again. `analyzePending` offers Articles whose `summary` is nil, so an
/// Article that came out of analysis with a summary and no Concepts is retired
/// from it — permanently, however much the map later changes (#38).
@MainActor
@Suite("Analysis eligibility", .serialized)
struct AnalysisEligibilityTests {

    private func freshContext() throws -> ModelContext {
        ActivePackIdentity.forget()
        ActivePack.resetCache()
        return ModelContext(try AppSchema.inMemoryContainer())
    }

    private func seeded(_ context: ModelContext) throws -> Article {
        try #require(try context.fetch(FetchDescriptor<Article>())
            .first { $0.guid == UITestSupport.SeededArticle.guid })
    }

    @Test("an Article analysed before its Pack existed is analysed again once it does")
    func analysedTooEarlyIsRetried() async throws {
        let context = try freshContext()

        // Analysis runs with no Concepts in the store: the fallback matches the
        // text against a vocabulary that isn't there and attaches nothing, and
        // the summary it writes is what would retire the Article for good.
        UITestSupport.seedArticle(context: context)
        await IntelligenceService.analyzePending(context: context)
        #expect(try seeded(context).concepts.isEmpty, "nothing to match yet — the premise")

        // The Pack arrives. The Article names seven of its Concepts.
        try PackInstaller.install(try BuiltinPacks.aiEngineer(), origin: .builtin,
                                  context: context, vector: { _ in nil })
        await IntelligenceService.analyzePending(context: context)

        #expect(!(try seeded(context).concepts.isEmpty), """
            analysis attached no Concept to an Article that names seven of them, \
            and was never offered the Article again
            """)
    }

    @Test("an Article that already has Concepts is not re-analysed by an install")
    func alreadyAnalysedIsLeftAlone() async throws {
        let context = try freshContext()
        try PackInstaller.install(try BuiltinPacks.aiEngineer(), origin: .builtin,
                                  context: context, vector: { _ in nil })
        UITestSupport.seedArticle(context: context)
        await IntelligenceService.analyzePending(context: context)

        let summary = try seeded(context).summary
        #expect(summary != nil)
        #expect(!(try seeded(context).concepts.isEmpty))

        // Reinstalling must not throw away a summary that cost a model call.
        try PackInstaller.install(try BuiltinPacks.aiEngineer(), origin: .builtin,
                                  context: context, vector: { _ in nil })
        #expect(try seeded(context).summary == summary)
    }

    @Test("a model answer with no Concepts does not beat matching the Pack's own words")
    func emptyModelAnswerFallsBack() {
        // The other way this Article ends up bare: on hardware where the model
        // does answer, an answer naming no Concept is not better information
        // than the Pack's own vocabulary sitting in the text.
        let vocabulary = [(name: "Attention", category: "Foundations", definition: "d"),
                          (name: "Embeddings", category: "Foundations", definition: "d")]
        let analysis = IntelligenceService.fallbackAnalysis(
            title: UITestSupport.SeededArticle.title,
            body: UITestSupport.SeededArticle.body,
            vocabulary: vocabulary)
        #expect(analysis.concepts.count == 2)
    }
}

/// The wipe behind `-uitest-reset-store` claims to leave the app "exactly as a
/// fresh install". It emptied the store and four seeding defaults, and left the
/// two that say which Pack the reader was on — so a wiped store opened on a
/// Pack a *previous* run had switched to (#38).
@MainActor
@Suite("Reset store", .serialized)
struct ResetStoreTests {

    @Test("a wiped store does not remember the Pack the last run switched to")
    func wipeForgetsTheRememberedPack() throws {
        let context = ModelContext(try AppSchema.inMemoryContainer())
        ActivePackIdentity.remember(field: "Security Engineering", origin: .builtin)

        UITestSupport.resetStore(context: context)

        #expect(ActivePackIdentity.recalled == nil, """
            the wipe leaves the identity behind, so launch reinstalls a Pack \
            this store never had
            """)
    }

    @Test("a wiped store opens on the flagship, and the planted Article finds it")
    func wipedStoreOpensOnTheFlagship() async throws {
        // The journey's own sequence: a run that switched Packs, then a wiped
        // launch that plants the Article and analyses it. The Article names AI
        // Engineering's Concepts, so a store that came back on Security
        // Engineering matches none of them — which is the 90-second wait.
        let context = ModelContext(try AppSchema.inMemoryContainer())
        ActivePackIdentity.remember(field: "Security Engineering", origin: .builtin)
        ActivePack.resetCache()

        UITestSupport.resetStore(context: context)
        SeedData.seedIfNeeded(context: context)
        UITestSupport.seedArticle(context: context)
        await IntelligenceService.analyzePending(context: context)

        let active = try context.fetch(FetchDescriptor<InstalledPack>()).first { $0.isActive }
        #expect(active?.field == "AI Engineering")

        let seeded = try #require(try context.fetch(FetchDescriptor<Article>())
            .first { $0.guid == UITestSupport.SeededArticle.guid })
        #expect(!seeded.concepts.isEmpty, """
            analysis attached no Concept to an Article that names seven of them \
            — the symptom the journey reports
            """)
    }
}
