import Testing
import Foundation
@testable import TechPulse

/// The UI journeys drive the app through launch arguments they cannot import.
///
/// `UITestLaunch` is their copy; `UITestSupport` is the app's. Three comments
/// used to ask whoever changed one to remember the other, which is the kind of
/// instruction that is followed until it isn't — and the failure would look
/// like a journey running against an un-wiped store, i.e. #26 again.
@Suite("UI test launch arguments")
struct UITestLaunchTests {

    @Test("the journeys' launch arguments are still the app's")
    func launchArgumentsMatchTheApp() {
        #expect(UITestLaunch.resetStore == UITestSupport.resetStoreArgument)
        #expect(UITestLaunch.seedArticle == UITestSupport.seedArticleArgument)
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
