import Foundation

/// The Atomic Habits loop's arithmetic, in one place.
///
/// Extracted from FeedView/ProgressTabView, which each carried an identical
/// copy of the streak walk. The widget is a third consumer, and three copies
/// of a rule this easy to get subtly wrong is two too many.
///
/// `@MainActor` like every sibling engine: it reads SwiftData models, and
/// `snapshot` composes `KnowledgePathEngine`, which is main-actor isolated.
@MainActor
enum HabitEngine {

    /// Articles whose first read landed today.
    static func readToday(articles: [Article], now: Date = .now) -> Int {
        let todayStart = Calendar.current.startOfDay(for: now)
        return articles.count { ($0.readAt ?? .distantPast) >= todayStart }
    }

    /// Length of the current Streak, in days.
    ///
    /// The Streak survives a day that hasn't been extended *yet*: it is measured
    /// from today when today has a read, otherwise from yesterday. Only a full
    /// missed day breaks it. Without that grace the home-screen widget would
    /// read "0-day streak" every morning on a 30-day one — the exact opposite
    /// of the cue it exists to give.
    ///
    /// `now` is injected so tests don't depend on the wall clock.
    static func streakDays(articles: [Article], now: Date = .now) -> Int {
        let calendar = Calendar.current
        let readDays = Set(articles.compactMap(\.readAt).map { calendar.startOfDay(for: $0) })
        guard !readDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)

        // Anchor on today if it counts, else on yesterday's still-live Streak.
        var day: Date
        if readDays.contains(today) {
            day = today
        } else if let yesterday, readDays.contains(yesterday) {
            day = yesterday
        } else {
            return 0
        }

        var streak = 0
        while readDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Everything the widget renders, resolved in the app process where the
    /// store and the knowledge pack are already warm.
    static func snapshot(articles: [Article],
                         concepts: [Concept],
                         dependencies: [ConceptDependency],
                         dailyGoal: Int,
                         now: Date = .now) -> WidgetSnapshot {
        let recommendation = KnowledgePathEngine.nextDot(concepts: concepts,
                                                         dependencies: dependencies,
                                                         articles: articles)
        return WidgetSnapshot(
            streakDays: streakDays(articles: articles, now: now),
            readToday: readToday(articles: articles, now: now),
            dailyGoal: dailyGoal,
            nextDotName: recommendation?.concept.name,
            nextDotCluster: recommendation?.concept.category,
            conceptsLit: concepts.filter(KnowledgePathEngine.isLit).count,
            conceptsTotal: concepts.count,
            generatedAt: now
        )
    }
}
