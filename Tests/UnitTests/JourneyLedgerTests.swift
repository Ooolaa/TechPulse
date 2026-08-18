import Testing
import Foundation
@testable import TechPulse

/// The bookkeeping the UI journeys use to prove they ran (#30).
///
/// A journey is a list of steps and a list of screenshots that prove each one
/// happened. Before this existed, a step guarded by `if element.exists` skipped
/// itself and left the test green — which is how `4-marked-known.png` went
/// stale on 2026-08-13 and stayed unnoticed for four days. The rules below are
/// what make that impossible, and they are checked here rather than in the
/// journey, because a journey that has to fail to prove its own bookkeeping
/// works is not a check anybody runs.
@Suite("Journey ledger")
struct JourneyLedgerTests {

    // MARK: - Steps that did not run

    @Test("a required step that never ran is named as missing")
    func missingRequiredStepIsNamed() {
        var ledger = JourneyLedger([.required("1-feed"), .required("2-article")])
        ledger.record("1-feed")

        #expect(ledger.missing == ["2-article"])
        #expect(ledger.failureReport?.contains("2-article") == true)
    }

    @Test("a complete journey reports nothing")
    func completeJourneyIsSilent() {
        var ledger = JourneyLedger([.required("1-feed"), .required("2-article")])
        ledger.record("1-feed")
        ledger.record("2-article")

        #expect(ledger.missing.isEmpty)
        #expect(ledger.failureReport == nil)
        #expect(ledger.skipReport == nil)
    }

    @Test("a skippable step carries its reason and is reported, not silent")
    func skippableStepIsReportedWithItsReason() {
        var ledger = JourneyLedger([
            .required("1-feed"),
            .optional("1b-hot-topics-filter", because: "no article is hot on a quiet news day"),
        ])
        ledger.record("1-feed")

        #expect(ledger.missing.isEmpty)
        #expect(ledger.failureReport == nil)
        let report = try? #require(ledger.skipReport)
        #expect(report?.contains("1b-hot-topics-filter") == true)
        #expect(report?.contains("no article is hot on a quiet news day") == true)
    }

    @Test("a skippable step that ran is not reported as skipped")
    func skippableStepThatRanIsNotReported() {
        var ledger = JourneyLedger([.optional("1b-hot-topics-filter", because: "quiet news day")])
        ledger.record("1b-hot-topics-filter")

        #expect(ledger.skipReport == nil)
    }

    // MARK: - The declaration has to keep describing the journey

    @Test("recording a step the journey never declared fails")
    func undeclaredStepFails() {
        var ledger = JourneyLedger([.required("1-feed")])
        ledger.record("1-feed")
        ledger.record("9-settings")

        #expect(ledger.undeclared == ["9-settings"])
        #expect(ledger.failureReport?.contains("9-settings") == true)
    }

    @Test("recording the same step twice fails, because the name no longer identifies one step")
    func duplicateStepFails() {
        var ledger = JourneyLedger([.required("1-feed")])
        ledger.record("1-feed")
        ledger.record("1-feed")

        #expect(ledger.duplicated == ["1-feed"])
        #expect(ledger.failureReport?.contains("1-feed") == true)
    }

    @Test("the report names every problem at once, so one run tells the whole story")
    func reportCoversEveryProblem() {
        var ledger = JourneyLedger([.required("1-feed"), .required("2-article")])
        ledger.record("9-settings")

        let report = try? #require(ledger.failureReport)
        #expect(report?.contains("1-feed") == true)
        #expect(report?.contains("2-article") == true)
        #expect(report?.contains("9-settings") == true)
    }

    @Test("steps are reported in the order the journey declared them")
    func missingStepsKeepDeclarationOrder() {
        var ledger = JourneyLedger([
            .required("1-feed"), .required("2-article"), .required("3-concept-sheet"),
        ])
        ledger.record("2-article")

        #expect(ledger.missing == ["1-feed", "3-concept-sheet"])
    }
}

/// Screenshots are the journey's evidence, so they are checked like evidence.
///
/// #26 was diagnosed by noticing that `4-marked-known.png` was four days old —
/// by hand, by comparing file timestamps. These tests are that check, moved
/// into the suite: a file left over from an earlier run is not proof that this
/// run did anything.
@Suite("Screenshot evidence")
struct ScreenshotEvidenceTests {

    private func temporaryDirectory() -> String {
        let path = NSTemporaryDirectory() + "techpulse-evidence-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private let png = Data(repeating: 0x89, count: 64)

    @Test("a screenshot written during the run is evidence")
    func freshScreenshotIsEvidence() {
        let evidence = ScreenshotEvidence(directory: temporaryDirectory(), runStarted: .now)

        #expect(evidence.write(png, named: "1-feed") == nil)
        #expect(evidence.problem(with: "1-feed") == nil)
    }

    @Test("a file left over from an earlier run is not evidence")
    func staleScreenshotIsNotEvidence() throws {
        let directory = temporaryDirectory()
        let old = ScreenshotEvidence(directory: directory, runStarted: .now)
        #expect(old.write(png, named: "4-marked-known") == nil)

        // The next run starts after that file was written and never rewrites it
        // — exactly the shape of the four-day-stale screenshot in #26.
        let now = ScreenshotEvidence(directory: directory, runStarted: Date.now.addingTimeInterval(60))
        let problem = try #require(now.problem(with: "4-marked-known"))
        #expect(problem.contains("4-marked-known"))
    }

    @Test("a screenshot that was never written at all is not evidence")
    func missingScreenshotIsNotEvidence() throws {
        let evidence = ScreenshotEvidence(directory: temporaryDirectory(), runStarted: .now)

        let problem = try #require(evidence.problem(with: "1-feed"))
        #expect(problem.contains("1-feed"))
    }

    @Test("an empty file is not evidence, however fresh it is")
    func emptyScreenshotIsNotEvidence() throws {
        let evidence = ScreenshotEvidence(directory: temporaryDirectory(), runStarted: .now)

        let problem = try #require(evidence.write(Data(), named: "1-feed"))
        #expect(problem.contains("1-feed"))
    }

    @Test("an unwritable directory is reported by the write, not left to be found later")
    func unwritableDirectoryIsReported() throws {
        let evidence = ScreenshotEvidence(directory: "/dev/null/nowhere", runStarted: .now)

        #expect(evidence.write(png, named: "1-feed") != nil)
    }
}
