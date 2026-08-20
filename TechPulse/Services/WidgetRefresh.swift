import Foundation
import SwiftData
import WidgetKit

/// Bridges the app's store to what the reader sees while they are not in the
/// app: the widget's snapshot file, and the reminder their Reading Intention
/// asks for. Both are the same day's state pointed outward, and both are wrong
/// the moment a read lands and nothing tells them.
///
/// Kept apart from `HabitEngine` so that engine stays free of WidgetKit.
@MainActor
enum WidgetRefresh {

    /// `@AppStorage("dailyReadingGoal")` default. `UserDefaults.integer`
    /// returns 0 for an unset key, which would make the goal ring divide by a
    /// goal the user never chose — fall back to the same tiny default.
    static var dailyGoal: Int {
        let stored = UserDefaults.standard.integer(forKey: "dailyReadingGoal")
        return stored > 0 ? stored : 3
    }

    /// Recompute the snapshot and ask WidgetKit to redraw. Cheap enough to
    /// call on every mastery event; skips the reload when nothing changed so
    /// we don't spend the widget's refresh budget on identical timelines.
    static func refresh(context: ModelContext) {
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        let concepts = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        let dependencies = (try? context.fetch(FetchDescriptor<ConceptDependency>())) ?? []

        let snapshot = HabitEngine.snapshot(articles: articles,
                                            concepts: concepts,
                                            dependencies: dependencies,
                                            dailyGoal: dailyGoal)

        // Ahead of the widget's own change check: a read that leaves the
        // snapshot identical still moves the reminder to tomorrow, because what
        // it asks for has been done. What is *waiting* is what arrived recently
        // and has not been read — the feed the reader would actually open, not
        // every unread row the store has ever held.
        let recent = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .distantPast
        let unread = articles.count { !$0.isRead && $0.publishedAt >= recent }
        Task {
            await ReminderScheduler.reschedule(waiting: unread,
                                               streakDays: snapshot.streakDays,
                                               hasReadToday: snapshot.readToday > 0)
        }

        // generatedAt always differs; compare everything else.
        if var previous = WidgetSnapshot.load() {
            previous.generatedAt = snapshot.generatedAt
            guard previous != snapshot else { return }
        }

        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
