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
        #expect(UITestLaunch.cannedGeneration == UITestSupport.cannedGenerationArgument)
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

    /// The generation journey is worth running only while the reply it stands
    /// in is the kind of reply the sanitizer exists for. A fixture quietly
    /// cleaned up would walk the journey past the code the feature is mostly
    /// made of — and would still be green, which is #30's failure wearing a
    /// different hat.
    @Test("the canned model reply really is the mess the sanitizer is for")
    func cannedGenerationReplyIsDirty() throws {
        let raw = try #require(PackGenerator.parseRemoteJSON(UITestSupport.CannedGeneration.reply),
                               "the reply must survive the fences and prose around it")

        let duplicated = UITestSupport.CannedGeneration.duplicatedConcept
        #expect(raw.concepts.filter { $0.name.lowercased() == duplicated.lowercased() }.count == 2,
                "the reply should name one Concept twice, in two cases")
        #expect(raw.concepts.contains { $0.dependencies.contains($0.name) },
                "the reply should contain a Concept that depends on itself")
        let names = Set(raw.concepts.map(\.name))
        #expect(raw.concepts.contains { $0.dependencies.contains { !names.contains($0) } },
                "the reply should depend on a Concept it never contains")
        #expect(raw.specialtyCluster.map { !raw.clusterOrder.contains($0) } == true,
                "the reply's specialty lane should name a Cluster it never declares")
        #expect(raw.stages.contains { $0.concepts.contains { !names.contains($0) } },
                "the reply should stage a Concept it never contains")
        #expect(raw.suggestedSources.isEmpty,
                "the journey must not depend on a host answering")
    }

    /// And the other half: dirty as it is, it has to reach the review screen.
    /// A reply the sanitizer cannot mend would fail the journey on the reason
    /// screen, which is a different test than the one it means to be.
    @Test("the canned reply sanitizes into a pack that installs")
    func cannedGenerationReplyBecomesInstallable() throws {
        let raw = try #require(PackGenerator.parseRemoteJSON(UITestSupport.CannedGeneration.reply))

        let clean = PackGenerator.sanitize(raw)

        try PackValidator.validate(clean)
        #expect(clean.field == UITestSupport.CannedGeneration.field)
        #expect(clean.concepts.filter {
            $0.name.lowercased() == UITestSupport.CannedGeneration.duplicatedConcept.lowercased()
        }.count == 1, "the duplicate is what the journey counts to see the sanitizer ran")
        #expect(clean.specialtyCluster.map(clean.clusterOrder.contains) == true)
    }

    @Test("the journey looks for the field the canned reply is a map of")
    func cannedGenerationNamesMatchTheApp() {
        #expect(UITestLaunch.generatedField == UITestSupport.CannedGeneration.field)
        #expect(UITestLaunch.duplicatedGeneratedConcept
                == UITestSupport.CannedGeneration.duplicatedConcept)
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
