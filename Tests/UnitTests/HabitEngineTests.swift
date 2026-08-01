import Testing
import Foundation
@testable import TechPulse

@MainActor
@Suite("Habit engine")
struct HabitEngineTests {

    /// Fixed midday reference so the walk-back never straddles a DST edge and
    /// the suite can't fail by running near midnight.
    private static let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 15
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    /// An article read `daysAgo` days before the reference date, mid-afternoon.
    private func read(daysAgo: Int) -> Article {
        let article = Article(guid: "g\(daysAgo)-\(UUID().uuidString)", title: "t",
                              content: "c", publishedAt: Self.now, sourceName: "s")
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Self.now)!
        article.isRead = true
        article.readAt = day
        return article
    }

    private func streak(_ articles: [Article]) -> Int {
        HabitEngine.streakDays(articles: articles, now: Self.now)
    }

    // MARK: Streak

    @Test("no reading history is a zero streak, not a crash")
    func emptyHistory() {
        #expect(streak([]) == 0)
        #expect(HabitEngine.readToday(articles: [], now: Self.now) == 0)
    }

    @Test("consecutive days ending today count up")
    func consecutiveEndingToday() {
        #expect(streak([read(daysAgo: 0)]) == 1)
        #expect(streak([read(daysAgo: 0), read(daysAgo: 1), read(daysAgo: 2)]) == 3)
    }

    @Test("a day not yet extended keeps the run alive (grace day)")
    func graceDayHolds() {
        // Read yesterday, nothing today: the widget must not say zero.
        #expect(streak([read(daysAgo: 1)]) == 1)
        #expect(streak([read(daysAgo: 1), read(daysAgo: 2), read(daysAgo: 3)]) == 3)
    }

    @Test("one fully missed day breaks the run")
    func missedDayBreaks() {
        // Last read was two days ago — yesterday was missed entirely.
        #expect(streak([read(daysAgo: 2), read(daysAgo: 3)]) == 0)
    }

    @Test("a gap stops the count even when today was read")
    func gapStopsCount() {
        // Today and three days ago, nothing between: only today counts.
        #expect(streak([read(daysAgo: 0), read(daysAgo: 3)]) == 1)
    }

    @Test("several reads on one day still count as one day")
    func multipleReadsSameDay() {
        #expect(streak([read(daysAgo: 0), read(daysAgo: 0), read(daysAgo: 1)]) == 2)
    }

    // MARK: Today's count

    @Test("readToday counts only today, ignoring unread and older articles")
    func readTodayCounting() {
        let unread = Article(guid: "u", title: "t", content: "c",
                             publishedAt: Self.now, sourceName: "s")
        let articles = [read(daysAgo: 0), read(daysAgo: 0), read(daysAgo: 1), unread]
        #expect(HabitEngine.readToday(articles: articles, now: Self.now) == 2)
    }

    // MARK: Rolling a stale snapshot forward

    @Test("same-day snapshot is untouched")
    func rollForwardSameDay() {
        let snapshot = WidgetSnapshot(streakDays: 5, readToday: 2, dailyGoal: 3,
                                      nextDotName: "Attention", nextDotCluster: "Foundations",
                                      conceptsLit: 40, conceptsTotal: 89, generatedAt: Self.now)
        #expect(snapshot.rolledForward(to: Self.now) == snapshot)
    }

    @Test("next day zeroes today's count but keeps the run")
    func rollForwardOneDay() {
        let snapshot = WidgetSnapshot(streakDays: 5, readToday: 3, dailyGoal: 3,
                                      nextDotName: nil, nextDotCluster: nil,
                                      conceptsLit: 40, conceptsTotal: 89, generatedAt: Self.now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Self.now)!
        let rolled = snapshot.rolledForward(to: tomorrow)
        #expect(rolled.readToday == 0)
        #expect(rolled.streakDays == 5)
        #expect(rolled.streakAtRisk)
    }

    @Test("two days without the app breaks the run")
    func rollForwardTwoDays() {
        let snapshot = WidgetSnapshot(streakDays: 5, readToday: 3, dailyGoal: 3,
                                      nextDotName: nil, nextDotCluster: nil,
                                      conceptsLit: 40, conceptsTotal: 89, generatedAt: Self.now)
        let later = Calendar.current.date(byAdding: .day, value: 2, to: Self.now)!
        let rolled = snapshot.rolledForward(to: later)
        #expect(rolled.readToday == 0)
        #expect(rolled.streakDays == 0)
    }

    // MARK: Display state

    @Test("goal and empty states drive the widget's copy")
    func displayFlags() {
        let fresh = WidgetSnapshot.placeholder
        #expect(fresh.isEmpty)
        #expect(!fresh.goalMet)

        let met = WidgetSnapshot(streakDays: 2, readToday: 3, dailyGoal: 3,
                                 nextDotName: nil, nextDotCluster: nil,
                                 conceptsLit: 1, conceptsTotal: 2, generatedAt: Self.now)
        #expect(met.goalMet)
        #expect(!met.isEmpty)
        #expect(!met.streakAtRisk)
    }
}
