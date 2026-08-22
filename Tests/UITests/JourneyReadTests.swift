import XCTest

/// How the journeys read a live app.
///
/// `exists` then `label` is two queries, and a control that goes between them
/// makes the second one throw rather than answer — a thrown query, which reads
/// as a broken journey rather than a failing one. `testCoreJourney` lost that
/// race about one run in two (#48).
///
/// #48 closed the three sites that were losing it. #53 moved the seam: a
/// condition is now *handed* one reading of a control, so there is no second
/// query for the next wait anyone writes to lose. These tests hold both halves
/// of that — the read, and the wait built on it.
@MainActor
final class JourneyReadTests: XCTestCase {

    /// A wiped launch with no `Journey` around it. The two tests below are
    /// about the read itself, which is `static` precisely because it needs
    /// nothing a journey holds — the two after them are about the wait, and
    /// build a journey because that is what they are testing.
    private func launchedOnAWipedStore() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunch.resetStore]
        app.launch()
        return app
    }

    /// The half that used to throw. Measured against a query that matches
    /// nothing, which is the state a vanished control leaves behind: this is
    /// the read the journey performs, at the moment it performs it.
    func testStateOfSomethingNotThereIsNilRatherThanAThrownQuery() {
        let app = launchedOnAWipedStore()

        let gone = app.buttons["noSuchControlInThisApp"].firstMatch
        XCTAssertFalse(gone.exists, "the fixture must name a control the app does not have")
        // Reading `gone.label` here is what fails the suite with
        // “Failed to get matching snapshot: No matches found…”.
        XCTAssertNil(Journey.state(of: gone))
    }

    /// And the other half, so the read cannot pass the test above by being nil
    /// for everything — which would make every wait built on it return true
    /// immediately and every journey silently green.
    ///
    /// Both attributes come out of the one snapshot, which is the property
    /// worth having: a caller asking what a control says *and* whether it is
    /// still on gets one app, not two.
    func testStateOfSomethingPresentIsWhatItSaysAndWhetherItIsOn() {
        let app = launchedOnAWipedStore()

        let onboarding = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(onboarding.waitForExistence(timeout: 30),
                      "a wiped store opens on onboarding")
        let state = Journey.state(of: onboarding)
        XCTAssertNotNil(state)
        XCTAssertFalse(state?.label.isEmpty ?? true, "a button that is there says something")
        XCTAssertEqual(state?.isEnabled, true, "Continue is offered with topics preselected")
    }

    /// The seam itself: a wait is handed the state, and a control that has gone
    /// arrives as `nil` rather than as a thrown query. Nil still means gone,
    /// exactly as `!exists` did.
    func testAWaitIsHandedNilForAControlThatHasGone() {
        let journey = Journey("journey reads", steps: [])
        journey.start()

        let gone = journey.app.buttons["noSuchControlInThisApp"].firstMatch
        var seen: [ElementState?] = []
        journey.waitUntil(gone, "the condition was never handed anything") { state in
            seen.append(state)
            return true
        }

        XCTAssertEqual(seen.count, 1, "the condition should be asked once and answered")
        XCTAssertNil(seen.first ?? nil, "a control that is not there is nil, not a thrown query")
        journey.finish()
    }

    /// And a wait on a control that is there is handed its attributes, so a
    /// condition can branch on what it says without going back to the app.
    func testAWaitIsHandedTheAttributesOfAControlThatIsThere() {
        let journey = Journey("journey reads", steps: [])
        journey.start()

        let onboarding = journey.app.buttons["onboardingContinue"].firstMatch
        var seen: ElementState?
        journey.waitUntil(onboarding, "onboarding never appeared on a wiped store", timeout: 30) { state in
            seen = state
            return state != nil
        }

        XCTAssertEqual(seen?.isEnabled, true)
        XCTAssertFalse(seen?.label.isEmpty ?? true)
        journey.finish()
    }
}
