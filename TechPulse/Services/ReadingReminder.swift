import Foundation

/// When the reminder arrives and what it says. Every decision is here, taking an
/// injected `now` and `Calendar`, so the notification call itself carries
/// nothing worth testing (#15).
@MainActor
enum ReadingReminder {

    /// The next moment the reminder should reach the reader, or nil when it should
    /// not — the intention is off, or was never stated.
    ///
    /// Matched on wall-clock components rather than by adding a day's worth of
    /// seconds: 21:00 is 21:00 wherever the reader is and whatever the clocks
    /// did overnight. Adding 86,400 seconds would deliver the reminder an hour early
    /// for a fortnight after a daylight-saving change.
    static func nextFire(for intention: ReadingIntention, now: Date, hasReadToday: Bool,
                         calendar: Calendar = .current) -> Date? {
        guard intention.isOn else { return nil }

        var components = DateComponents()
        components.hour = intention.hour
        components.minute = intention.minute

        // A day the reader has already read is a day the reminder has nothing to ask
        // for, so it starts looking from tomorrow — the run is alive and being
        // told to keep it alive would be noise. A second before midnight rather
        // than midnight itself: `nextDate(after:)` is exclusive, and a reminder set
        // for 00:00 would otherwise skip the day it belongs to.
        let searchFrom: Date
        if hasReadToday {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            searchFrom = tomorrow.map { $0.addingTimeInterval(-1) } ?? now
        } else {
            searchFrom = now
        }
        return calendar.nextDate(after: searchFrom, matching: components,
                                 matchingPolicy: .nextTime)
    }

    /// How many days are armed at once.
    ///
    /// One request per day rather than a repeating trigger, because a repeating
    /// one cannot be quiet on a day the reader has already read — and a single
    /// non-repeating one reaches only a reader who opens the app, which is not
    /// the reader this exists for. A week is the bound: the system caps pending
    /// requests, and a reader who has not opened the app in seven days is owed a
    /// different conversation than another notification.
    static let daysArmed = 7

    /// Every moment to arm now, soonest first. Empty when the intention is off.
    static func upcomingFires(for intention: ReadingIntention, now: Date, hasReadToday: Bool,
                              calendar: Calendar = .current) -> [Date] {
        guard var fire = nextFire(for: intention, now: now, hasReadToday: hasReadToday,
                                  calendar: calendar) else { return [] }
        var fires = [fire]
        var components = DateComponents()
        components.hour = intention.hour
        components.minute = intention.minute
        while fires.count < daysArmed {
            guard let next = calendar.nextDate(after: fire, matching: components,
                                               matchingPolicy: .nextTime) else { break }
            fires.append(next)
            fire = next
        }
        return fires
    }

    /// What the reminder says, given what is waiting and what is at stake.
    ///
    /// It names the routine because that is the whole point of having asked for
    /// one: the reminder attaches to something the reader already does. It never
    /// reports what they did not do — a nudge that opens with a failure is one
    /// the reader turns off, and then there is no cue at all.
    static func copy(for intention: ReadingIntention, waiting: Int,
                     streakDays: Int) -> (title: String, body: String) {
        let title = intention.displayRoutine ?? "Time to read"

        // A live run is the thing the reader would mind losing, so it leads.
        if streakDays > 0 {
            return (title, "Read one article to keep your \(streakDays)-day streak.")
        }
        if waiting > 0 {
            return (title, "\(waiting) article\(waiting == 1 ? "" : "s") waiting whenever you are.")
        }
        return (title, "A few minutes with your map, whenever you are ready.")
    }
}
