import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// The map grows toward what the field is discussing: a term the reader's own
/// Sources keep using, with nothing on their map that already means it, is
/// offered — and only offered (#13).
@MainActor
@Suite("Hot candidates", .serialized)
struct HotCandidateTests {

    private func context() throws -> ModelContext {
        ModelContext(try AppSchema.inMemoryContainer())
    }

    private func concept(_ name: String, cluster: String = "Foundations") -> Concept {
        Concept(name: name, category: cluster, definition: "d")
    }

    private func term(_ text: String) -> HotTerm {
        HotTerm(text: text, articles: 6, rise: 4.0)
    }

    /// Every name points a different way, so nothing means anything like
    /// anything else unless a test says so.
    private let strangers: @Sendable (String) -> [Double]? = { name in
        // Its own axis each, from the characters rather than from `hashValue`,
        // which is salted per process and would make this flaky.
        var axes = [Double](repeating: 0, count: 64)
        let index = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 64 }
        axes[index] = 1
        return axes
    }

    // MARK: What is offered

    @Test("a term with nothing like it on the map is a candidate")
    func unmatchedTermIsOffered() async {
        let candidates = await HotTopics.candidates(from: [term("world model")],
                                              concepts: [concept("Attention")],
                                              vector: strangers)
        #expect(candidates.map(\.text) == ["world model"])
    }

    @Test("a term the map already has by name is not offered again")
    func exactMatchIsNotOffered() async {
        let candidates = await HotTopics.candidates(from: [term("world model")],
                                              concepts: [concept("World Model")],
                                              vector: strangers)
        #expect(candidates.isEmpty, "matched on name, ignoring case")
    }

    @Test("a rising term the map does not mean is offered, judged by the real embedding")
    func realEmbeddingStillOffersWhatIsGenuinelyNew() async throws {
        // The other side of the threshold move (#41). Widening it from 0.25 to
        // 0.50 suppresses more, and what it must not suppress is the growth
        // this feature exists to catch. The real embedding, against the whole
        // flagship Pack, over terms of the kind a reader's Sources actually
        // raise — including "small models", which at 0.570 against `Small
        // Language Models` is the nearest any of them came.
        let concepts = try BuiltinPacks.load(BuiltinPacks.aiEngineerFileName).concepts
            .map { concept($0.name, cluster: $0.cluster) }
        let rising = ["attention sinks", "test-time compute", "mixture of experts",
                      "small models"]

        for text in rising {
            let candidates = await HotTopics.candidates(from: [term(text)], concepts: concepts)
            #expect(candidates.map(\.text) == [text],
                    "“\(text)” was taken for something the map already has")
        }
    }

    @Test("a term the map already has, spelled another way, is not offered")
    func foldedSpellingIsNotOffered() async {
        // The plural of a one-word name is further from it, under the
        // embedding, than two distinct ideas are (#41) — so this is the fold's
        // to catch, here as in `ConceptIndex.match`. Offering it would put a
        // chip in front of the reader that adds nothing when tapped: adopting
        // it merges straight back into the Concept they already have.
        let candidates = await HotTopics.candidates(from: [term("benchmarks"), term("kv cache")],
                                              concepts: [concept("Benchmark"),
                                                         concept("KV-Cache")],
                                              vector: strangers)
        #expect(candidates.isEmpty, "matched on spelling, ignoring plural and hyphen")
    }

    @Test("a term the map already has inside a longer Concept name is not offered")
    func containedNameIsNotOffered() async {
        let candidates = await HotTopics.candidates(from: [term("world model")],
                                              concepts: [concept("World Model Research")],
                                              vector: strangers)
        #expect(candidates.isEmpty)
    }

    @Test("a term extending something on the map is still offered")
    func extensionOfAKnownConceptIsOffered() async {
        // The map has "Attention"; the field has started saying "attention
        // sinks". That is the growth this feature exists for, and suppressing
        // it because the shorter name is inside the longer one would silence
        // exactly the terms worth catching.
        let candidates = await HotTopics.candidates(from: [term("attention sinks")],
                                              concepts: [concept("Attention")],
                                              vector: strangers)
        #expect(candidates.map(\.text) == ["attention sinks"])
    }

    @Test("an adopted Concept lands outside the Pack's own Clusters")
    func adoptedConceptDoesNotInflatePackProgress() async throws {
        // `WordSelection.cluster` is deliberately outside `clusterOrder` so
        // looked-up words can never inflate "2 of 13 lit". A term the reader
        // accepted is the same kind of arrival.
        let context = try context()
        let adopted = try #require(await HotTopics.adopt(term("world model"), context: context))
        let pack = try BuiltinPacks.aiEngineer()
        #expect(!pack.clusterOrder.contains(adopted.category),
                "“\(adopted.category)” is one of the Pack's own Clusters")
    }

    @Test("a term the map already means, in other words, is not offered")
    func meaningMatchIsNotOffered() async {
        // "retrieval augmentation" and "RAG" are the same thing said twice.
        // The map has one; offering the other would be a duplicate the reader
        // has to notice is a duplicate.
        let candidates = await HotTopics.candidates(
            from: [term("retrieval augmentation")], concepts: [concept("RAG")],
            vector: { name in
                ["retrieval augmentation", "rag"].contains(name) ? [1, 0, 0] : [0, 1, 0]
            })
        #expect(candidates.isEmpty)
    }

    @Test("a term merely near something on the map is still offered")
    func distantMeaningIsStillOffered() async {
        // The threshold is conservative on purpose: two Concepts stored
        // separately is a smaller harm than two ideas silently merged.
        // Pointing partly the same way — nearer than a stranger, further than
        // the same idea said twice.
        let candidates = await HotTopics.candidates(from: [term("world model")],
                                              concepts: [concept("RAG")],
                                              vector: { name in
                                                  name == "world model" ? [1, 1, 0] : [1, 0, 0]
                                              })
        #expect(candidates.map(\.text) == ["world model"])
    }

    @Test("the offer is bounded, because it is an invitation and not a backlog")
    func offerIsBounded() async {
        let terms = (0..<10).map { term("topic \($0)") }
        let candidates = await HotTopics.candidates(from: terms, concepts: [], vector: strangers)
        #expect(candidates.count <= HotTopics.candidateLimit)
    }

    // MARK: Only offered

    @Test("asking what the candidates are does not add any of them")
    func candidatesAreNotAdded() async throws {
        let context = try context()
        _ = await HotTopics.candidates(from: [term("world model")], concepts: [], vector: strangers)
        #expect(try context.fetch(FetchDescriptor<Concept>()).isEmpty)
    }

    // MARK: Accepting one

    @Test("an accepted candidate joins the map as an ordinary Concept")
    func acceptedCandidateJoinsTheMap() async throws {
        let context = try context()
        let adopted = try #require(await HotTopics.adopt(term("world model"), context: context))

        #expect(adopted.name == "World Model", "named as a reader would write it")
        #expect(adopted.category == HotTopics.adoptedCluster)
        #expect(adopted.masteryLevel == 0, "new and unlit, like any Concept a Pack brings")
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 1)
    }

    @Test("accepting the same candidate twice does not make two Concepts")
    func acceptingTwiceIsIdempotent() async throws {
        let context = try context()
        _ = await HotTopics.adopt(term("world model"), context: context)
        _ = await HotTopics.adopt(term("world model"), context: context)
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 1)
    }

    @Test("accepting the same candidate twice at once does not make two Concepts")
    func concurrentAdoptionsMakeOneConcept() async throws {
        // Two taps on one chip. `adopt` became `async` in #42, and the chip
        // stays on screen across the suspension — up to the two seconds
        // embedding a large map costs — so this is a window a thumb can hit,
        // not a theoretical interleaving. Both passes read the map before
        // either has written to it, so both used to miss and both create.
        let context = try context()
        let rising = term("world model")
        // Two main-actor tasks, which is what two taps make: the Feed's chip
        // starts an unstructured `Task` and `adopt` is `@MainActor`.
        let first = Task { @MainActor in
            _ = await HotTopics.adopt(rising, context: context)
        }
        let second = Task { @MainActor in
            _ = await HotTopics.adopt(rising, context: context)
        }
        await first.value
        await second.value

        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 1)
    }

    @Test("accepting something already on the map does not undo what was learned")
    func acceptingDoesNotResetMastery() async throws {
        // The offer should not have shown this, but a name can also arrive by
        // another route — and setting a Concept back to unlit because a
        // headline mentioned it would take away the reader's own progress.
        let context = try context()
        let known = concept("World Model")
        known.masteryLevel = 0.7
        context.insert(known)
        try context.save()

        let adopted = try #require(await HotTopics.adopt(term("world model"), context: context))
        #expect(adopted.masteryLevel == 0.7)
        #expect(adopted.category == "Foundations", "and it keeps the Cluster it was in")
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 1)
    }

    @Test("offering candidates against a full map is prompt")
    func offerAgainstRealMapIsPrompt() async throws {
        // The default path runs Apple's embedding, and the flagship Pack is 68
        // Concepts — so a lane of eight terms is up to 544 comparisons. Wall
        // clock, deliberately: who waits for them is `candidatesDoNotBlockTheMainActor`'s
        // question, and this one is that the work itself stayed small.
        let context = try context()
        try PackInstaller.install(try BuiltinPacks.aiEngineer(), origin: .builtin,
                                  context: context, vector: { _ in nil })
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let terms = (0..<HotTopics.laneSize).map { term("candidate topic \($0)") }

        let started = Date.now
        _ = await HotTopics.candidates(from: terms, concepts: concepts)
        let elapsed = Date.now.timeIntervalSince(started)

        #expect(elapsed < 1, "offering against \(concepts.count) Concepts took \(elapsed)s")
    }

    @Test("offering candidates against a large map does not freeze the Feed")
    func candidatesDoNotBlockTheMainActor() async throws {
        // The seam #49 names. Both of the Feed's callers reach the meaning
        // check through here — `FeedView.task`, where `analyzePending` returns
        // straight away on a launch with nothing pending and leaves the map
        // unembedded, and `.onChange`, a synchronous view callback with
        // nowhere to await at all — so main-actor time spent here is time the
        // Feed is not drawn, whichever of them asked.
        //
        // The real embedding, at the map size #42 was measured from, and names
        // unique to this test so the launch-long memo in `SemanticLinker.embed`
        // is cold whichever order the suite runs in.
        let context = try context()
        let concepts = (0..<600).map { number -> Concept in
            let idea = concept("Offered Idea \(number)")
            context.insert(idea)
            return idea
        }
        let rising = [term("quiet launch topic")]

        let (offered, stall, elapsed) = await mainActorStall {
            await HotTopics.candidates(from: rising, concepts: concepts)
        }

        #expect(elapsed > 0.5,
                "the pass cost \(elapsed)s — 600 Concepts were not really embedded")
        #expect(stall < elapsed / 5,
                "the Feed was held for \(stall)s of the \(elapsed)s pass")
        // Measured: 57 ms held, of a 2.2 s pass. The ratio is the claim; the
        // absolute bar keeps a slow machine from passing on it, and bounds the
        // work left behind on the main actor once the embedding hops off — the
        // fold pass, and a distance per Concept per term, which at 600 Concepts
        // is the arithmetic `SemanticLinker.distance` went through `vDSP` for.
        #expect(stall < 0.25, "the Feed was held for \(stall)s")
        // And the lane still answers: the map was weighed, not skipped.
        #expect(offered.map(\.text) == ["quiet launch topic"])
    }

    @Test("an accepted candidate stops being offered")
    func acceptedCandidateLeavesTheOffer() async throws {
        let context = try context()
        _ = await HotTopics.adopt(term("world model"), context: context)
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let candidates = await HotTopics.candidates(from: [term("world model")],
                                                    concepts: concepts, vector: strangers)
        #expect(candidates.isEmpty)
    }
}
