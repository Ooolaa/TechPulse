import Foundation

/// Runs `work` and reports the longest the main actor went unserved while it
/// did — alongside how long it took, which is the number these tests are *not*
/// about. The work still costs what it costs; the question is who waits.
///
/// The heartbeat is a task on the main actor that does nothing but yield.
/// Anything holding the main actor keeps it from being served, and the gap it
/// then records is what a reader would have seen as a frozen Feed.
///
/// Shared rather than owned by one suite: #42 asked this question of
/// de-duplication and #49 asks it again of the 🔥 lane, at a different seam on
/// the same screen. A second copy of the heartbeat would be a second thing to
/// keep honest.
@MainActor
func mainActorStall<T>(during work: () async -> T)
async -> (value: T, stall: TimeInterval, elapsed: TimeInterval) {
    let heartbeat = Task { @MainActor in
        var longest: TimeInterval = 0
        var last = Date.now
        while !Task.isCancelled {
            await Task.yield()
            longest = max(longest, Date.now.timeIntervalSince(last))
            last = .now
        }
        return longest
    }
    // The heartbeat takes its first beat before the work starts. Without this
    // it is only scheduled, and work that holds the main actor throughout —
    // exactly the failure being measured — would run to completion before the
    // heartbeat ever set its clock, and report no stall at all.
    await Task.yield()
    let started = Date.now
    let value = await work()
    let elapsed = Date.now.timeIntervalSince(started)
    heartbeat.cancel()
    return (value, await heartbeat.value, elapsed)
}
