import XCTest

/// How the journeys read a live app.
///
/// `Journey.label(of:)` exists because `exists` then `label` is two queries,
/// and a control that goes between them makes the second one throw rather than
/// answer — a thrown query, which reads as a broken journey rather than a
/// failing one. `testCoreJourney` lost that race about one run in two (#48).
@MainActor
final class JourneyReadTests: XCTestCase {

    /// The half that used to throw. Measured against a query that matches
    /// nothing, which is the state a vanished control leaves behind: this is
    /// the read the journey performs, at the moment it performs it.
    func testLabelOfSomethingNotThereIsNilRatherThanAThrownQuery() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunch.resetStore]
        app.launch()

        let gone = app.buttons["noSuchControlInThisApp"].firstMatch
        XCTAssertFalse(gone.exists, "the fixture must name a control the app does not have")
        // Reading `gone.label` here is what fails the suite with
        // “Failed to get matching snapshot: No matches found…”.
        XCTAssertNil(Journey.label(of: gone))
    }

    /// And the other half, so the helper cannot pass the test above by being
    /// nil for everything — which would make every wait built on it return
    /// true immediately and every journey silently green.
    func testLabelOfSomethingPresentIsWhatItSays() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunch.resetStore]
        app.launch()

        let onboarding = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(onboarding.waitForExistence(timeout: 30),
                      "a wiped store opens on onboarding")
        let says = Journey.label(of: onboarding)
        XCTAssertNotNil(says)
        XCTAssertFalse(says?.isEmpty ?? true, "a button that is there says something")
    }
}
