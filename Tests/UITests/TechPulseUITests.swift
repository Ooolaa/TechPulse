import XCTest

/// The UI journeys. Each one declares its steps to a `Journey`, which fails the
/// test if a declared step never ran (#30).
///
/// Before that, most steps here were wrapped in `if element.exists { … }`: a
/// step whose element was missing did nothing and left the journey green. Four
/// of them had stopped running — `3-concept-sheet`, `3b`, `3c` and
/// `4-marked-known` were between one and five days stale while the suite passed
/// every time. The few steps still allowed not to run say why in their
/// declaration, and say so out loud in the run when they don't.
@MainActor
final class TechPulseUITests: XCTestCase {

    // MARK: - Core journey

    /// Feed → article → concept sheet → "I know this" → knowledge graph →
    /// progress, with a screenshot proving each step.
    func testCoreJourney() throws {
        let journey = Journey("core journey", steps: [
            .required("0-onboarding"),
            .required("0b-reading-intention"),
            .required("1-feed"),
            .required("1b-hot-topics-filter"),
            .required("2-article"),
            .required("3-concept-sheet"),
            .required("3b-related-concept-jump"),
            .required("3c-article-from-sheet"),
            .required("4-marked-known"),
            .required("5-cluster-overview"),
            .required("5b-cluster-detail"),
            .required("5b2-concept-sheet"),
            .optional("5b2b-topic-search",
                      because: "the arXiv search is only offered to a Concept with fewer than three Articles"),
            .optional("5b3-article-from-sheet",
                      because: "arXiv is a network this journey does not control — when it reports no new matches there is no Article row to open"),
            .required("5b4-related-concept-jump"),
            .required("5c-full-map"),
            .required("5c1-full-map-light"),
            .required("5c2-full-map-dark"),
            .required("5c3-full-map-dark-zoomed"),
            .required("5c4-full-map-light-zoomed"),
            .required("6-progress-charts"),
            .required("7-quiz-question"),
            .required("8-quiz-result"),
            .required("9-settings"),
            .required("9b-settings-footers"),
        ], launchArguments: [UITestLaunch.seedArticle])
        let app = journey.app
        journey.start()

        // First run shows onboarding (design 3a): topics preselected, continue.
        // Required rather than conditional — the store is wiped, so this *is* a
        // first run (#26).
        let continueButton = app.buttons["onboardingContinue"].firstMatch
        journey.waitFor(continueButton, "onboarding never appeared on a wiped store", timeout: 20)
        journey.snap("0-onboarding")
        XCTAssertTrue(continueButton.isEnabled, "Continue disabled despite preselected topics")
        continueButton.tap()
        journey.waitUntilGone(continueButton, "the topics step never gave way")

        // Then the Reading Intention: when reading happens, and the routine it
        // follows (#15). Skipped rather than accepted, because accepting raises
        // the system's permission alert, which is not this app's to dismiss —
        // and "declining changes nothing else" is the property worth walking.
        let routine = app.buttons["routineChip"].firstMatch
        journey.waitFor(routine, "the Reading Intention step never appeared")
        journey.tap(routine, "a suggested routine")
        // Let the tap finish before the shutter: a screenshot of the pressed
        // state is evidence of the wrong thing, and reading contrast off one is
        // how a chip gets "fixed" for a problem it never had.
        journey.settle("the chosen routine to settle")
        journey.snap("0b-reading-intention")
        let skip = app.buttons["intentionSkip"].firstMatch
        journey.waitFor(skip, "the intention step offered no way past it")
        skip.tap()
        journey.waitUntilGone(skip, "onboarding never dismissed")

        // The first Article means the first Source landed, not that the sync
        // finished — the header says which, so wait for what it says.
        let firstCard = app.buttons["articleCard"].firstMatch
        journey.waitFor(firstCard, "feed never loaded articles", timeout: 90)
        journey.waitUntil("the feed never finished syncing", timeout: 120) {
            !app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Syncing'"))
                .firstMatch.exists
        }
        journey.settle("the feed to stop filling in")
        journey.snap("1-feed")

        // 🔥 Hot-topics filter: toggling shows a (possibly empty) filtered list
        // and toggles back cleanly.
        let hotChip = app.buttons["hotChip"].firstMatch
        journey.waitFor(hotChip, "the feed has no Hot topics chip")
        journey.tap(hotChip, "Hot topics chip")
        journey.settle("the filtered feed to draw")
        journey.snap("1b-hot-topics-filter")
        journey.tap(hotChip, "Hot topics chip")
        journey.settle("the unfiltered feed to come back")

        // The Concept sheet, entered from the Article the launch planted —
        // see `openSeededArticle`.
        let chip = openSeededArticle(journey)
        journey.snap("2-article")
        journey.tap(chip, "concept chip")
        let closeSheet = app.buttons["closeSheet"].firstMatch
        journey.waitFor(closeSheet, "the concept sheet never opened")
        journey.snap("3-concept-sheet")

        // Drill-through: related concept → sibling page → back. Required: the
        // planted Article is a reading, so its Concepts are Co-read with each
        // other by the time this sheet opens.
        drillThroughRelatedConcept(journey, snapping: "3b-related-concept-jump",
                                   backTo: closeSheet, under: "Read together",
                                   missing: """
                                       the Concepts of a read Article are Co-read with each other, so \
                                       this sheet must offer a related Concept to jump to
                                       """)

        // Article row → full article → back. Required: this Concept came from
        // the Article the journey is reading, so its Article list holds at
        // least that one.
        drillThroughArticleRow(journey, snapping: "3c-article-from-sheet", backTo: closeSheet,
                               missing: "the sheet lists no Article, not even the one this Concept came from")

        // "I know this" — an outcome, not a screenshot: the button is offered
        // before and refused after.
        let know = app.buttons["knowButton"].firstMatch
        journey.waitFor(know, "the sheet has no “I know this” button")
        XCTAssertTrue(know.isEnabled, "“I know this” was already spent on a Concept the journey just met")
        know.tap()
        journey.waitUntil("the Concept never became Known") { know.exists && !know.isEnabled }
        journey.snap("4-marked-known")

        // Dismiss through the affordance built for it, not `swipeDown`.
        // A downward drag competes with the sheet's inner `ScrollView`: it
        // dismisses only while the scroll sits at the top, and otherwise
        // just scrolls the content back up while the sheet stays put (#26).
        // The drill-through above is what scrolls it — XCUITest scrolls a
        // row into view to reach it — so by this line the gesture is
        // unreliable exactly when the Concept has enough Articles to fill
        // the sheet.
        journey.tap(closeSheet, "close button")
        journey.waitUntilGone(closeSheet, "concept sheet did not dismiss")

        // Assert the tab actually changed. A sheet left open swallows this tap,
        // and without the assertion the failure surfaces three steps later as
        // "no cluster cards" — which is what #26 was reported as.
        let knowledgeTab = app.buttons["Knowledge"]
        journey.tap(knowledgeTab, "Knowledge tab")
        journey.waitUntil("Knowledge tab never became selected — a modal likely swallowed the tap") {
            knowledgeTab.isSelected
        }
        journey.settle("the cluster overview to draw")
        journey.snap("5-cluster-overview")

        // Drill into the first cluster's dependency graph (design 4b).
        let clusterCard = app.buttons["clusterCard"].firstMatch
        journey.waitFor(clusterCard, "no cluster cards")
        journey.tap(clusterCard, "cluster card")
        journey.settle("the force layout to settle", timeout: 4)
        journey.snap("5b-cluster-detail")

        // Deterministic concept-sheet entry: on a wiped store the cluster's
        // Pack Concepts are all unlit, so the frontier card is there.
        let frontier = app.buttons["frontierCard"].firstMatch
        journey.waitFor(frontier, "a freshly seeded cluster must have a frontier card")
        journey.tap(frontier, "frontier card")
        journey.waitFor(closeSheet, "the frontier Concept's sheet never opened")
        journey.snap("5b2-concept-sheet")

        // Topic search: a frontier Concept usually has no Articles yet — pull
        // fresh arXiv matches, which should populate the row list. Decided once
        // the sheet has stopped moving, because the offer stands only while the
        // Concept has fewer than three Articles.
        journey.settle("the frontier Concept's sheet to finish opening")
        let find = app.buttons["findArticles"].firstMatch
        let row = app.buttons["conceptArticleRow"].firstMatch
        let searchOffered = journey.becomesTrue({ find.exists })
        XCTAssertTrue(searchOffered || row.exists,
                      "the frontier Concept offers neither an Article to read nor a search to find one")
        var foundNothing = false
        if searchOffered {
            journey.tap(find, "find-articles button")
            // The button reports its own result: "Added N fresh articles ✓",
            // "No new matches right now" — or it goes altogether, because a
            // Concept holding three Articles is no longer offered a search.
            // Waiting for it to merely *disable* would catch the search
            // starting, and screenshot the spinner.
            journey.waitUntil("the arXiv search never came back", timeout: 45) {
                // Gone is an answer, and so is either result it reports. A
                // search still running keeps the button and its spinner, so
                // this still times out loudly when nothing comes back.
                guard let says = Journey.label(of: find) else { return true }
                return says.contains("Added") || says.contains("No new matches")
            }
            foundNothing = Journey.label(of: find)?.contains("No new matches") ?? false
            journey.snap("5b2b-topic-search")
        }
        if !foundNothing {
            // Either the search added Articles, or it was never offered because
            // the Concept already had three. Both ways there is a row.
            drillThroughArticleRow(journey, snapping: "5b3-article-from-sheet", backTo: closeSheet,
                                   missing: "the Concept has Articles, and the sheet lists none of them")
        }
        drillThroughRelatedConcept(journey, snapping: "5b4-related-concept-jump",
                                   backTo: closeSheet, under: "Related in meaning",
                                   missing: """
                                       Semantic Links are computed for the whole Pack at install, so a \
                                       frontier Concept no reading has met still has neighbours that \
                                       mean something similar (#33)
                                       """)
        journey.tap(closeSheet, "close button")
        journey.waitUntilGone(closeSheet, "the frontier Concept's sheet did not dismiss")

        journey.goBack(to: clusterCard, "the cluster overview never came back")

        // Full map: every concept in one net, no sections.
        let fullMap = app.buttons["fullMapCard"].firstMatch
        journey.waitFor(fullMap, "full map card missing")
        journey.tap(fullMap, "full map card")
        // A 141-dot net is still drifting a little at three seconds; it is
        // legible well before it is finished, and waiting for the last pixel
        // costs more than the screenshot gains.
        journey.settle("the full map's force layout to settle", timeout: 3)
        journey.snap("5c-full-map")

        // Three kinds of connection have to be told apart on the map, and the
        // only way to know they are is to look at both themes. The strokes are
        // drawn in a Canvas over Theme.card, which is exactly the combination
        // that shipped a dark-mode readability bug on Settings once.
        for key in ["Learn first", "Related", "Read together"] {
            journey.waitFor(app.staticTexts[key].firstMatch,
                            "map legend has no key for “\(key)” — the edge kinds are unexplained")
        }
        XCUIDevice.shared.appearance = .light
        journey.settle("the map to redraw in light mode", timeout: 3)
        journey.snap("5c1-full-map-light")
        XCUIDevice.shared.appearance = .dark
        journey.settle("the map to redraw in dark mode", timeout: 3)
        journey.snap("5c2-full-map-dark")

        // Zoomed in, where a dash and an arrowhead are actually resolvable: at
        // overview scale a 141-dot map is dense enough that any line looks like
        // any other, so the screenshot gate would prove nothing about whether
        // the three kinds are told apart.
        let graph = app.otherElements["knowledgeGraph"].firstMatch
        journey.waitFor(graph, "the map has no graph to zoom into")
        graph.pinch(withScale: 3, velocity: 1)
        journey.settle("the zoomed map to redraw", timeout: 2)
        journey.snap("5c3-full-map-dark-zoomed")
        XCUIDevice.shared.appearance = .light
        journey.settle("the zoomed map to redraw in light mode", timeout: 2)
        journey.snap("5c4-full-map-light-zoomed")

        journey.goBack(to: fullMap, "the cluster overview never came back from the full map")

        let progressTab = app.buttons["Progress"]
        journey.tap(progressTab, "Progress tab")
        journey.waitUntil("Progress tab never became selected") { progressTab.isSelected }
        journey.settle("the progress charts to draw")
        journey.snap("6-progress-charts")

        answerTheWeeklyQuiz(journey)

        // Settings: the large title and the section footers must both be
        // legible — this screen shipped a dark-mode readability bug once
        // precisely because the journey never captured it.
        let settingsTab = app.buttons["Settings"]
        journey.tap(settingsTab, "Settings tab")
        journey.waitUntil("Settings tab never became selected") { settingsTab.isSelected }
        journey.settle("Settings to draw")
        journey.snap("9-settings")
        app.swipeUp()
        app.swipeUp()
        journey.settle("Settings to stop scrolling")
        journey.snap("9b-settings-footers")

        journey.finish()
    }

    // MARK: - Core journey steps that need more than a line

    /// Opens the planted Article and returns its first Concept chip.
    ///
    /// The chip is required, not hoped for. On-device analysis attaches
    /// Concepts by matching the Pack's vocabulary — or by reading the text,
    /// where Apple Intelligence is available — and this Article names seven
    /// Concepts the flagship Pack defines, so an Article with no chip means
    /// analysis is broken rather than that the news was quiet. That used to be
    /// `if chip.waitForExistence(timeout: 5)`, and it skipped four steps in
    /// silence (#30).
    private func openSeededArticle(_ journey: Journey) -> XCUIElement {
        let app = journey.app
        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", UITestLaunch.seededArticleTitle))
            .firstMatch
        journey.waitFor(card, "the planted Article never reached the Feed", timeout: 60)
        journey.tap(card, "the planted Article")

        let chip = app.buttons["conceptChip"].firstMatch
        journey.waitFor(chip, """
            on-device analysis attached no Concept to an Article that names seven of them
            """, timeout: 90)
        return chip
    }

    /// Opens an Article from the Concept sheet's row list and comes back.
    private func drillThroughArticleRow(_ journey: Journey, snapping name: String,
                                        backTo sheetRoot: XCUIElement, missing: String) {
        let row = journey.app.buttons["conceptArticleRow"].firstMatch
        journey.waitFor(row, missing)
        journey.tap(row, "article row")
        journey.settle("the article to open")
        journey.snap(name)
        journey.goBack(to: sheetRoot, "the concept sheet never came back")
    }

    /// Jumps to a related Concept and comes back.
    ///
    /// Required on both sheets since #33: a read Article's Concepts are Co-read
    /// with each other, and a Concept no reading has met still has the Semantic
    /// Links its Pack's install computed. Both kinds wear the same chip, so
    /// `under` names the heading the caller is relying on and the step asserts
    /// it — otherwise a sheet offering only the other kind would pass here and
    /// `missing` would misattribute the failure it never had. The section and
    /// its chips are checked against each other either way, so a section that
    /// promises jumps and offers none is a failure and not a quiet skip.
    private func drillThroughRelatedConcept(_ journey: Journey, snapping name: String,
                                            backTo sheetRoot: XCUIElement,
                                            under claim: String, missing: String) {
        let app = journey.app
        let related = app.buttons["relatedConceptChip"].firstMatch
        let sectionHeader = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] 'Related concepts'")).firstMatch
        let offered = journey.becomesTrue({ related.exists })
        XCTAssertEqual(offered, sectionHeader.exists,
                       "the sheet's related-Concepts section and its chips disagree")
        XCTAssertTrue(offered, missing)
        XCTAssertTrue(app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", claim)).firstMatch.exists,
                      "the sheet offers chips but not under “\(claim)” — \(missing)")

        journey.tap(related, "related concept chip")
        journey.settle("the sibling Concept's page to draw")
        journey.snap(name)
        journey.goBack(to: sheetRoot, "the concept sheet never came back")
    }

    /// Answers every question of the weekly quiz and reaches the result.
    ///
    /// The quiz is always on offer: its candidates are Concepts that have a
    /// definition, and installing a Pack gives every Concept one.
    private func answerTheWeeklyQuiz(_ journey: Journey) {
        let app = journey.app
        let start = app.buttons["startQuiz"].firstMatch
        journey.waitFor(start, "the Progress tab offers no weekly quiz")
        XCTAssertTrue(start.isEnabled,
                      "the weekly quiz has no candidates, though every Pack Concept carries a definition")
        journey.tap(start, "start quiz")

        let action = app.buttons["quizAction"].firstMatch
        journey.waitFor(action, "quiz never generated", timeout: 60)
        journey.snap("7-quiz-question")

        let done = app.buttons["quizDone"].firstMatch
        var answered = 0
        // `QuizEngine.quizCandidates` caps at 8; the extra iterations are only
        // there so a runaway loop ends as a failure rather than a hang.
        while !done.exists, answered < 12 {
            let option = app.buttons["quizOption"].firstMatch
            journey.waitFor(option, "question \(answered + 1) offered no options")
            option.tap()
            journey.waitUntil("question \(answered + 1) never accepted an answer") {
                action.exists && action.isEnabled
            }
            action.tap()                                   // check answer
            journey.waitUntil("question \(answered + 1) never showed whether the answer was right") {
                // Gone or relabelled, read in one query — the same race
                // the find-articles button lost (#48).
                Journey.label(of: action) != "Check answer"
            }
            journey.tap(action, "the way on from question \(answered + 1)")
            answered += 1
        }
        XCTAssertGreaterThan(answered, 0, "the quiz ended before it asked anything")
        journey.waitFor(done, "quiz result never shown")
        journey.snap("8-quiz-result")
        journey.tap(done, "quiz done")
    }

    // MARK: - Pack selection

    /// Choosing what the map covers: see the active Pack, switch to the other
    /// built-in one, take up its suggested Sources, and switch back.
    ///
    /// Starts from a wiped store, so "the Pack's suggested Sources are offered"
    /// is a real assertion rather than one that quietly passes because a
    /// previous run already took the offer up (#26). It ends on the Pack it
    /// started on, so it leaves nothing behind either.
    func testPackSelectionJourney() throws {
        let journey = Journey("pack selection", steps: [
            .required("10-settings-pack-row"),
            .required("10a-pack-library"),
            .required("10b-import-picker"),
            .required("10c-source-offer"),
            .required("10d-pack-switched"),
            .required("10e-knowledge-after-switch"),
            .required("10f-pack-switched-back"),
            .required("10g-sources-from-pack"),
        ], launchArguments: ["-hasOnboarded", "YES"])
        let app = journey.app
        journey.start()

        journey.tap(app.buttons["Settings"], "Settings tab")
        let packRow = app.buttons["packRow"].firstMatch
        journey.waitFor(packRow, "Settings has no Pack row")
        journey.snap("10-settings-pack-row")
        journey.tap(packRow, "Pack row")

        // Both built-in Packs are on offer, and one of them is marked active.
        let builtins = app.buttons.matching(identifier: "builtinPack")
        journey.waitFor(builtins.element(boundBy: 0), "no built-in packs listed")
        journey.snap("10a-pack-library")
        XCTAssertGreaterThan(builtins.count, 1, "only one built-in pack to choose from")
        XCTAssertTrue(app.staticTexts["AI Engineering"].firstMatch.exists,
                      "the active Pack is not named")

        // Importing: the entry point opens the system file picker. What a bad
        // file does is covered by unit tests; this only proves the door opens.
        journey.tap(app.buttons["importPack"].firstMatch, "import Pack button")
        let cancel = app.buttons["Cancel"].firstMatch
        journey.waitFor(cancel, "the system file picker never opened", timeout: 15)
        journey.snap("10b-import-picker")
        journey.tap(cancel, "the file picker's Cancel button")
        journey.waitUntilGone(cancel, "the file picker never closed")
        journey.waitFor(builtins.element(boundBy: 0), "the Pack library never came back")

        // Switch to the other built-in Pack. Its suggested Sources are offered:
        // the offer lists the Sources the reader has not got, and on a wiped
        // store that is all of them.
        journey.tap(builtins.element(boundBy: 1), "the second built-in Pack")
        let accept = app.buttons["acceptSources"].firstMatch
        journey.waitFor(accept, "the Pack's suggested Sources were never offered", timeout: 15)
        journey.snap("10c-source-offer")
        journey.tap(accept, "accept sources")

        // The map is now the other Pack's.
        journey.waitFor(app.staticTexts["Security Engineering"].firstMatch, "the Pack did not switch")
        journey.snap("10d-pack-switched")

        journey.goBack(to: packRow, "Settings never came back")
        journey.tap(app.buttons["Knowledge"], "Knowledge tab")
        journey.settle("the switched map to draw", timeout: 5)
        journey.snap("10e-knowledge-after-switch")

        // Switch back, so the flagship Pack is what the next launch opens on.
        journey.tap(app.buttons["Settings"], "Settings tab")
        journey.tap(packRow, "Pack row")
        journey.waitFor(builtins.element(boundBy: 0), "the Pack library never came back")
        journey.tap(builtins.element(boundBy: 0), "the flagship Pack")
        // No offer is expected here — the flagship Pack's Sources arrived with
        // onboarding, and the offer only ever lists what the reader has not
        // got. If one does appear (a Pack gained a Source), decline it: this
        // journey is about switching back, not about changing Sources.
        let decline = app.buttons["declineSources"].firstMatch
        if journey.becomesTrue({ decline.exists }) { decline.tap() }
        journey.waitFor(app.staticTexts["AI Engineering"].firstMatch,
                        "switching back did not restore the flagship Pack")
        journey.snap("10f-pack-switched-back")

        // The Security Pack's suggestions are now the reader's own Sources,
        // and they survived switching back — a Source is chosen, not owned by
        // the Pack that suggested it.
        journey.goBack(to: packRow, "Settings never came back")
        journey.scroll(to: app.staticTexts["Krebs on Security"].firstMatch,
                       "the Pack's suggested Sources never reached Settings")
        journey.snap("10g-sources-from-pack")

        journey.finish()
    }

    // MARK: - Guards

    /// The Concept sheet must be dismissable **whatever its scroll position** —
    /// the invariant the core journey now leans on, so it gets its own guard.
    ///
    /// #26 was a journey that dismissed the sheet by `swipeDown`, which works
    /// only while the inner `ScrollView` sits at the top. This drives the case
    /// that broke it: scroll the sheet, then dismiss. It goes red if the close
    /// affordance is removed, stops being hittable while scrolled, or the sheet
    /// gains a layout where the button scrolls away with the content.
    func testConceptSheetDismissesWhileScrolled() throws {
        // No steps declared: this guard's evidence is its assertions, not a
        // screenshot, so there is nothing for the ledger to hold it to.
        let journey = Journey("sheet dismissal", steps: [],
                              launchArguments: ["-hasOnboarded", "YES"])
        let app = journey.app
        journey.start()

        journey.tap(app.buttons["Knowledge"], "Knowledge tab")
        let cluster = app.buttons["clusterCard"].firstMatch
        journey.waitFor(cluster, "no cluster cards")
        journey.tap(cluster, "cluster card")

        let frontier = app.buttons["frontierCard"].firstMatch
        journey.waitFor(frontier, "a freshly seeded cluster must have a frontier card")
        journey.tap(frontier, "frontier card")

        let close = app.buttons["closeSheet"].firstMatch
        journey.waitFor(close, "concept sheet never opened")
        journey.settle("the sheet's presentation to finish")

        // Scroll away from the top — the state in which a swipe-to-dismiss
        // silently stops working.
        let beforeScroll = app.screenshot().pngRepresentation
        app.swipeUp(velocity: .fast)
        journey.settle("the sheet to stop scrolling")
        XCTAssertNotEqual(beforeScroll, app.screenshot().pngRepresentation,
                          "sheet did not scroll, so this test is not exercising the #26 case")

        XCTAssertTrue(close.exists && close.isHittable,
                      "close button not reachable once the sheet is scrolled")
        close.tap()
        journey.waitUntilGone(close, "scrolled concept sheet did not dismiss")

        // And the tab bar is live again, which is what the journey needs next.
        let progress = app.buttons["Progress"]
        journey.tap(progress, "Progress tab")
        journey.waitUntil("tab tap still swallowed after dismissal") { progress.isSelected }

        journey.finish()
    }

    /// Usability guards: every tab reachable, primary controls hittable.
    func testTabsAndTargets() throws {
        // Onboarding covered by the core journey; the wipe keeps "every tab
        // reachable" a statement about a known install rather than about
        // whatever the last run left (#26).
        // No steps declared — see `testConceptSheetDismissesWhileScrolled`.
        let journey = Journey("tabs and targets", steps: [],
                              launchArguments: ["-hasOnboarded", "YES"])
        let app = journey.app
        journey.start()

        for tab in ["Feed", "Knowledge", "Progress", "Settings"] {
            let button = app.buttons[tab].firstMatch
            journey.waitFor(button, "\(tab) tab missing")
            XCTAssertTrue(button.isHittable, "\(tab) tab not hittable")
            button.tap()
        }
        // Settings must expose at least one source toggle, and the sync row
        // after scrolling past the sources list.
        journey.waitFor(app.switches.firstMatch, "no feed source toggles")
        journey.scroll(to: app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Sync now'")).firstMatch,
                       "Sync now row missing", swipes: 4)

        journey.finish()
    }
}
