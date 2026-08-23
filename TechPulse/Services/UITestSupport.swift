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

    /// Pass alongside the wipe to plant Sources in the two states a journey
    /// cannot otherwise reach: throttled, and answering but long dead.
    static let seedSourceHealthArgument = "-uitest-seed-source-health"

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

    /// Sources in known health, for the journey that photographs a Settings
    /// row saying so (#14).
    ///
    /// Planted rather than produced, because producing them means a host that
    /// really 429s and a publisher that really stopped in 2020 — a journey that
    /// asserts on the network asserts on the weather. The states themselves are
    /// held to `FeedSyncService`'s behaviour by `FeedSyncTests` against
    /// `StubTransport`; this fixture is only about whether the reader can see
    /// them.
    ///
    /// Both carry a `lastFetched`, which also settles the journey's other
    /// hazard: the Feed syncs on launch when nothing has been fetched for
    /// half an hour, so without a recent date here the journey would go to the
    /// real network and overwrite the very states it came to photograph.
    enum SeededHealth {
        static let throttledName = "Throttled Source"
        static let stoppedName = "Stopped Source"

        /// The Cluster both are filed under — an existing one, so the journey
        /// photographs the list a reader really has rather than a lane of its
        /// own that nothing else would ever be in.
        static let category = "LLMs"

        /// How long ago the throttled Source last worked. Long enough that
        /// "answered 3 days ago" beside a live failure reads as the two
        /// different facts they are.
        static let lastWorked: TimeInterval = 3 * 86_400

        /// How long ago the stopped Source last published. Past
        /// `SourceHealth.likelyDeadAfter` by years, as Kaggle's Medium blog is.
        static let stoppedPublishing: TimeInterval = 5 * 365 * 86_400
    }

    /// Defaults that outlive a store wipe and would otherwise keep seeding and
    /// onboarding in whatever state the last run left them.
    private static let seedingDefaultsKeys = [
        "hasOnboarded", "resumeKnowledgeSeeded", "builtinPackVersion", "knowledgePackVersion",
    ] + ReminderScheduler.defaultsKeys + PackSourceOffer.defaultsKeys

    static var isResetRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(resetStoreArgument)
    }

    /// Empties every model type, clears the seeding defaults, and forgets which
    /// Pack the reader was on — leaving the app exactly as a fresh install, the
    /// caller then seeding as it always does. All three, because a fresh
    /// install remembers nothing anywhere, and the one this used to miss lives
    /// in `UserDefaults` precisely so a store wipe cannot reach it.
    ///
    /// Deletes row by row rather than with `delete(model:)`: a batch delete does
    /// not maintain inverse relationships, which is how an earlier version of
    /// this codebase left dangling `ConceptLink` rows behind. Order runs from the
    /// rows that reference others to the rows they reference.
    @MainActor
    static func resetStoreIfRequested(context: ModelContext) {
        guard isResetRequested else { return }
        resetStore(context: context)
    }

    /// Separate from the argument check so a test can wipe without launching
    /// the app, and assert on what a wiped store opens as.
    @MainActor
    static func resetStore(context: ModelContext) {
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
        // Which Pack the reader was on is remembered outside the store (#37),
        // which is the point of it — and it means emptying the store does not
        // touch it. A wipe that left it behind opened the next launch on a Pack
        // a *previous* journey had switched to, with none of its Concepts in
        // the store: `openOnTheRememberedPack` reinstalls the remembered Pack,
        // so the planted Article was matched against the wrong vocabulary and
        // reached the reader bare (#38).
        ActivePackIdentity.forget()
        ActivePack.resetCache()
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

    static func seedSourceHealthIfRequested(context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains(seedSourceHealthArgument) else { return }
        seedSourceHealth(context: context)
    }

    /// Plants the two Sources. Separate from the argument check so a test can
    /// plant them without launching the app, and assert what health makes of
    /// them.
    static func seedSourceHealth(context: ModelContext) {
        let throttled = FeedSource(name: SeededHealth.throttledName,
                                   url: URL(string: "https://throttled.uitest.invalid/feed.xml")!,
                                   category: SeededHealth.category)
        throttled.lastFetched = .now.addingTimeInterval(-SeededHealth.lastWorked)
        throttled.newestOffered = .now.addingTimeInterval(-SeededHealth.lastWorked)
        throttled.lastFailure = .throttled
        context.insert(throttled)

        let stopped = FeedSource(name: SeededHealth.stoppedName,
                                 url: URL(string: "https://stopped.uitest.invalid/feed.xml")!,
                                 category: SeededHealth.category)
        stopped.lastFetched = .now
        stopped.newestOffered = .now.addingTimeInterval(-SeededHealth.stoppedPublishing)
        context.insert(stopped)

        // The cache each of them is reported against: the throttled one still
        // has reading in it, which is the offline-first half — failing out loud
        // must not read as having lost anything.
        for index in 0..<2 {
            context.insert(Article(guid: "uitest-throttled-\(index)",
                                   title: "Cached before the throttling \(index)",
                                   content: "Body",
                                   publishedAt: .now.addingTimeInterval(-SeededHealth.lastWorked),
                                   sourceName: SeededHealth.throttledName))
        }
        context.insert(Article(guid: "uitest-stopped-0",
                               title: "The last thing this Source ever published",
                               content: "Body",
                               publishedAt: .now.addingTimeInterval(-SeededHealth.stoppedPublishing),
                               sourceName: SeededHealth.stoppedName))
        try? context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        for row in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
            context.delete(row)
        }
    }
}
#endif
