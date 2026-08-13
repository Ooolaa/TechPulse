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

        // 🔥 Hot-topics filter: toggling must show a (possibly empty) filtered
        // list and toggle back cleanly.
        let hotChip = app.buttons["hotChip"].firstMatch
        if hotChip.exists {
            hotChip.tap()
            sleep(1)
            snap(app, "1b-hot-topics-filter")
            hotChip.tap()
            sleep(1)
        }

        firstCard.tap()
        sleep(2)
        snap(app, "2-article")

        // Concept chips exist when analysis found concepts in this article.
        let chip = app.buttons["conceptChip"].firstMatch
        if chip.waitForExistence(timeout: 5) {
            chip.tap()
            sleep(1)
            snap(app, "3-concept-sheet")

            // Drill-through: related concept → sibling page → back;
            // article row → full article → back. Both must be tappable.
            let related = app.buttons["relatedConceptChip"].firstMatch
            if related.exists {
                related.tap()
                sleep(1)
                snap(app, "3b-related-concept-jump")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
            let articleRow = app.buttons["conceptArticleRow"].firstMatch
            if articleRow.exists {
                articleRow.tap()
                sleep(1)
                snap(app, "3c-article-from-sheet")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }

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

        // Deterministic concept-sheet entry: the frontier card always exists
        // while the cluster has unlit pack concepts. Verify sheet drill-through
        // (article row → ArticleView, related chip → sibling concept).
        let frontier = app.buttons["frontierCard"].firstMatch
        if frontier.exists {
            frontier.tap()
            sleep(1)
            snap(app, "5b2-concept-sheet")

            // Topic search: a frontier concept usually has no articles yet —
            // pull fresh arXiv matches, which should populate the row list.
            let find = app.buttons["findArticles"].firstMatch
            if find.exists {
                find.tap()
                sleep(6)
                snap(app, "5b2b-topic-search")
            }

            let row = app.buttons["conceptArticleRow"].firstMatch
            if row.exists {
                row.tap()
                sleep(1)
                snap(app, "5b3-article-from-sheet")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
            let related = app.buttons["relatedConceptChip"].firstMatch
            if related.exists {
                related.tap()
                sleep(1)
                snap(app, "5b4-related-concept-jump")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
            app.buttons["closeSheet"].tap()
            sleep(1)
        }

        app.navigationBars.buttons.firstMatch.tap()   // back
        sleep(1)

        // Full map: every concept in one net, no sections.
        let fullMap = app.buttons["fullMapCard"].firstMatch
        XCTAssertTrue(fullMap.waitForExistence(timeout: 5), "full map card missing")
        fullMap.tap()
        sleep(3)
        snap(app, "5c-full-map")

        // Three kinds of connection have to be told apart on the map, and the
        // only way to know they are is to look at both themes. The strokes are
        // drawn in a Canvas over Theme.card, which is exactly the combination
        // that shipped a dark-mode readability bug on Settings once.
        for key in ["Learn first", "Related", "Read together"] {
            XCTAssertTrue(app.staticTexts[key].firstMatch.waitForExistence(timeout: 5),
                          "map legend has no key for “\(key)” — the edge kinds are unexplained")
        }
        XCUIDevice.shared.appearance = .light
        sleep(2)
        snap(app, "5c1-full-map-light")
        XCUIDevice.shared.appearance = .dark
        sleep(2)
        snap(app, "5c2-full-map-dark")

        // Zoomed in, where a dash and an arrowhead are actually resolvable: at
        // overview scale a 141-dot map is dense enough that any line looks like
        // any other, so the screenshot gate would prove nothing about whether
        // the three kinds are told apart.
        app.otherElements["knowledgeGraph"].firstMatch.pinch(withScale: 3, velocity: 1)
        sleep(2)
        snap(app, "5c3-full-map-dark-zoomed")
        XCUIDevice.shared.appearance = .light
        sleep(2)
        snap(app, "5c4-full-map-light-zoomed")

        app.navigationBars.buttons.firstMatch.tap()
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

        // Settings: the large title and the section footers must both be
        // legible — this screen shipped a dark-mode readability bug once
        // precisely because the journey never captured it.
        app.buttons["Settings"].tap()
        sleep(1)
        snap(app, "9-settings")
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        snap(app, "9b-settings-footers")
    }

    /// Choosing what the map covers: see the active Pack, switch to the other
    /// built-in one, take up its suggested Sources, and switch back.
    ///
    /// Runs after the core journey, so the app already has a map; it ends on
    /// the Pack it started on so it leaves nothing behind for the next test.
    func testPackSelectionJourney() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasOnboarded", "YES"]
        app.launch()

        app.buttons["Settings"].tap()
        let packRow = app.buttons["packRow"].firstMatch
        XCTAssertTrue(packRow.waitForExistence(timeout: 10), "Settings has no Pack row")
        snap(app, "10-settings-pack-row")
        packRow.tap()
        sleep(1)
        snap(app, "10a-pack-library")

        // Both built-in Packs are on offer, and one of them is marked active.
        let builtins = app.buttons.matching(identifier: "builtinPack")
        XCTAssertTrue(builtins.element(boundBy: 0).waitForExistence(timeout: 5),
                      "no built-in packs listed")
        XCTAssertGreaterThan(builtins.count, 1, "only one built-in pack to choose from")
        XCTAssertTrue(app.staticTexts["AI Engineering"].firstMatch.exists,
                      "the active Pack is not named")

        // Importing: the entry point opens the system file picker. What a bad
        // file does is covered by unit tests; this only proves the door opens.
        app.buttons["importPack"].firstMatch.tap()
        sleep(2)
        snap(app, "10b-import-picker")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 3) {
            cancel.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        sleep(1)

        // Switch to the other built-in Pack: its suggested Sources are offered.
        // The offer is only ever the Sources the reader has not got, so on a
        // simulator that ran this journey before there is nothing left to
        // offer — the end state is asserted below either way.
        builtins.element(boundBy: 1).tap()
        sleep(2)
        let accept = app.buttons["acceptSources"].firstMatch
        if accept.waitForExistence(timeout: 5) {
            snap(app, "10c-source-offer")
            accept.tap()
            sleep(2)
        }

        // The map is now the other Pack's.
        XCTAssertTrue(app.staticTexts["Security Engineering"].firstMatch
            .waitForExistence(timeout: 5), "the Pack did not switch")
        snap(app, "10d-pack-switched")

        app.navigationBars.buttons.firstMatch.tap()   // back to Settings
        sleep(1)
        app.buttons["Knowledge"].tap()
        sleep(2)
        snap(app, "10e-knowledge-after-switch")

        // Switch back, so the flagship Pack is what the next launch opens on.
        app.buttons["Settings"].tap()
        packRow.tap()
        sleep(1)
        app.buttons.matching(identifier: "builtinPack").element(boundBy: 0).tap()
        sleep(2)
        if app.buttons["declineSources"].firstMatch.exists {
            app.buttons["declineSources"].firstMatch.tap()
            sleep(1)
        }
        XCTAssertTrue(app.staticTexts["AI Engineering"].firstMatch
            .waitForExistence(timeout: 5), "switching back did not restore the flagship Pack")
        snap(app, "10f-pack-switched-back")

        // The Security Pack's suggestions are now the reader's own Sources,
        // and they survived switching back — a Source is chosen, not owned by
        // the Pack that suggested it.
        app.navigationBars.buttons.firstMatch.tap()   // back to Settings
        sleep(1)
        let fromPack = app.staticTexts["Krebs on Security"].firstMatch
        var scrolls = 0
        while !fromPack.exists, scrolls < 10 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(fromPack.exists, "the Pack's suggested Sources never reached Settings")
        snap(app, "10g-sources-from-pack")
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
