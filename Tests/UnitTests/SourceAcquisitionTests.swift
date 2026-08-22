import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// How a Source is acquired (#47, ADR-0011).
///
/// Two mechanisms used to deliver Sources and disagree about consent: an offer
/// that subscribed to nothing, and a launch-time seeder that subscribed to
/// everything from a compiled AI list regardless of which Pack the reader was
/// on. These are the rules that replaced the second one.
@MainActor
@Suite("Acquiring a Source", .serialized)
struct SourceAcquisitionTests {

    private func makeContext() throws -> ModelContext {
        let container = try AppSchema.inMemoryContainer()
        ActivePack.resetCache()
        PackSourceOffer.forgetDeclined()
        return ModelContext(container)
    }

    private func aiEngineer() throws -> PackFile { try BuiltinPacks.aiEngineer() }

    private func security() throws -> PackFile {
        try BuiltinPacks.load(BuiltinPacks.securityEngineeringFileName)
    }

    private func subscribedURLs(_ context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<FeedSource>()).map(\.url.absoluteString))
    }

    /// The standing offer as `SettingsView` computes it — off the Sources the
    /// view already holds, rather than a fetch of its own.
    private func standing(_ suggestions: [PackFile.PackSource],
                          _ context: ModelContext) throws -> [PackFile.PackSource] {
        PackSourceOffer.standing(suggestions, subscribedTo: try subscribedURLs(context))
    }

    // MARK: - The first launch

    @Test("a store with nothing to read is subscribed to the Active Pack's suggestions")
    func firstLaunchSubscribes() throws {
        let context = try makeContext()
        let pack = try aiEngineer()
        try PackInstaller.install(pack, origin: .builtin, context: context)

        SeedData.acquireSourcesIfNeeded(context: context)

        #expect(try subscribedURLs(context) == Set(pack.suggestedSources.map(\.url)))
        // And nothing is left on offer, because it was all taken.
        #expect(try standing(pack.suggestedSources, context).isEmpty)
    }

    @Test("the Pack the reader is on decides which Sources arrive, not a compiled AI list")
    func suggestionsFollowTheActivePack() throws {
        let context = try makeContext()
        let pack = try security()
        try PackInstaller.install(pack, origin: .builtin, context: context)

        SeedData.acquireSourcesIfNeeded(context: context)

        let subscribed = try subscribedURLs(context)
        #expect(subscribed == Set(pack.suggestedSources.map(\.url)))
        // The sharper edge of #47: a Security Engineering reader used to
        // receive arXiv cs.AI, OpenAI News and r/kaggle without being asked.
        for flagship in try aiEngineer().suggestedSources {
            #expect(!subscribed.contains(flagship.url),
                    "the flagship's “\(flagship.name)” reached a Security Engineering reader")
        }
    }

    // MARK: - Every launch after the first

    @Test("a Source added to a Pack in a new app version is offered, never subscribed")
    func laterArrivalsAreOfferedNotSubscribed() throws {
        let context = try makeContext()
        let pack = try aiEngineer()
        try PackInstaller.install(pack, origin: .builtin, context: context)
        SeedData.acquireSourcesIfNeeded(context: context)

        // A reader whose store predates one of the Pack's Sources — exactly
        // what #46 created by adding the vote-ranked feed to a shipped Pack.
        let arrival = try #require(pack.suggestedSources.first {
            $0.url.contains("r/MachineLearning")
        })
        let existing = try context.fetch(FetchDescriptor<FeedSource>())
        let row = try #require(existing.first { $0.url.absoluteString == arrival.url })
        context.delete(row)
        try context.save()

        SeedData.acquireSourcesIfNeeded(context: context)

        #expect(!(try subscribedURLs(context)).contains(arrival.url),
                "launch subscribed the reader to a Source they were never offered")
        #expect(try standing(pack.suggestedSources, context)
            .map(\.url) == [arrival.url])
    }

    @Test("a launch that adds nothing still leaves the reader's Sources alone")
    func laterLaunchesChangeNothing() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)
        SeedData.acquireSourcesIfNeeded(context: context)
        let after = try subscribedURLs(context)

        SeedData.acquireSourcesIfNeeded(context: context)
        SeedData.acquireSourcesIfNeeded(context: context)

        #expect(try subscribedURLs(context) == after)
        #expect(try context.fetch(FetchDescriptor<FeedSource>()).count == after.count)
    }

    @Test("switching Pack does not hand the reader the new Pack's Sources unasked")
    func switchingPackOffersRatherThanSubscribes() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)
        SeedData.acquireSourcesIfNeeded(context: context)

        let securityPack = try security()
        try PackInstaller.install(securityPack, origin: .builtin, context: context)
        SeedData.acquireSourcesIfNeeded(context: context)

        let subscribed = try subscribedURLs(context)
        for suggestion in securityPack.suggestedSources {
            #expect(!subscribed.contains(suggestion.url))
        }
        #expect(try standing(securityPack.suggestedSources, context).count
                == securityPack.suggestedSources.count)
    }

    // MARK: - Turning an offer down

    @Test("a suggestion the reader turned down stops being raised")
    func declinedSuggestionsAreNotRaisedAgain() throws {
        let context = try makeContext()
        let pack = try security()

        #expect(try standing(pack.suggestedSources, context).count
                == pack.suggestedSources.count)

        PackSourceOffer.recordDeclined(pack.suggestedSources)

        #expect(try standing(pack.suggestedSources, context).isEmpty)
        // Turning an offer down subscribes to nothing, the same as ignoring it.
        #expect(try context.fetch(FetchDescriptor<FeedSource>()).isEmpty)
    }

    @Test("turning one suggestion down leaves the rest on offer")
    func decliningIsPerSuggestion() throws {
        let context = try makeContext()
        let pack = try security()
        let refused = pack.suggestedSources[0]

        PackSourceOffer.recordDeclined([refused])

        let offered = try standing(pack.suggestedSources, context)
        #expect(!offered.map(\.url).contains(refused.url))
        #expect(offered.count == pack.suggestedSources.count - 1)
    }

    @Test("installing the Pack by hand asks again, which is the way back from a decline")
    func installingByHandAsksAgain() throws {
        let context = try makeContext()
        let pack = try security()
        PackSourceOffer.recordDeclined(pack.suggestedSources)

        // `PackLibraryView` offers `pending`, not `standing`: choosing a Pack
        // from the library is the reader asking to see its Sources.
        #expect(PackSourceOffer.pending(pack.suggestedSources, context: context).count
                == pack.suggestedSources.count)
        #expect(try standing(pack.suggestedSources, context).isEmpty)
    }

    @Test("a decline never hides a Source the reader went on to subscribe to")
    func decliningThenSubscribingLeavesNoOffer() throws {
        let context = try makeContext()
        let pack = try security()
        let one = pack.suggestedSources[0]

        PackSourceOffer.recordDeclined([one])
        PackSourceOffer.subscribe([one], context: context)

        #expect(try subscribedURLs(context).contains(one.url))
        #expect(!(try standing(pack.suggestedSources, context))
            .map(\.url).contains(one.url))
    }

    // MARK: - What a Pack may ask for (#20)

    /// A Pack that is a map only incidentally: one Concept, and as many
    /// suggested Sources as the test is about. Every suggestion is on a host of
    /// its own, so nothing here turns on two of them sharing one.
    private func packSuggesting(_ count: Int) -> PackFile {
        PackFile(field: "Everything",
                 specialtyCluster: nil,
                 clusterOrder: ["Foundations"],
                 concepts: [.init(name: "Attention", cluster: "Foundations",
                                  definition: "Weighted lookup.", dependencies: [])],
                 stages: [],
                 suggestedSources: (0..<count).map {
                     .init(name: "Feed \($0)", url: "https://feed-\($0).test/rss",
                           category: "LLMs")
                 })
    }

    /// An imported Pack is a file from outside the app, and the format is where
    /// it is told no. A Pack carrying more suggestions than
    /// `PackFile.maxSuggestedSources` never gets as far as the offer sheet, so
    /// the reader is never one tap from hundreds of subscriptions — and never
    /// one cold sync from hundreds of requests off their device.
    @Test("a Pack suggesting more Sources than the format allows is rejected, and subscribes nothing")
    func anOverCapImportSubscribesNothing() throws {
        let context = try makeContext()
        let pack = try aiEngineer()
        try PackInstaller.install(pack, origin: .builtin, context: context)
        SeedData.acquireSourcesIfNeeded(context: context)
        let before = try subscribedURLs(context)

        let over = PackFile.maxSuggestedSources + 1
        let greedy = packSuggesting(over)

        // Through the bytes, because that is what importing a file actually is.
        #expect(throws: PackValidationError.tooManySuggestedSources(over)) {
            _ = try PackValidator.decodeAndValidate(try JSONEncoder().encode(greedy))
        }

        // Nothing was installed, so nothing is subscribed — and the record the
        // standing offer reads is still the flagship's, so none of the thirty-one
        // can be raised at a later launch either.
        #expect(try subscribedURLs(context) == before)
        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "AI Engineering")
        #expect(active.suggestedSources.map(\.url) == pack.suggestedSources.map(\.url))
        #expect(try standing(active.suggestedSources, context).isEmpty)
    }

    /// The other side of the cap: at it, an import still works. A bound that
    /// also turned away the largest legal Pack would be off by one.
    @Test("a Pack at the cap installs, and offers exactly what it suggests")
    func aPackAtTheCapIsOffered() throws {
        let context = try makeContext()
        let atCap = packSuggesting(PackFile.maxSuggestedSources)

        let decoded = try PackValidator.decodeAndValidate(try JSONEncoder().encode(atCap))
        try PackInstaller.install(decoded, origin: .imported, context: context)

        // Offered, not subscribed — an import is still an offer (ADR-0011).
        #expect(PackSourceOffer.pending(decoded.suggestedSources, context: context).count
                == PackFile.maxSuggestedSources)
        #expect(try context.fetch(FetchDescriptor<FeedSource>()).isEmpty)
        // And the offer at that size opens with nothing ticked, so accepting it
        // wholesale is not one tap.
        #expect(PackSourceOfferView.preChecked(decoded.suggestedSources).isEmpty)
    }

    // MARK: - Retirement

    @Test("a Source that turned out dead is removed, and does not re-seed the store")
    func retiredSourceIsSweptWithoutReseeding() throws {
        let context = try makeContext()
        let pack = try aiEngineer()
        try PackInstaller.install(pack, origin: .builtin, context: context)
        SeedData.acquireSourcesIfNeeded(context: context)

        let dead = URL(string: "https://medium.com/feed/kaggle-blog")!
        context.insert(FeedSource(name: "Kaggle Blog", url: dead, category: "Data Science"))
        try context.save()

        SeedData.acquireSourcesIfNeeded(context: context)

        #expect(!(try subscribedURLs(context)).contains(dead.absoluteString))
        #expect(try subscribedURLs(context) == Set(pack.suggestedSources.map(\.url)))
    }

    @Test("a store that held Sources is never re-seeded, even if retirement empties it")
    func retirementNeverReopensTheFirstLaunch() throws {
        let context = try makeContext()
        let pack = try aiEngineer()
        try PackInstaller.install(pack, origin: .builtin, context: context)
        context.insert(FeedSource(name: "Kaggle Blog",
                                  url: URL(string: "https://medium.com/feed/kaggle-blog")!,
                                  category: "Data Science"))
        try context.save()

        SeedData.acquireSourcesIfNeeded(context: context)

        // The reader is left with nothing, which is theirs to fix. Handing back
        // fourteen Sources they were never offered would be the behaviour this
        // whole path exists to stop.
        #expect(try context.fetch(FetchDescriptor<FeedSource>()).isEmpty)
        #expect(try standing(pack.suggestedSources, context).count
                == pack.suggestedSources.count)
    }

    // MARK: - Through launch

    @Test("launch settles the Pack before it decides which Sources to offer")
    func launchSeedsAgainstTheInstalledPack() throws {
        let context = try makeContext()
        // A reader who chose Security Engineering on an earlier run. Launch has
        // to reinstate that Pack before reading suggestions off it, or the
        // flagship's Sources arrive instead.
        try PackInstaller.install(try security(), origin: .builtin, context: context)

        SeedData.seedIfNeeded(context: context)

        let subscribed = try subscribedURLs(context)
        #expect(subscribed == Set(try security().suggestedSources.map(\.url)))
        #expect(ActivePack.load(context: context)?.field == "Security Engineering")
    }
}
