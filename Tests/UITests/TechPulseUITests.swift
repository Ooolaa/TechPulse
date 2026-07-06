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
        sleep(3)                              // let the force layout settle
        snap(app, "5-knowledge-graph")

        app.buttons["Progress"].tap()
        sleep(1)
        snap(app, "6-progress-charts")
    }
}
