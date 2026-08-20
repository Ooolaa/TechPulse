import Foundation

/// The reader's own stated plan for when reading happens — a time, and the
/// existing routine it follows.
///
/// Kept in `UserDefaults` rather than the store: it is one small preference the
/// reader states, not part of the map, and the launch path that schedules from
/// it runs before any view has a `ModelContext` to read.
///
/// The routine is what makes this an *intention* rather than an alarm. Atomic
/// Habits' point is that a new habit sticks to an existing one, so the reminder names
/// the thing the reader already does: "after your evening coffee".
struct ReadingIntention: Codable, Equatable {
    /// The reader's own words for the routine, or nil when they gave none. The
    /// suggestions are a starting point, not a closed list — a reader whose
    /// routine is "after the school run" says so.
    var routine: String?
    var hour: Int
    var minute: Int
    /// Off is a state the reader chose, distinct from never having said. Both
    /// schedule nothing; only one of them is worth asking about again.
    var isOn: Bool

    /// The routine as something to say back, or nil when there is nothing to
    /// say. "Something else…" sets the routine empty and reveals the field, so
    /// a reader who taps it and moves on leaves whitespace behind — which is a
    /// started sentence, not a routine.
    var statedRoutine: String? {
        guard let routine, !routine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return routine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The routine as the reminder says it back: the reader's own words, addressed
    /// to them and capitalised to open a line. `my` is matched as a word, so
    /// "after my tummy time" does not become "after your tuyour time".
    var displayRoutine: String? {
        guard let stated = statedRoutine else { return nil }
        let addressed = stated.replacingOccurrences(of: "\\bmy\\b", with: "your",
                                                    options: .regularExpression)
        return addressed.prefix(1).uppercased() + addressed.dropFirst()
    }

    /// The routines offered at onboarding, in the order they occur in a day.
    static let suggestedRoutines = [
        "after my morning coffee",
        "over lunch",
        "after dinner",
        "before bed",
    ]

    /// 21:00, following dinner — late enough to have happened, early enough not
    /// to compete with sleep. A default the reader is shown and can change, not
    /// one applied behind them.
    static let unset = ReadingIntention(routine: nil, hour: 21, minute: 0, isOn: false)
}
