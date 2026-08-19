import AppIntents
import SwiftData

/// Siri: "What did I learn this week?" (spec §9)
struct WeeklyLearningIntent: AppIntent {
    static let title: LocalizedStringResource = "What did I learn this week?"
    static let description = IntentDescription("Summarizes concepts you learned in the past 7 days.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try AppSchema.container()
        let names = Self.conceptsAdvanced(inWeekBefore: .now, context: container.mainContext)
        return .result(dialog: IntentDialog(stringLiteral: Self.spokenAnswer(for: names)))
    }

    /// What Siri says back. Built as a `String` so it can be read in a test —
    /// the dialog `perform` returns is hidden behind an opaque type, so a test
    /// that only calls `perform` can't tell a right answer from a wrong one.
    static func spokenAnswer(for names: [String]) -> String {
        guard !names.isEmpty else {
            return "No new concepts this week — open TechPulse and read a few articles."
        }
        // Six is what fits in something spoken aloud; the count is the honest
        // total either way.
        let list = names.prefix(6).joined(separator: ", ")
        return "This week you advanced \(names.count) concept\(names.count == 1 ? "" : "s"): \(list)."
    }

    /// The Concepts the reader advanced in the seven days before `now`, named
    /// once each however many readings moved them. A reading that moved no
    /// Mastery isn't something you learned, so it doesn't count.
    ///
    /// The window has a floor and no ceiling: a `LearningEvent` dated in the
    /// future is reported too. That is the rule as it has always been, and a
    /// future-dated Source timestamp has reached this store before — but it is
    /// a question about the week, not about the schema this file was opened to
    /// fix, so it is left as it stands.
    static func conceptsAdvanced(inWeekBefore now: Date, context: ModelContext) -> [String] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let descriptor = FetchDescriptor<LearningEvent>(
            predicate: #Predicate { $0.date > weekAgo && $0.masteryDelta > 0 }
        )
        let events = (try? context.fetch(descriptor)) ?? []
        return Array(Set(events.map(\.conceptName))).sorted()
    }
}

struct TechPulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WeeklyLearningIntent(),
            phrases: ["What did I learn this week in \(.applicationName)?"],
            shortTitle: "Weekly learning",
            systemImageName: "point.3.connected.trianglepath.dotted"
        )
    }
}
