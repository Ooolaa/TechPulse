#if DEBUG
import Foundation
import SwiftData

/// Lets a UI test launch the app into a known state.
///
/// Without this there is no way to run a journey against anything but whatever
/// the simulator accumulated from previous runs, and #26 is what that costs: a
/// journey whose verdict depended on how many Articles a Concept had collected
/// and whether an earlier run had already marked it known. A test that asserts
/// on data a previous run can consume is not testing the code.
///
/// `DEBUG` only, so it cannot ship. Launch arguments reach a sandboxed app from
/// Xcode and XCUITest, not from another app, but the app built for release does
/// not contain this at all.
enum UITestSupport {
    /// Pass in `app.launchArguments` to wipe the store before the first frame.
    static let resetStoreArgument = "-uitest-reset-store"

    /// Pass alongside the wipe to plant one known Article at the top of the Feed.
    static let seedArticleArgument = "-uitest-seed-article"

    /// The Article the core journey reads.
    ///
    /// Without it, "open a Concept from an Article" depended on whether the
    /// news that morning happened to name something on the map: analysis
    /// attaches Concepts by matching the Pack's vocabulary (or by reading the
    /// text, on hardware with the on-device model), so a quiet day left the
    /// journey with no chip to tap — and the journey skipped four steps and
    /// stayed green (#30). The store wipe made the *store* known; this makes
    /// the reading known too.
    ///
    /// The text names Pack Concepts from `ai-engineer.json` that no resume
    /// project already marks Known, so the sheet it opens still has an
    /// "I know this" left to press. Mirrored in `TechPulseUITests`.
    enum SeededArticle {
        static let guid = "uitest-seeded-article"
        static let title = "How embeddings, attention and RAG fit together"
        static let sourceName = "TechPulse Journey"
        static let body = """
            Every retrieval stack starts the same way. Tokenization splits the \
            text into pieces a model can count, and embeddings turn those pieces \
            into vectors whose distances mean something.

            Attention is what a transformer does with them: for each output it \
            weighs which inputs matter, which is why context length and cost \
            move together. RAG puts the two ideas to work — chunking a corpus, \
            storing the chunks in vector databases, and retrieving the closest \
            ones so the answer is grounded in your data rather than in the \
            model's memory.

            Quantization is the other half of the bill: smaller weights, more \
            requests per GPU, and a quality loss you measure rather than assume.
            """
    }

    /// Defaults that outlive a store wipe and would otherwise keep seeding and
    /// onboarding in whatever state the last run left them.
    private static let seedingDefaultsKeys = [
        "hasOnboarded", "resumeKnowledgeSeeded", "builtinPackVersion", "knowledgePackVersion",
    ]

    static var isResetRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(resetStoreArgument)
    }

    /// Empties every model type and clears the seeding defaults, leaving the app
    /// exactly as a fresh install — the caller then seeds as it always does.
    ///
    /// Deletes row by row rather than with `delete(model:)`: a batch delete does
    /// not maintain inverse relationships, which is how an earlier version of
    /// this codebase left dangling `ConceptLink` rows behind. Order runs from the
    /// rows that reference others to the rows they reference.
    static func resetStoreIfRequested(context: ModelContext) {
        guard isResetRequested else { return }

        deleteAll(LearningEvent.self, in: context)
        deleteAll(ConceptLink.self, in: context)
        deleteAll(SemanticLink.self, in: context)
        deleteAll(ConceptDependency.self, in: context)
        deleteAll(Article.self, in: context)
        deleteAll(Concept.self, in: context)
        deleteAll(FeedSource.self, in: context)
        deleteAll(InstalledPack.self, in: context)

        for key in seedingDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try? context.save()
    }

    /// Plants `SeededArticle` as the newest Article, unanalyzed — the app's own
    /// analysis is what attaches Concepts to it, so the journey still tests
    /// that and not a fixture.
    ///
    /// Planted as *already read*, which is the part that matters for the
    /// related-Concept step: `rebuildCoreadLinks` scores readings, and only an
    /// Article the reader opened is one. Without a reading in the store, a
    /// Concept met for the first time has no Co-read Link to anything and the
    /// sheet's "Related concepts" section cannot appear — so that step could
    /// never run, which is the defect #30 is about rather than a fix for it.
    static func seedArticleIfRequested(context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains(seedArticleArgument) else { return }
        seedArticle(context: context)
    }

    /// Plants the Article. Separate from the argument check so a test can plant
    /// it without launching the app, and assert on what analysis makes of it.
    static func seedArticle(context: ModelContext) {
        let article = Article(guid: SeededArticle.guid,
                              title: SeededArticle.title,
                              content: SeededArticle.body,
                              publishedAt: .now,
                              sourceName: SeededArticle.sourceName)
        article.isRead = true
        article.readAt = .now
        context.insert(article)
        try? context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        for row in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
            context.delete(row)
        }
    }
}
#endif
