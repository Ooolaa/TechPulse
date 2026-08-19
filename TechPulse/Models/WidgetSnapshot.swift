import Foundation

/// What the widget process needs to render, and nothing more.
///
/// Deliberately free of SwiftData types: widgets get a tight (~30 MB) memory
/// budget, so the extension decodes this small JSON instead of opening the
/// store and re-walking the knowledge pack. The app keeps its own container
/// untouched — the App Group holds only this file, so there is no store
/// migration and no risk to real reading history.
struct WidgetSnapshot: Codable, Equatable {
    var streakDays: Int
    var readToday: Int
    var dailyGoal: Int
    /// First frontier concept in learning-path order, if any remain.
    var nextDotName: String?
    var nextDotCluster: String?
    var conceptsLit: Int
    var conceptsTotal: Int
    var generatedAt: Date

    var goalMet: Bool { readToday >= dailyGoal }

    /// A live Streak that today hasn't extended yet — the cue the widget exists for.
    var streakAtRisk: Bool { streakDays > 0 && readToday == 0 }

    /// Nothing read ever: show an invitation, never a bare zero.
    var isEmpty: Bool { streakDays == 0 && readToday == 0 }

    /// Age a snapshot forward to `now`.
    ///
    /// The app may not run for days, so the widget cannot assume the file is
    /// from today. A new day zeroes today's count; the Streak then survives
    /// only as many further days as `HabitEngine.streakDays` would allow it.
    ///
    /// How many that is depends on the snapshot's own day. `readToday == 0`
    /// means the last read was *yesterday* — the engine's one grace day is
    /// already spent inside the file, so one more elapsed day breaks the
    /// Streak. A snapshot whose own day was read still has that grace, and
    /// breaks on the second.
    func rolledForward(to now: Date) -> WidgetSnapshot {
        let calendar = Calendar.current
        let generatedDay = calendar.startOfDay(for: generatedAt)
        let today = calendar.startOfDay(for: now)
        guard today > generatedDay else { return self }

        let elapsed = calendar.dateComponents([.day], from: generatedDay, to: today).day ?? 0
        let graceLeft = readToday > 0 ? 1 : 0
        var rolled = self
        rolled.readToday = 0
        rolled.streakDays = elapsed > graceLeft ? 0 : streakDays
        return rolled
    }

    static let appGroup = "group.com.johnchen.TechPulse"
    private static let filename = "widget-snapshot.json"

    /// nil when the App Group is unavailable (entitlement missing or not yet
    /// provisioned) — callers treat that as "no data" rather than crashing.
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Placeholder for the widget gallery and the pre-first-read state.
    static let placeholder = WidgetSnapshot(
        streakDays: 0, readToday: 0, dailyGoal: 3,
        nextDotName: nil, nextDotCluster: nil,
        conceptsLit: 0, conceptsTotal: 0, generatedAt: .now
    )
}
