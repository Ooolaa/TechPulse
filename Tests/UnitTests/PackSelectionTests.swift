import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// A reader chooses what their map covers: a different built-in Pack, or a
/// Pack file they were given. Switching must cost them nothing they learned,
/// and a bad file must cost them nothing at all.
@MainActor
@Suite("Choosing a Pack", .serialized)
struct PackSelectionTests {

    private func makeContext() throws -> ModelContext {
        let container = try AppSchema.inMemoryContainer()
        ActivePack.resetCache()
        return ModelContext(container)
    }

    private func concept(_ name: String, in context: ModelContext) throws -> Concept? {
        try context.fetch(FetchDescriptor<Concept>()).first { $0.name == name }
    }

    private func aiEngineer() throws -> PackFile { try BuiltinPacks.aiEngineer() }

    private func security() throws -> PackFile {
        try BuiltinPacks.load(BuiltinPacks.securityEngineeringFileName)
    }

    // MARK: - There is more than one map to choose from

    @Test("the app offers more than one built-in Pack")
    func moreThanOneBuiltin() throws {
        #expect(BuiltinPacks.all.count > 1)
        #expect(BuiltinPacks.all.map(\.fileName) == BuiltinPacks.fileNames)
    }

    @Test("built-in Packs cover distinct fields, which is what recognising one by field rests on")
    func builtinFieldsAreDistinct() throws {
        // A field does not name a Pack in general — a Pack the reader was given
        // may cover a built-in's field, and #39 is what that cost. Among the
        // Packs that ship together it has to be unique anyway: a built-in whose
        // file this build no longer ships is recognised by its field, and two
        // sharing one would make that answer a coin toss (ADR-0008).
        let fields = BuiltinPacks.all.map(\.pack.field)
        #expect(Set(fields).count == fields.count)
    }

    @Test("every built-in Pack passes validation and suggests Sources that could be subscribed to")
    func builtinsAreInstallable() throws {
        for builtin in BuiltinPacks.all {
            try PackValidator.validate(builtin.pack)
            #expect(!builtin.pack.suggestedSources.isEmpty,
                    "“\(builtin.pack.field)” offers the reader nothing to read")
            for source in builtin.pack.suggestedSources {
                // https, not merely parseable: FeedSyncService fetches nothing else.
                #expect(URL(string: source.url)?.scheme == "https",
                        "unusable Source URL in “\(builtin.pack.field)”: \(source.url)")
            }
        }
    }

    /// The format caps what a Pack may suggest (#20). The Packs that ship in
    /// the app have to sit inside their own format — and comfortably, or the
    /// cap is a budget rather than a bound on the absurd.
    @Test("every built-in Pack suggests fewer Sources than the format allows")
    func builtinsAreInsideTheSuggestionCap() throws {
        for builtin in BuiltinPacks.all {
            #expect(builtin.pack.suggestedSources.count <= PackFile.maxSuggestedSources,
                    "“\(builtin.pack.field)” suggests more Sources than a Pack may")
        }
    }

    @Test("the Security Engineering Pack draws a real map, with a side-quest lane")
    func securityPackIsAMap() throws {
        let pack = try security()
        #expect(pack.field == "Security Engineering")
        #expect(pack.concepts.count > 30)
        let specialty = try #require(pack.specialtyCluster)
        #expect(pack.clusterOrder.contains(specialty))
        #expect(pack.concepts.map(\.cluster).contains(specialty))

        // Every Concept outside the side quest sits on the staged path, or the
        // "You are here" ladder skips part of the field.
        let staged = Set(pack.stages.flatMap(\.concepts))
        for concept in pack.concepts where concept.cluster != specialty {
            #expect(staged.contains(concept.name), "“\(concept.name)” is on no stage")
        }
    }

    // MARK: - Switching between built-in Packs

    @Test("choosing a different built-in Pack switches the map to it")
    func switchingChangesTheMap() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)
        try PackInstaller.install(try security(), origin: .builtin, context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "Security Engineering")
        #expect(active.clusterOrder == (try security()).clusterOrder)
        #expect(active.conceptNames == (try security()).concepts.map(\.name))

        // Exactly one Pack is active, and the engines answer against it.
        #expect(try context.fetch(FetchDescriptor<InstalledPack>()).filter(\.isActive).count == 1)
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let deps = try context.fetch(FetchDescriptor<ConceptDependency>())
        let frontier = KnowledgePathEngine.frontier(concepts: concepts, dependencies: deps)
        #expect(!frontier.isEmpty)
        #expect(frontier.allSatisfy(Set(active.conceptNames).contains))
    }

    @Test("switching Packs preserves Mastery for Concepts that exist in both")
    func switchingPreservesSharedMastery() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)

        // These Concepts are in both built-in Packs — the same idea, read from
        // two fields. Learning one must not be undone by switching.
        let shared = Set(try aiEngineer().concepts.map(\.name))
            .intersection(try security().concepts.map(\.name))
        #expect(!shared.isEmpty, "the two built-in Packs share no Concepts to preserve")

        for name in shared {
            let held = try #require(try concept(name, in: context))
            held.masteryLevel = 0.6
            held.lastReviewed = .now
            context.insert(LearningEvent(kind: "read", conceptName: name, masteryDelta: 0.1))
        }
        try context.save()

        try PackInstaller.install(try security(), origin: .builtin, context: context)

        for name in shared {
            let after = try #require(try concept(name, in: context),
                                     "“\(name)” did not survive the switch")
            #expect(after.masteryLevel == 0.6)
            #expect(after.masteryState == .learning)     // still half-lit, not reset
            #expect(after.lastReviewed != nil)
        }
        #expect(try context.fetch(FetchDescriptor<LearningEvent>()).count == shared.count)
    }

    @Test("the retired Pack's Concepts keep their Mastery — what you learned is yours")
    func retiredPackKeepsItsMastery() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)

        let rag = try #require(try concept("RAG", in: context))
        rag.masteryLevel = 0.9
        try context.save()

        try PackInstaller.install(try security(), origin: .builtin, context: context)

        // "RAG" is in no security Pack, but the reader still knows it.
        let survivor = try #require(try concept("RAG", in: context))
        #expect(survivor.masteryLevel == 0.9)
        #expect(ActivePack.load(context: context)?.conceptNames.contains("RAG") == false)
    }

    @Test("switching back lands on the first Pack again, with its Mastery intact")
    func switchingBack() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)
        let rag = try #require(try concept("RAG", in: context))
        rag.masteryLevel = 0.5
        try context.save()

        try PackInstaller.install(try security(), origin: .builtin, context: context)
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "AI Engineering")
        #expect(try concept("RAG", in: context)?.masteryLevel == 0.5)
        // Three installs, one active Pack — retiring, not accumulating.
        #expect(try context.fetch(FetchDescriptor<InstalledPack>()).filter(\.isActive).count == 1)
    }

    @Test("the active Pack says where it came from, so the reader can see which map they are on")
    func activePackNamesItsOrigin() throws {
        let context = try makeContext()
        try PackInstaller.install(try security(), origin: .imported, context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "Security Engineering")
        #expect(active.origin == .imported)
        #expect(active.origin.label == "Imported")
    }

    @Test("an origin no build understands is not read as the app's own Pack")
    func unknownOriginIsNotBuiltin() throws {
        let context = try makeContext()
        let record = try PackInstaller.install(try security(), origin: .generated,
                                               context: context)
        #expect(record.packOrigin == .generated)

        // A record written by some later build, read by this one. Claiming it
        // as built-in would put it back under launch's control.
        record.origin = "conjured"
        #expect(record.packOrigin != .builtin)
    }

    // MARK: - Importing a Pack file

    @Test("a Pack file from outside the app installs and becomes the map")
    func importInstalls() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)

        // What a reader would be handed: the bytes of a Pack file.
        let bytes = try JSONEncoder().encode(try security())
        let imported = try PackValidator.decodeAndValidate(bytes)
        try PackInstaller.install(imported, origin: .imported, context: context)

        let active = try #require(ActivePack.load(context: context))
        #expect(active.field == "Security Engineering")
        #expect(active.origin == .imported)
    }

    @Test("an invalid Pack file is rejected with the validator's reason and changes nothing")
    func importRejectsInvalidFile() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)
        let before = try context.fetch(FetchDescriptor<Concept>()).count

        // A Pack naming a Dependency it does not contain — the reader has to
        // be told which Concept and which missing name.
        var broken = try security()
        broken.concepts[0].dependencies = ["No Such Concept"]
        let bytes = try JSONEncoder().encode(broken)

        var reason: String?
        #expect(throws: PackValidationError.self) {
            do {
                let pack = try PackValidator.decodeAndValidate(bytes)
                try PackInstaller.install(pack, origin: .imported, context: context)
            } catch {
                reason = error.localizedDescription
                throw error
            }
        }
        let told = try #require(reason)
        #expect(told.contains("No Such Concept"))
        #expect(told.contains(broken.concepts[0].name))

        // Nothing about the map moved.
        #expect(ActivePack.load(context: context)?.field == "AI Engineering")
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == before)
        #expect(try context.fetch(FetchDescriptor<InstalledPack>()).count == 1)
    }

    @Test("a file that is not a Pack at all is rejected with something readable")
    func importRejectsNonPackFile() throws {
        let context = try makeContext()
        try PackInstaller.install(try aiEngineer(), origin: .builtin, context: context)

        for bytes in [Data("not json at all".utf8), Data("{}".utf8)] {
            var reason: String?
            #expect(throws: PackValidationError.self) {
                do {
                    _ = try PackValidator.decodeAndValidate(bytes)
                } catch {
                    reason = error.localizedDescription
                    throw error
                }
            }
            #expect(reason?.isEmpty == false)
        }
        #expect(ActivePack.load(context: context)?.field == "AI Engineering")
    }

    // MARK: - The Pack's suggested Sources are offered

    @Test("a newly installed Pack's suggested Sources are all on offer")
    func suggestionsAreOffered() throws {
        let context = try makeContext()
        let pack = try security()
        try PackInstaller.install(pack, origin: .builtin, context: context)

        let offered = PackSourceOffer.pending(pack.suggestedSources, context: context)
        #expect(offered.map(\.url) == pack.suggestedSources.map(\.url))
        // Offered, not subscribed: installing still signs the reader up to nothing.
        #expect(try context.fetch(FetchDescriptor<FeedSource>()).isEmpty)
    }

    @Test("accepting the offer subscribes to exactly what was accepted")
    func acceptingSubscribes() throws {
        let context = try makeContext()
        let pack = try security()
        let accepted = Array(pack.suggestedSources.prefix(2))

        #expect(PackSourceOffer.subscribe(accepted, context: context) == 2)

        let sources = try context.fetch(FetchDescriptor<FeedSource>())
        let subscribed = Set(sources.map(\.url.absoluteString))
        #expect(subscribed == Set(accepted.map(\.url)))
        let allEnabled = sources.allSatisfy(\.isEnabled)
        #expect(allEnabled)
        let first = try #require(sources.first { $0.url.absoluteString == accepted[0].url })
        #expect(first.name == accepted[0].name)
        #expect(first.category == accepted[0].category)
    }

    @Test("a Source the reader already has is not offered again, or added twice")
    func alreadySubscribedIsNotOffered() throws {
        let context = try makeContext()
        let pack = try security()
        let known = pack.suggestedSources[0]
        context.insert(FeedSource(name: "My own name for it",
                                  url: URL(string: known.url)!, category: "Mine"))
        try context.save()

        let offered = PackSourceOffer.pending(pack.suggestedSources, context: context)
        #expect(!offered.map(\.url).contains(known.url))

        // Accepting the whole list twice must still leave one row per Source.
        PackSourceOffer.subscribe(pack.suggestedSources, context: context)
        PackSourceOffer.subscribe(pack.suggestedSources, context: context)
        let urls = try context.fetch(FetchDescriptor<FeedSource>()).map(\.url.absoluteString)
        #expect(Set(urls).count == urls.count)
        #expect(urls.count == pack.suggestedSources.count)
        // And the reader's own name for the Source they had survives.
        let names = try context.fetch(FetchDescriptor<FeedSource>()).map(\.name)
        #expect(names.contains("My own name for it"))
    }

    // MARK: - What the offer opens with ticked
    //
    // Pre-checking is consent by default, so it is bounded too (#20). A Pack at
    // the format's cap must not open with thirty Sources ticked and one tap
    // standing between the reader and thirty subscriptions. What an *unticked*
    // box means once that happens is `SourceAcquisitionTests`' half of this.

    /// Suggestions on distinct hosts, so a count is all that separates them.
    private func suggestions(_ count: Int) -> [PackFile.PackSource] {
        (0..<count).map {
            .init(name: "Feed \($0)", url: "https://feed-\($0).test/rss", category: "LLMs")
        }
    }

    @Test("a short offer opens with every suggestion ticked")
    func shortOfferOpensTicked() throws {
        let short = suggestions(PackSourceOffer.preCheckedUpTo)

        #expect(PackSourceOffer.preChecked(short) == Set(short.map(\.url)))
    }

    @Test("an offer past the threshold opens with nothing ticked, not with the first fifteen")
    func longOfferOpensUnticked() throws {
        let long = suggestions(PackSourceOffer.preCheckedUpTo + 1)

        // Empty, so "Add 0" is disabled and the reader has to say which ones.
        // Not a prefix: the order suggestions arrive in is the author's, not a
        // ranking the app may read as consent.
        #expect(PackSourceOffer.preChecked(long).isEmpty)
    }

    /// The threshold is set from the shipped Packs, so it has to keep holding
    /// them. A built-in that grew past it would quietly stop opening ticked —
    /// and the switch-Pack journey taps "Add" without ticking anything.
    @Test("every built-in Pack's offer still opens ticked")
    func builtinOffersOpenTicked() throws {
        for builtin in BuiltinPacks.all {
            let sources = builtin.pack.suggestedSources
            #expect(PackSourceOffer.preChecked(sources).count == sources.count,
                    "“\(builtin.pack.field)” now suggests too many Sources to open ticked")
        }
    }

    @Test("a suggestion that could never be fetched is never offered")
    func unusableSuggestionIsNotOffered() throws {
        let context = try makeContext()
        let suggestions = [
            PackFile.PackSource(name: "Nowhere", url: "not a url", category: "Broken"),
            PackFile.PackSource(name: "Somewhere", url: "https://example.com/feed",
                                category: "Fine"),
        ]

        #expect(PackSourceOffer.pending(suggestions, context: context).map(\.name) == ["Somewhere"])
        #expect(PackSourceOffer.subscribe(suggestions, context: context) == 1)
    }

    @Test("a suggestion the sync could only ever fetch nothing from is never offered")
    func nonHTTPSSuggestionIsNotOffered() throws {
        let context = try makeContext()
        let suggestions = [
            PackFile.PackSource(name: "Plaintext", url: "http://example.com/feed",
                                category: "Old"),
            PackFile.PackSource(name: "Secure", url: "https://example.com/feed",
                                category: "Fine"),
        ]

        // FeedSyncService fetches https and nothing else, so an http suggestion
        // would subscribe the reader to a Source that stays empty in silence.
        #expect(PackSourceOffer.pending(suggestions, context: context).map(\.name) == ["Secure"])
        #expect(PackSourceOffer.subscribe(suggestions, context: context) == 1)
        #expect(try context.fetch(FetchDescriptor<FeedSource>()).map(\.url.scheme) == ["https"])
    }

    @Test("a suggestion whose URL needs escaping is still only ever added once")
    func escapedSuggestionIsNotAddedTwice() throws {
        let context = try makeContext()
        // A Source is stored as URL(string:) escapes it — "rss feed" becomes
        // "rss%20feed" — so recognising it again means matching what was stored,
        // not what the Pack wrote. Otherwise every accept adds another row.
        let suggestions = [
            PackFile.PackSource(name: "Spaced", url: "https://example.com/rss feed",
                                category: "Fine"),
        ]

        #expect(PackSourceOffer.subscribe(suggestions, context: context) == 1)
        #expect(PackSourceOffer.pending(suggestions, context: context).isEmpty)
        #expect(PackSourceOffer.subscribe(suggestions, context: context) == 0)
        #expect(try context.fetch(FetchDescriptor<FeedSource>()).count == 1)
    }
}
