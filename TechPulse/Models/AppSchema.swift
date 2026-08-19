import SwiftData

/// Every model the app's store holds, declared once.
///
/// Opening the store with fewer models than it contains does not fail: SwiftData
/// migrates the store down to the schema it was handed and drops the tables the
/// schema doesn't mention. So a stale list at one call site deletes data written
/// by another — Siri's weekly question used to take the reader's installed Packs
/// with it (#21).
///
/// Everything that opens this store — the app, the previews, the intents —
/// opens it from here, so a new model is one edit rather than a list to
/// remember in three places.
enum AppSchema {
    /// Computed rather than stored: a `static let` of model metatypes is global
    /// state the concurrency checker has to reason about, and this is cheap.
    static var models: [any PersistentModel.Type] {
        [FeedSource.self, Article.self, Concept.self,
         LearningEvent.self, ConceptLink.self, ConceptDependency.self,
         SemanticLink.self, InstalledPack.self]
    }

    /// The app's on-disk store — the one the reader's history lives in.
    static func container() throws -> ModelContainer {
        try ModelContainer(for: Schema(models), migrationPlan: nil, configurations: [])
    }

    /// A store that lives no longer than the process, for previews and tests.
    /// Same schema, so what they exercise is the shape the app really has.
    static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(models), migrationPlan: nil,
                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
}
