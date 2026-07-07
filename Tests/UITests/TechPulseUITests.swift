import XCTest

/// Drives the core user journey and saves a screenshot at each step:
/// feed → article → concept sheet → "I know this" → knowledge graph → progress.
final class TechPulseUITests: XCTestCase {

    private let shotDir = "/tmp/techpulse_uitest"

    private func snap(_ app: XCUIApplication, _ name: String) {
        let png = app.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(shotDir)/\(name).png", contents: png)
    }

    func testCoreJourney() throws {
        let app = XCUIApplication()
        app.launch()

        // First run shows onboarding (design 3a): topics preselected, continue.
        let continueButton = app.buttons["onboardingContinue"].firstMatch
        if continueButton.waitForExistence(timeout: 5) {
            snap(app, "0-onboarding")
            XCTAssertTrue(continueButton.isEnabled, "Continue disabled despite preselected topics")
            continueButton.tap()
            sleep(1)
        }

        // Allow first sync + on-device analysis to finish.
        let firstCard = app.buttons["articleCard"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 60), "feed never loaded articles")
        sleep(10)
        snap(app, "1-feed")

        firstCard.tap()
        sleep(2)
        snap(app, "2-article")

        // Concept chips exist when analysis found concepts in this article.
        let chip = app.buttons["conceptChip"].firstMatch
        if chip.waitForExistence(timeout: 5) {
            chip.tap()
            sleep(1)
            snap(app, "3-concept-sheet")
            let know = app.buttons["knowButton"].firstMatch
            if know.exists, know.isEnabled {
                know.tap()
                sleep(1)
                snap(app, "4-marked-known")
            }
            app.swipeDown(velocity: .fast)   // dismiss sheet
            sleep(1)
        }

        app.buttons["Knowledge"].tap()
        sleep(1)
        snap(app, "5-cluster-overview")

        // Drill into the first cluster's dependency graph (design 4b).
        let clusterCard = app.buttons["clusterCard"].firstMatch
        XCTAssertTrue(clusterCard.waitForExistence(timeout: 5), "no cluster cards")
        clusterCard.tap()
        sleep(3)                              // let the force layout settle
        snap(app, "5b-cluster-detail")
        app.navigationBars.buttons.firstMatch.tap()   // back
        sleep(1)

        app.buttons["Progress"].tap()
        sleep(1)
        snap(app, "6-progress-charts")

        // Weekly quiz: answer every question (any option), reach the result.
        let start = app.buttons["startQuiz"].firstMatch
        if start.waitForExistence(timeout: 3), start.isEnabled {
            start.tap()
            let action = app.buttons["quizAction"].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 30), "quiz never generated")
            snap(app, "7-quiz-question")
            var safety = 0
            while action.exists, safety < 20 {
                let option = app.buttons["quizOption"].firstMatch
                if option.exists { option.tap() }
                action.tap()      // check answer
                if action.exists { action.tap() }   // next / see results
                safety += 1
            }
            let done = app.buttons["quizDone"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 5), "quiz result never shown")
            snap(app, "8-quiz-result")
            done.tap()
        }
    }

    /// Usability guards: every tab reachable, primary controls hittable.
    func testTabsAndTargets() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasOnboarded", "YES"]   // onboarding covered by core journey
        app.launch()
        for tab in ["Feed", "Knowledge", "Progress", "Settings"] {
            let button = app.buttons[tab].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(tab) tab missing")
            XCTAssertTrue(button.isHittable, "\(tab) tab not hittable")
            button.tap()
        }
        // Settings must expose at least one source toggle, and the sync row
        // after scrolling past the sources list.
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5), "no feed source toggles")
        let syncRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Sync now'")).firstMatch
        var scrolls = 0
        while !syncRow.exists, scrolls < 4 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(syncRow.waitForExistence(timeout: 3), "Sync now row missing")
    }
}
