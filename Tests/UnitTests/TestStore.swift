import Foundation
import SwiftData
@testable import TechPulse

/// The store a unit suite runs against: one in-memory container, held for the
/// suite, emptied before each test.
///
/// Nine suites carried a copy of this before (#40) — fetch every model type,
/// delete the rows, save, hand back the context — and five more carried it
/// under another name. They disagreed about which types they bothered to clear,
/// and the disagreement was silent: a suite that forgot a type inherited the
/// previous test's rows rather than failing. A fifteenth shared a store and
/// cleared nothing at all, staying honest only by never reusing a date.
///
/// Two things follow from that, and they are what this type is for:
///
/// - **The model list comes from `AppSchema`.** `AppSchema` names the app's
///   models once, which is what #21 was about — a hand-written list at one call
///   site migrated the store *down* to it and dropped the reader's installed
///   Packs. The tests then hand-wrote that list fourteen more times. Reading it back
///   from the schema means a model added to the app is cleared by every suite
///   without anyone editing a test.
/// - **The process-global state a Pack install writes is cleared too.**
///   Installing a Pack remembers the Pack outside the store
///   (`ActivePackIdentity`) and caches it in the process (`ActivePack`), so a
///   suite that clears only rows starts on the Pack its predecessor installed.
///   Two of them knew that and the rest didn't, which is the "stays true by
///   everyone remembering it" that #36 folded away for the URLProtocol stubs.
///
/// One container per suite rather than one for the test run: Swift Testing runs
/// suites in parallel even when each is `.serialized` within itself, and rows
/// cleared out from under a suite that is mid-test would be a flake nobody
/// could read. Reused *within* a suite because repeated `ModelContainer`
/// creation alongside the host app's live container traps in SwiftData, and
/// because clearing is what keeps these suites fast.
///
/// The two globals are the exception, and they cannot be given the same
/// treatment: they are one per process by definition, so clearing them for
/// every suite is clearing them under the suites running alongside. What makes
/// that safe is not the clearing but who reads them. `ActivePack.load(context:)`
/// fetches from the context it is handed, so a suite asserting on the Pack it
/// installed reads its own store; only `ActivePack.inUse` reads the cache, and
/// the two tests that do are synchronous `@MainActor` bodies, which reach their
/// assertion without ever yielding the actor.
@MainActor
struct TestStore {

    private let container: ModelContainer

    init() {
        container = try! AppSchema.inMemoryContainer()
    }

    /// A context with no rows in it and no Pack remembered — whatever the last
    /// test did.
    ///
    /// Row-by-row deletes rather than `delete(model:)`, so the Article↔Concept
    /// inverse relationship is nullified properly.
    func makeContext() throws -> ModelContext {
        let context = container.mainContext
        for model in AppSchema.models {
            try Self.deleteRows(of: model, in: context)
        }
        try context.save()
        // Cleared after the rows, not before: what these two remember is the
        // Pack the rows described.
        ActivePackIdentity.forget()
        ActivePack.resetCache()
        return context
    }

    /// Opens one of `AppSchema.models` — which is a list of existential
    /// metatypes — far enough to build the `FetchDescriptor` its rows need.
    private static func deleteRows<Model: PersistentModel>(
        of type: Model.Type, in context: ModelContext
    ) throws {
        for row in try context.fetch(FetchDescriptor<Model>()) { context.delete(row) }
    }
}
