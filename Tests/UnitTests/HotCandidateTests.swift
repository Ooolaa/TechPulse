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
    func unmatchedTermIsOffered() {
        let candidates = HotTopics.candidates(from: [term("world model")],
                                              concepts: [concept("Attention")],
                                              vector: strangers)
        #expect(candidates.map(\.text) == ["world model"])
    }

    @Test("a term the map already has by name is not offered again")
    func exactMatchIsNotOffered() {
        let candidates = HotTopics.candidates(from: [term("world model")],
                                              concepts: [concept("World Model")],
                                              vector: strangers)
        #expect(candidates.isEmpty, "matched on name, ignoring case")
    }

    @Test("a term the map already has inside a longer Concept name is not offered")
    func containedNameIsNotOffered() {
        let candidates = HotTopics.candidates(from: [term("world model")],
                                              concepts: [concept("World Model Research")],
                                              vector: strangers)
        #expect(candidates.isEmpty)
    }

    @Test("a term extending something on the map is still offered")
    func extensionOfAKnownConceptIsOffered() {
        // The map has "Attention"; the field has started saying "attention
        // sinks". That is the growth this feature exists for, and suppressing
        // it because the shorter name is inside the longer one would silence
        // exactly the terms worth catching.
        let candidates = HotTopics.candidates(from: [term("attention sinks")],
                                              concepts: [concept("Attention")],
                                              vector: strangers)
        #expect(candidates.map(\.text) == ["attention sinks"])
    }

    @Test("an adopted Concept lands outside the Pack's own Clusters")
    func adoptedConceptDoesNotInflatePackProgress() throws {
        // `WordSelection.cluster` is deliberately outside `clusterOrder` so
        // looked-up words can never inflate "2 of 13 lit". A term the reader
        // accepted is the same kind of arrival.
        let context = try context()
        let adopted = try #require(HotTopics.adopt(term("world model"), context: context))
        let pack = try BuiltinPacks.aiEngineer()
        #expect(!pack.clusterOrder.contains(adopted.category),
                "“\(adopted.category)” is one of the Pack's own Clusters")
    }

    @Test("a term the map already means, in other words, is not offered")
    func meaningMatchIsNotOffered() {
        // "retrieval augmentation" and "RAG" are the same thing said twice.
        // The map has one; offering the other would be a duplicate the reader
        // has to notice is a duplicate.
        let candidates = HotTopics.candidates(
            from: [term("retrieval augmentation")], concepts: [concept("RAG")],
            vector: { name in
                ["retrieval augmentation", "rag"].contains(name) ? [1, 0, 0] : [0, 1, 0]
            })
        #expect(candidates.isEmpty)
    }

    @Test("a term merely near something on the map is still offered")
    func distantMeaningIsStillOffered() {
        // The threshold is conservative on purpose: two Concepts stored
        // separately is a smaller harm than two ideas silently merged.
        // Pointing partly the same way — nearer than a stranger, further than
        // the same idea said twice.
        let candidates = HotTopics.candidates(from: [term("world model")],
                                              concepts: [concept("RAG")],
                                              vector: { name in
                                                  name == "world model" ? [1, 1, 0] : [1, 0, 0]
                                              })
        #expect(candidates.map(\.text) == ["world model"])
    }

    @Test("the offer is bounded, because it is an invitation and not a backlog")
    func offerIsBounded() {
        let terms = (0..<10).map { term("topic \($0)") }
        #expect(HotTopics.candidates(from: terms, concepts: [], vector: strangers).count
                <= HotTopics.candidateLimit)
    }

    // MARK: Only offered

    @Test("asking what the candidates are does not add any of them")
    func candidatesAreNotAdded() throws {
        let context = try context()
        _ = HotTopics.candidates(from: [term("world model")], concepts: [], vector: strangers)
        #expect(try context.fetch(FetchDescriptor<Concept>()).isEmpty)
    }

    // MARK: Accepting one

    @Test("an accepted candidate joins the map as an ordinary Concept")
    func acceptedCandidateJoinsTheMap() throws {
        let context = try context()
        let adopted = try #require(HotTopics.adopt(term("world model"), context: context))

        #expect(adopted.name == "World Model", "named as a reader would write it")
        #expect(adopted.category == HotTopics.adoptedCluster)
        #expect(adopted.masteryLevel == 0, "new and unlit, like any Concept a Pack brings")
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 1)
    }

    @Test("accepting the same candidate twice does not make two Concepts")
    func acceptingTwiceIsIdempotent() throws {
        let context = try context()
        _ = HotTopics.adopt(term("world model"), context: context)
        _ = HotTopics.adopt(term("world model"), context: context)
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 1)
    }

    @Test("accepting something already on the map does not undo what was learned")
    func acceptingDoesNotResetMastery() throws {
        // The offer should not have shown this, but a name can also arrive by
        // another route — and setting a Concept back to unlit because a
        // headline mentioned it would take away the reader's own progress.
        let context = try context()
        let known = concept("World Model")
        known.masteryLevel = 0.7
        context.insert(known)
        try context.save()

        let adopted = try #require(HotTopics.adopt(term("world model"), context: context))
        #expect(adopted.masteryLevel == 0.7)
        #expect(adopted.category == "Foundations", "and it keeps the Cluster it was in")
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 1)
    }

    @Test("offering candidates against a full map does not hold the Feed up")
    func offerAgainstRealMapIsPrompt() throws {
        // The default path runs Apple's embedding, and the flagship Pack is 68
        // Concepts — so a lane of eight terms is up to 544 comparisons, on the
        // main actor, inside a view update.
        let context = try context()
        try PackInstaller.install(try BuiltinPacks.aiEngineer(), origin: .builtin,
                                  context: context, vector: { _ in nil })
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let terms = (0..<HotTopics.laneSize).map { term("candidate topic \($0)") }

        let started = Date.now
        _ = HotTopics.candidates(from: terms, concepts: concepts)
        let elapsed = Date.now.timeIntervalSince(started)

        #expect(elapsed < 1, "offering against \(concepts.count) Concepts took \(elapsed)s")
    }

    @Test("an accepted candidate stops being offered")
    func acceptedCandidateLeavesTheOffer() throws {
        let context = try context()
        _ = HotTopics.adopt(term("world model"), context: context)
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        #expect(HotTopics.candidates(from: [term("world model")], concepts: concepts,
                                     vector: strangers).isEmpty)
    }
}
