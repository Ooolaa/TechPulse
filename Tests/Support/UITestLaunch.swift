import Foundation

/// The launch arguments and fixture text the UI journeys drive the app with.
///
/// Mirrors `UITestSupport` in the app target, which the UI test bundle cannot
/// link. It lives here rather than in the journeys because `Tests/Support` also
/// compiles into the *unit* bundle — which does link the app — so
/// `UITestLaunchTests` asserts the two copies still match. Three "if one
/// changes, change both" comments were asking the next reader to remember
/// something a test can check.
enum UITestLaunch {
    static let resetStore = "-uitest-reset-store"
    static let seedArticle = "-uitest-seed-article"
    static let seededArticleTitle = "How embeddings, attention and RAG fit together"
}
