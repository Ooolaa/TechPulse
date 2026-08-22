import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// Siri's weekly question, asked against the store the app actually writes.
/// The test host *is* the app, so the on-disk store here is the one
/// `TechPulseApp` created with the app's own schema — an intent whose schema
/// has drifted from it meets the reader's real data, not a fixture (#21).
@MainActor
@Suite("Weekly learning intent", .serialized)
struct WeeklyLearningIntentTests {

    /// One store for the whole suite, as every other suite here has. Only the
    /// test that has to see the store on disk opens a container of its own.
    private static let store = TestStore()

    /// A Pack the app would recognise, retired so it can't become the Active
    /// Pack of whatever runs against this store next.
    private func markerPack(_ field: String) -> InstalledPack {
        let pack = InstalledPack(field: field, specialtyCluster: nil, clusterOrder: [],
                                 stages: [], suggestedSources: [], conceptNames: [],
                                 sideQuestConcepts: [], origin: .builtin)
        pack.isActive = false
        return pack
    }

    // MARK: - The store the app writes

    @Test("asking it leaves the reader's installed Pack where it was")
    func leavesTheInstalledPackAlone() async throws {
        let field = "Siri schema check \(UUID().uuidString)"
        // Opened the way the app opens it, so what this test writes is what the
        // app would have written.
        let store = try AppSchema.container()
        store.mainContext.insert(markerPack(field))
        try store.mainContext.save()
        // The store outlives this test — the app and the journeys read it too.
        defer {
            let packs = (try? store.mainContext.fetch(FetchDescriptor<InstalledPack>())) ?? []
            for pack in packs where pack.field == field { store.mainContext.delete(pack) }
            try? store.mainContext.save()
        }

        _ = try await WeeklyLearningIntent().perform()

        // Read from a second container rather than the one above: a schema the
        // intent narrowed is narrowed *on disk*, and the open container would
        // answer from memory.
        let reopened = try AppSchema.container()
        let packs = try reopened.mainContext.fetch(FetchDescriptor<InstalledPack>())
        #expect(packs.contains { $0.field == field })
    }

    // MARK: - The week it reports on

    @Test("reports the Concepts advanced in the last seven days, and only those")
    func reportsTheWeeksConcepts() throws {
        let context = try Self.store.makeContext()
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        for event in [
            LearningEvent(kind: "read", conceptName: "Attention", masteryDelta: 0.2,
                          date: now.addingTimeInterval(-2 * 86_400)),
            LearningEvent(kind: "read", conceptName: "Embeddings", masteryDelta: 0.2,
                          date: now.addingTimeInterval(-30 * 86_400)),
            // Read again, learned nothing: not a Concept you advanced.
            LearningEvent(kind: "read", conceptName: "Tokenizers", masteryDelta: 0,
                          date: now.addingTimeInterval(-1 * 86_400)),
        ] { context.insert(event) }
        try context.save()

        let names = WeeklyLearningIntent.conceptsAdvanced(inWeekBefore: now, context: context)

        #expect(names == ["Attention"])
    }

    @Test("names a Concept once however many readings advanced it")
    func namesEachConceptOnce() throws {
        let context = try Self.store.makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        for delta in [0.1, 0.1, 0.3] {
            context.insert(LearningEvent(kind: "read", conceptName: "Attention",
                                         masteryDelta: delta,
                                         date: now.addingTimeInterval(-3600)))
        }
        try context.save()

        #expect(WeeklyLearningIntent.conceptsAdvanced(inWeekBefore: now, context: context)
                == ["Attention"])
    }

    // MARK: - What Siri says

    @Test("a week with nothing in it sends the reader back to reading")
    func emptyWeekAnswer() {
        let answer = WeeklyLearningIntent.spokenAnswer(for: [])
        #expect(answer == "No new concepts this week — open TechPulse and read a few articles.")
    }

    @Test("one Concept is spoken in the singular")
    func singleConceptAnswer() {
        #expect(WeeklyLearningIntent.spokenAnswer(for: ["Attention"])
                == "This week you advanced 1 concept: Attention.")
    }

    @Test("several Concepts are named, and the count is the whole week")
    func manyConceptsAnswer() {
        let names = ["Agents", "Attention", "Chunking", "Distillation", "Embeddings",
                     "Fine-tuning", "Grounding", "Hallucination"]
        let answer = WeeklyLearningIntent.spokenAnswer(for: names)

        #expect(answer == "This week you advanced 8 concepts: Agents, Attention, Chunking, "
                + "Distillation, Embeddings, Fine-tuning.")
        // Spoken aloud, six is the limit — but the count is all eight.
        #expect(!answer.contains("Grounding"))
    }
}
