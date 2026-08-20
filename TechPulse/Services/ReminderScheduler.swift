import Foundation
import UserNotifications

/// Where the Reading Intention is kept, and the one call that hands a reminder to
/// the system.
///
/// Deliberately thin: every decision — when the reminder fires, what it says,
/// whether it fires at all — is `ReadingReminder`, which is pure and tested.
/// What is left here is `UserDefaults` and `UNUserNotificationCenter`, neither
/// of which is worth a test of ours (#15).
///
/// Nothing here reaches the network. A local notification is scheduled on the
/// device by the device; `Egress` is unchanged by this feature.
@MainActor
enum ReminderScheduler {

    nonisolated private static let intentionKey = "readingIntention"
    private static let requestPrefix = "com.johnchen.TechPulse.readingCue"

    private static var requestIdentifiers: [String] {
        (0..<ReadingReminder.daysArmed).map { "\(requestPrefix).\($0)" }
    }

    /// Keys a store wipe has to clear as well, so a wiped app is a fresh
    /// install everywhere and not only in the store (#38).
    nonisolated static let defaultsKeys = [intentionKey]

    static var intention: ReadingIntention {
        get {
            guard let data = UserDefaults.standard.data(forKey: intentionKey),
                  let stored = try? JSONDecoder().decode(ReadingIntention.self, from: data)
            else { return .unset }
            return stored
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: intentionKey)
        }
    }

    /// Asks for permission, in the moment the reader states an intention rather
    /// than at launch — the one point where what the app wants it for is on
    /// screen. A refusal is an answer: the intention is still theirs to keep,
    /// and everything else in the app is untouched by it.
    ///
    /// The system asks once. A later call after a refusal returns false without
    /// showing anything, which is why the caller has to be able to say so
    /// rather than leave a switch on with nothing behind it.
    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func permissionGranted() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .authorized
    }

    /// True when the reader has refused, as opposed to not having been asked —
    /// the case where the only way back is the system's own Settings.
    static func permissionRefused() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .denied
    }

    /// Replaces the pending reminders with the next ones. Called after a read, after a
    /// sync, and whenever the intention changes — the schedule is one request,
    /// so re-scheduling is how it stays true rather than something to reconcile.
    static func reschedule(waiting: Int, streakDays: Int, hasReadToday: Bool,
                           now: Date = .now, calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: requestIdentifiers)

        let intention = self.intention
        let fires = ReadingReminder.upcomingFires(for: intention, now: now,
                                                  hasReadToday: hasReadToday, calendar: calendar)
        guard !fires.isEmpty, await permissionGranted() else { return }

        // Today's numbers are today's. A reminder days out says the thing
        // that is true whenever it arrives, rather than quoting a stale count.
        let today = ReadingReminder.copy(for: intention, waiting: waiting, streakDays: streakDays)
        let later = ReadingReminder.copy(for: intention, waiting: 0, streakDays: 0)

        for (index, fire) in fires.enumerated() {
            let words = index == 0 ? today : later
            let content = UNMutableNotificationContent()
            content.title = words.title
            content.body = words.body

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                     from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: requestIdentifiers[index],
                                                        content: content, trigger: trigger))
        }
    }

    /// Nothing pending, for an intention turned off.
    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
    }
}
