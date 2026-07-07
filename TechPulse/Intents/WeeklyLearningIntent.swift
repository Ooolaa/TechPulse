import AppIntents
import SwiftData

/// Siri: "What did I learn this week?" (spec §9)
struct WeeklyLearningIntent: AppIntent {
    static let title: LocalizedStringResource = "What did I learn this week?"
    static let description = IntentDescription("Summarizes concepts you learned in the past 7 days.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try ModelContainer(
            for: FeedSource.self, Article.self, Concept.self,
            LearningEvent.self, ConceptLink.self
        )
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let descriptor = FetchDescriptor<LearningEvent>(
            predicate: #Predicate { $0.date > weekAgo && $0.masteryDelta > 0 }
        )
        let events = (try? container.mainContext.fetch(descriptor)) ?? []
        let names = Array(Set(events.map(\.conceptName))).sorted()

        let dialog: IntentDialog
        if names.isEmpty {
            dialog = "No new concepts this week — open TechPulse and read a few articles."
        } else {
            let list = names.prefix(6).joined(separator: ", ")
            dialog = "This week you advanced \(names.count) concept\(names.count == 1 ? "" : "s"): \(list)."
        }
        return .result(dialog: dialog)
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
