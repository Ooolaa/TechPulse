import Testing
import Foundation
@testable import TechPulse

/// The cue that reaches the reader (#15). All of the arithmetic is here, taking
/// an injected `now` and calendar, so the only thing left in the system call is
/// the system call.
@MainActor
@Suite("Reading reminder")
struct ReadingReminderTests {

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                      in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return calendar.date(from: components)!
    }

    private let evening = ReadingIntention(routine: "after my evening coffee",
                                           hour: 21, minute: 0, isOn: true)

    // MARK: When the cue arrives

    @Test("the cue is today when today's time has not passed and nothing is read")
    func todayBeforeTheTime() {
        let calendar = calendar("Europe/London")
        let now = date(2026, 8, 20, 9, 0, in: calendar)
        let next = ReadingReminder.nextFire(for: evening, now: now, hasReadToday: false,
                                            calendar: calendar)
        #expect(next == date(2026, 8, 20, 21, 0, in: calendar))
    }

    @Test("a time that has already passed moves the cue to tomorrow")
    func afterTheTime() {
        let calendar = calendar("Europe/London")
        let now = date(2026, 8, 20, 22, 30, in: calendar)
        let next = ReadingReminder.nextFire(for: evening, now: now, hasReadToday: false,
                                            calendar: calendar)
        #expect(next == date(2026, 8, 21, 21, 0, in: calendar))
    }

    @Test("a day that has been read gets no cue, and the next one is tomorrow")
    func quietOnceRead() {
        let calendar = calendar("Europe/London")
        let now = date(2026, 8, 20, 9, 0, in: calendar)
        let next = ReadingReminder.nextFire(for: evening, now: now, hasReadToday: true,
                                            calendar: calendar)
        #expect(next == date(2026, 8, 21, 21, 0, in: calendar))
    }

    @Test("an intention turned off asks for nothing")
    func turnedOff() {
        let calendar = calendar("Europe/London")
        var off = evening
        off.isOn = false
        #expect(ReadingReminder.nextFire(for: off, now: date(2026, 8, 20, 9, 0, in: calendar),
                                         hasReadToday: false, calendar: calendar) == nil)
    }

    @Test("the cue keeps its wall-clock time across a daylight-saving change")
    func acrossDaylightSaving() throws {
        // Clocks go back on 1 November 2026 in New York. Adding 24 hours would
        // land the cue at 20:00; it has to stay at the hour the reader chose.
        let calendar = calendar("America/New_York")
        let now = date(2026, 10, 31, 22, 30, in: calendar)
        let next = ReadingReminder.nextFire(for: evening, now: now, hasReadToday: false,
                                            calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                 from: try #require(next))
        #expect(components.day == 1 && components.month == 11)
        #expect(components.hour == 21 && components.minute == 0)
    }

    @Test("moving time zone moves the cue with the reader")
    func acrossTimeZones() {
        // The same intention, read in Tokyo: 21:00 is 21:00 where the reader is.
        let tokyo = calendar("Asia/Tokyo")
        let now = date(2026, 8, 20, 9, 0, in: tokyo)
        let next = ReadingReminder.nextFire(for: evening, now: now, hasReadToday: false,
                                            calendar: tokyo)
        #expect(next == date(2026, 8, 20, 21, 0, in: tokyo))
    }

    @Test("the cue at midnight belongs to the day it is set for")
    func midnightIntention() {
        let calendar = calendar("Europe/London")
        var midnight = evening
        midnight.hour = 0; midnight.minute = 0
        let now = date(2026, 8, 20, 23, 30, in: calendar)
        let next = ReadingReminder.nextFire(for: midnight, now: now, hasReadToday: false,
                                            calendar: calendar)
        #expect(next == date(2026, 8, 21, 0, 0, in: calendar))
    }

    // MARK: Reaching a reader who is not opening the app

    @Test("the cue is armed for days ahead, not just the next one")
    func armsAWindowOfDays() {
        // A cue re-armed only when the app runs reaches a reader who is already
        // reading. The reader this feature exists for is the one who stopped
        // opening it, so the days ahead are scheduled now.
        let calendar = calendar("Europe/London")
        let now = date(2026, 8, 20, 9, 0, in: calendar)
        let fires = ReadingReminder.upcomingFires(for: evening, now: now, hasReadToday: false,
                                                  calendar: calendar)
        #expect(fires.count == ReadingReminder.daysArmed)
        #expect(fires.first == date(2026, 8, 20, 21, 0, in: calendar))
        #expect(fires.last == date(2026, 8, 20 + ReadingReminder.daysArmed - 1, 21, 0, in: calendar))
    }

    @Test("a day already read is not armed, and the days after it still are")
    func readDayIsSkippedButTheRestStand() {
        let calendar = calendar("Europe/London")
        let now = date(2026, 8, 20, 9, 0, in: calendar)
        let fires = ReadingReminder.upcomingFires(for: evening, now: now, hasReadToday: true,
                                                  calendar: calendar)
        #expect(fires.first == date(2026, 8, 21, 21, 0, in: calendar))
        #expect(fires.count == ReadingReminder.daysArmed)
    }

    @Test("an intention turned off arms nothing")
    func offArmsNothing() {
        var off = evening
        off.isOn = false
        #expect(ReadingReminder.upcomingFires(for: off, now: date(2026, 8, 20, 9, 0,
                                                                  in: calendar("Europe/London")),
                                              hasReadToday: false,
                                              calendar: calendar("Europe/London")).isEmpty)
    }

    @Test("a midnight intention on a read day is tomorrow, not the day after")
    func midnightOnAReadDay() {
        // `startOfDay` plus an exclusive search is how a 00:00 cue loses a day.
        let calendar = calendar("Europe/London")
        let now = date(2026, 8, 20, 9, 0, in: calendar)
        var midnight = evening
        midnight.hour = 0; midnight.minute = 0
        let next = ReadingReminder.nextFire(for: midnight, now: now, hasReadToday: true,
                                            calendar: calendar)
        #expect(next == date(2026, 8, 21, 0, 0, in: calendar))
    }

    // MARK: What it says

    @Test("the cue names the routine back, in the second person")
    func copyNamesTheRoutine() {
        // The reader wrote "after my evening coffee" about themselves; the cue
        // is addressed to them, so it says "your".
        let copy = ReadingReminder.copy(for: evening, waiting: 3, streakDays: 0)
        #expect(copy.title == "After your evening coffee")
        #expect(copy.body.contains("3"))
    }

    @Test("a live streak is what the cue leads with, because that is what is at stake")
    func copyLeadsWithTheStreak() {
        let copy = ReadingReminder.copy(for: evening, waiting: 3, streakDays: 12)
        #expect(copy.body.contains("12-day streak"))
    }

    @Test("an intention with no routine still has something to say")
    func copyWithoutARoutine() {
        var bare = evening
        bare.routine = nil
        let copy = ReadingReminder.copy(for: bare, waiting: 3, streakDays: 0)
        #expect(!copy.title.isEmpty)
        #expect(!copy.body.isEmpty)
    }

    @Test("a routine that merely contains “my” keeps its own words")
    func copyDoesNotRewriteInsideWords() {
        // "my" is a word here, not a substring to hunt: "tummy time" is not
        // "tuyour time".
        var odd = evening
        odd.routine = "after my tummy time"
        #expect(ReadingReminder.copy(for: odd, waiting: 1, streakDays: 0).title
                == "After your tummy time")
    }

    @Test("a routine the reader started and did not finish is not a routine")
    func copyWithABlankRoutine() {
        // "Something else…" sets the routine to empty and reveals the field. A
        // reader who taps it and continues without typing must not be sent a
        // notification with no title.
        for blank in ["", "   ", "\n"] {
            var unfinished = evening
            unfinished.routine = blank
            let copy = ReadingReminder.copy(for: unfinished, waiting: 3, streakDays: 0)
            #expect(copy.title == "Time to read", "a blank routine rendered as “\(copy.title)”")
        }
    }

    @Test("the cue never counts what is not there, and never scolds")
    func copyIsNeverGuiltInducing() {
        // Nothing waiting is not a reason to say "you have read nothing".
        let copy = ReadingReminder.copy(for: evening, waiting: 0, streakDays: 0)
        #expect(!copy.body.isEmpty)
        for word in ["missed", "failed", "lost", "haven't", "0 "] {
            #expect(!copy.body.localizedCaseInsensitiveContains(word),
                    "the cue said “\(word)” — it is a nudge, not a report card")
        }
    }
}
