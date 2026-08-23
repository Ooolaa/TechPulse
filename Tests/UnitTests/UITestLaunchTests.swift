import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// The UI journeys drive the app through launch arguments they cannot import.
///
/// `UITestLaunch` is their copy; `UITestSupport` is the app's. Three comments
/// used to ask whoever changed one to remember the other, which is the kind of
/// instruction that is followed until it isn't — and the failure would look
/// like a journey running against an un-wiped store, i.e. #26 again.
@MainActor
@Suite("UI test launch arguments")
struct UITestLaunchTests {

    private static let store = TestStore()

    @Test("the journeys' launch arguments are still the app's")
    func launchArgumentsMatchTheApp() {
        #expect(UITestLaunch.resetStore == UITestSupport.resetStoreArgument)
        #expect(UITestLaunch.seedArticle == UITestSupport.seedArticleArgument)
        #expect(UITestLaunch.seedSourceHealth == UITestSupport.seedSourceHealthArgument)
    }

    @Test("the journey looks for the Sources the app plants")
    func seededSourceNamesMatchTheApp() {
        #expect(UITestLaunch.throttledSourceName == UITestSupport.SeededHealth.throttledName)
        #expect(UITestLaunch.stoppedSourceName == UITestSupport.SeededHealth.stoppedName)
    }

    /// The fixture only shows what this issue is about while the dates it
    /// plants really land on either side of the threshold health judges by.
    /// Two constants that agreed by luck would photograph two healthy rows.
    @Test("the planted Sources really are one failing and one long dead")
    func seededSourcesLandWhereHealthJudgesThem() throws {
        let context = try Self.store.makeContext()
        UITestSupport.seedSourceHealth(context: context)
        let sources = try context.fetch(FetchDescriptor<FeedSource>())
        let readings = SourceHealth.read(sources, in: context)
        func reading(named name: String) throws -> SourceHealth {
            let source = try #require(sources.first { $0.name == name })
            return try #require(readings[source.persistentModelID])
        }

        let throttled = try reading(named: UITestSupport.SeededHealth.throttledName)
        #expect(throttled.state == .failing(.throttled))
        #expect(throttled.cached == 2,
                "failing out loud must not read as having lost the reading it already gave")
        #expect(try reading(named: UITestSupport.SeededHealth.stoppedName).state == .likelyDead)
    }

    @Test("the journey looks for the Article the app plants")
    func seededArticleTitleMatchesTheApp() {
        #expect(UITestLaunch.seededArticleTitle == UITestSupport.SeededArticle.title)
    }

    @Test("the planted Article names Concepts the flagship Pack defines")
    func seededArticleNamesPackConcepts() throws {
        let pack = try BuiltinPacks.aiEngineer()
        let names = Set(pack.concepts.map(\.name))
        let text = "\(UITestSupport.SeededArticle.title) \(UITestSupport.SeededArticle.body)"

        // The core journey requires a Concept chip on this Article, so the
        // keyword tier has to have something to match — whole words, as
        // `IntelligenceService.fallbackAnalysis` matches them.
        let named = names.filter { name in
            text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b",
                       options: [.regularExpression, .caseInsensitive]) != nil
        }
        #expect(named.count >= 5, "the planted Article names only \(named.sorted())")
    }
}
