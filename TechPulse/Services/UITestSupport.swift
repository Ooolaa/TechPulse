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

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        for row in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
            context.delete(row)
        }
    }
}
#endif
