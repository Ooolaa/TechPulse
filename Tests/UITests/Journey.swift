import XCTest

/// Drives one UI journey and keeps its books (#30).
///
/// Two rules, both paid for by #26. **Every step is declared up front** and has
/// to produce its screenshot: before this, a step wrapped in
/// `if element.exists { … }` skipped itself and left the journey green, which
/// is how `4-marked-known.png` went four days stale without anyone noticing.
/// A step allowed not to run says why, in words, at the declaration — and says
/// so out loud when it doesn't.
///
/// And **every wait names the condition it is waiting for**. The 47 `sleep()`
/// calls this replaces were guesses: too long on an idle machine, too short on
/// a loaded one, and silent about which.
@MainActor
final class Journey {

    /// Where the journey's evidence lands. Also in `README.md`.
    static let shotDirectory = "/tmp/techpulse_uitest"

    /// The wipe every journey launches with — `UITestLaunch` holds the app's
    /// spelling of it, and a unit test holds the app to it.
    static let resetStoreArgument = UITestLaunch.resetStore

    let app = XCUIApplication()

    private let title: String
    private var ledger: JourneyLedger
    private let evidence: ScreenshotEvidence

    /// Declares the journey. Every launch wipes the store, so a step's
    /// preconditions are a property of the code rather than of what the last
    /// run happened to leave behind (#26).
    init(_ title: String, steps: [JourneyStep], launchArguments: [String] = []) {
        self.title = title
        self.ledger = JourneyLedger(steps)
        self.evidence = ScreenshotEvidence(directory: Self.shotDirectory, runStarted: .now)
        app.launchArguments += [Self.resetStoreArgument] + launchArguments

        // Clear this journey's own screenshots, so what is on disk afterwards is
        // this run and nothing else. The freshness check below is the belt to
        // this pair of braces: it catches a step whose write silently failed
        // over an older file.
        for step in steps {
            try? FileManager.default.removeItem(atPath: "\(Self.shotDirectory)/\(step.name).png")
        }
    }

    func start() {
        app.launch()
    }

    // MARK: - Evidence

    /// Records that a step ran and writes the screenshot that proves it.
    func snap(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        ledger.record(name)
        if let problem = evidence.write(app.screenshot().pngRepresentation, named: name) {
            XCTFail("\(title): \(problem)", file: file, line: line)
        }
    }

    /// Reports what the journey did against what it said it would. Call last.
    func finish(file: StaticString = #filePath, line: UInt = #line) {
        if let report = ledger.skipReport {
            // Visible in the log and in the result bundle's activity list — the
            // point being that a step which did not run is never silent.
            XCTContext.runActivity(named: "⚠️ \(title) — \(report)") { _ in }
            print("⚠️ \(title): \(report)")
        }
        for name in Set(ledger.ran).sorted() {
            if let problem = evidence.problem(with: name) {
                XCTFail("\(title): \(problem)", file: file, line: line)
            }
        }
        if let failure = ledger.failureReport {
            XCTFail("\(title): \(failure)", file: file, line: line)
        }
    }

    // MARK: - Waits that name what they are waiting for

    /// Waits for an element to exist, failing with what was expected.
    @discardableResult
    func waitFor(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10,
                 file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(title): \(what) (waited \(Int(timeout))s)", file: file, line: line)
        return element
    }

    /// Waits for an element to go away — a sheet dismissing, a picker closing.
    /// Polled rather than `waitForNonExistence`, whose granularity is a second
    /// and which therefore charges one for every dismissal in the suite.
    func waitUntilGone(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10,
                       file: StaticString = #filePath, line: UInt = #line) {
        waitUntil(what, timeout: timeout, file: file, line: line) { !element.exists }
    }

    /// What a control says, or nil if it is not there — read in **one** query.
    ///
    /// `exists` and `label` are two separate queries against a live app, and a
    /// control that goes between them makes the second one throw rather than
    /// answer: `Failed to get matching snapshot: No matches found…`, which is a
    /// thrown query rather than a failed assertion, so it reads as a broken
    /// journey rather than a false one. The find-articles button does exactly
    /// that — it is removed the moment its Concept reaches three Articles,
    /// which is what the search that step just triggered is trying to make
    /// happen — and `testCoreJourney` failed about one run in two on it (#48).
    ///
    /// One snapshot, so "not there" is a value the caller can branch on.
    /// `static` because reading a label needs nothing a journey holds; it is
    /// here so it sits with the other ways this file reads a live app.
    ///
    /// Nil still means gone, exactly as `!exists` did — this narrows *when* the
    /// question is asked, not what the answer means.
    static func label(of element: XCUIElement) -> String? {
        (try? element.snapshot())?.label
    }

    /// Waits for anything else worth waiting for. `what` is the condition in
    /// words, and it is what the failure says.
    ///
    /// Polls rather than using `XCTNSPredicateExpectation`: the predicate block
    /// is `@Sendable`, and every condition here closes over an `XCUIElement`,
    /// which is not.
    @discardableResult
    func waitUntil(_ what: String, timeout: TimeInterval = 10,
                   file: StaticString = #filePath, line: UInt = #line,
                   _ condition: () -> Bool) -> Bool {
        let met = poll(condition, until: timeout)
        XCTAssertTrue(met, "\(title): \(what) (waited \(Int(timeout))s)", file: file, line: line)
        return met
    }

    /// The same wait, but never becoming true is an answer rather than a
    /// failure — for the steps a journey has declared it may legitimately skip.
    func becomesTrue(_ condition: () -> Bool, within timeout: TimeInterval = 2) -> Bool {
        poll(condition, until: timeout)
    }

    private func poll(_ condition: () -> Bool, until timeout: TimeInterval,
                      every interval: TimeInterval = 0.2) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date.now.addingTimeInterval(interval))
        } while Date.now < deadline
        return condition()
    }

    /// Taps a control, having waited for it to be there.
    ///
    /// Hittability is worth waiting for — a control under a presenting sheet
    /// exists and swallows the tap, which is the shape of #26 — but not worth
    /// failing on: a row below the fold is not hittable until XCUITest scrolls
    /// it into view, which is something `tap()` itself does.
    func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10,
             file: StaticString = #filePath, line: UInt = #line) {
        let there = waitUntil("\(what) never appeared to tap", timeout: timeout,
                              file: file, line: line) { element.exists }
        guard there else { return }
        _ = becomesTrue({ element.exists && element.isHittable })
        // Between the wait and the tap the screen can move on — a sheet that
        // re-renders takes its buttons with it — and tapping something that has
        // gone raises rather than failing. Say which control went instead.
        guard element.exists else {
            XCTFail("\(title): \(what) disappeared between waiting for it and tapping it",
                    file: file, line: line)
            return
        }
        element.tap()
    }

    /// Waits for the screen to stop moving — the honest form of "let the
    /// animation finish". Returns as soon as two consecutive frames match
    /// instead of spending a fixed guess, and says so when something never
    /// settles rather than pretending it waited long enough.
    ///
    /// `timeout` is a budget, not a promise: a force layout over 141 dots is
    /// still drifting slightly long after the screenshot is legible, and
    /// waiting for the last pixel costs more than it proves.
    func settle(_ what: String, timeout: TimeInterval = 4) {
        var previous: Data?
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            let frame = app.screenshot().pngRepresentation
            if frame == previous { return }
            previous = frame
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.15))
        }
        let notice = "⏳ \(title): \(what) was still moving after \(Int(timeout))s — carrying on"
        XCTContext.runActivity(named: notice) { _ in }
        print(notice)
    }

    /// Swipes until something is on screen, then says so if it never was.
    func scroll(to element: XCUIElement, _ what: String, swipes: Int = 10,
                file: StaticString = #filePath, line: UInt = #line) {
        var used = 0
        while !element.exists, used < swipes {
            app.swipeUp()
            used += 1
        }
        XCTAssertTrue(element.exists, "\(title): \(what) (after \(used) swipes)",
                      file: file, line: line)
    }

    /// Back out of a pushed page, waiting for the page it returns to.
    func goBack(to expected: XCUIElement, _ what: String,
                file: StaticString = #filePath, line: UInt = #line) {
        tap(app.navigationBars.buttons.firstMatch, "back button", file: file, line: line)
        waitFor(expected, what, file: file, line: line)
    }
}
