import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// De-duplication used to switch itself off above 500 Concepts — the size at
/// which a reader has most to lose from twins of one idea (#11).
@MainActor
@Suite("Concept de-duplication", .serialized)
struct ConceptDedupeTests {

    private func context() throws -> ModelContext {
        ModelContext(try AppSchema.inMemoryContainer())
    }

    /// Names point along their own axis unless they are one of a named pair,
    /// which point the same way — the two ways of saying one idea.
    private func vectors(sameIdea pair: Set<String> = []) -> @MainActor (String) -> [Double]? {
        { name in
            var axes = [Double](repeating: 0, count: 128)
            if pair.contains(name) {
                axes[0] = 1
                return axes
            }
            let index = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 127 }
            axes[index + 1] = 1
            return axes
        }
    }

    private func index(_ concepts: [Concept],
                       sameIdea pair: Set<String> = []) -> ConceptIndex {
        ConceptIndex(concepts, vector: vectors(sameIdea: pair))
    }

    private func filler(_ count: Int, into context: ModelContext) -> [Concept] {
        (0..<count).map { number in
            let concept = Concept(name: "Filler Concept \(number)", category: "Foundations",
                                  definition: "d")
            context.insert(concept)
            return concept
        }
    }

    // MARK: Above the old ceiling

    @Test("a near-duplicate is still merged on a map far past the old cut-off")
    func mergesAboveTheOldCeiling() throws {
        let context = try context()
        var concepts = filler(600, into: context)
        let existing = Concept(name: "Large Language Models", category: "Foundations",
                               definition: "d")
        context.insert(existing)
        concepts.append(existing)

        var index = index(concepts, sameIdea: ["large language models", "llm"])
        let matched = KnowledgeEngine.findOrCreateConcept(named: "LLM", category: "Foundations",
                                                          definition: "d", context: context,
                                                          index: &index)

        #expect(matched === existing, "601 Concepts and the twin was created anyway")
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 601)
    }

    @Test("an exact name still matches whatever the map's size")
    func exactMatchAboveTheCeiling() throws {
        let context = try context()
        var concepts = filler(600, into: context)
        let existing = Concept(name: "Attention", category: "Foundations", definition: "d")
        context.insert(existing)
        concepts.append(existing)

        var index = index(concepts)
        let matched = KnowledgeEngine.findOrCreateConcept(named: "attention", category: "X",
                                                          definition: "d", context: context,
                                                          index: &index)
        #expect(matched === existing)
    }

    // MARK: Still conservative

    @Test("two ideas that are merely near each other are still two ideas")
    func distinctConceptsAreNotCollapsed() throws {
        let context = try context()
        let existing = Concept(name: "Attention", category: "Foundations", definition: "d")
        context.insert(existing)

        var index = index([existing])
        let created = KnowledgeEngine.findOrCreateConcept(named: "Retrieval", category: "Foundations",
                                                          definition: "d", context: context,
                                                          index: &index)
        #expect(created !== existing)
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 2)
    }

    @Test("a Concept created through the index is matched by the next lookup")
    func newlyCreatedConceptJoinsTheIndex() throws {
        let context = try context()
        var index = index([], sameIdea: ["world model", "world models"])
        let first = KnowledgeEngine.findOrCreateConcept(named: "World Model", category: "Foundations",
                                                        definition: "d", context: context,
                                                        index: &index)
        let second = KnowledgeEngine.findOrCreateConcept(named: "World Models", category: "Foundations",
                                                         definition: "d", context: context,
                                                         index: &index)
        #expect(first === second, "the twin arrived in the same pass that created the original")
    }

    @Test("opposites are not one idea, judged by the embedding the app really uses")
    func realEmbeddingKeepsDistinctConceptsApart() throws {
        // Every other test here injects vectors, so none of them exercises the
        // threshold against the model that ships. These pairs are real Concept
        // names from the flagship Pack and are emphatically not each other.
        let context = try context()
        let pairs = [("Supervised Learning", "Unsupervised Learning"),
                     ("Layer Normalization", "Quantization"),
                     ("Batch Normalization", "Layer Normalization"),
                     ("Reinforcement Learning", "Reinforcement Learning from Human Feedback")]

        for (existingName, incomingName) in pairs {
            let existing = Concept(name: existingName, category: "Foundations", definition: "d")
            context.insert(existing)
            var index = ConceptIndex([existing])
            let matched = KnowledgeEngine.findOrCreateConcept(named: incomingName,
                                                              category: "Foundations",
                                                              definition: "d", context: context,
                                                              index: &index)
            #expect(matched !== existing,
                    "“\(incomingName)” was merged into “\(existingName)”, taking its history")
        }
    }

    @Test("the shipped threshold, measured rather than described")
    func realEmbeddingDistances() throws {
        // What `sameIdeaDistance` actually admits, on the scale `NLEmbedding`
        // reports. Recorded as assertions because the file's own doc comment
        // has advertised "LLM" ≈ "Large Language Models" since it was written,
        // and the model puts that pair five times outside the threshold.
        func distance(_ left: String, _ right: String) throws -> Double {
            let a = try #require(SemanticLinker.embed(left))
            let b = try #require(SemanticLinker.embed(right))
            return try #require(SemanticLinker.distance(between: a, and: b))
        }

        // Kept apart, and rightly — these are different ideas.
        #expect(try distance("supervised learning", "unsupervised learning") > ConceptIndex.sameIdeaDistance)
        #expect(try distance("batch normalization", "layer normalization") > ConceptIndex.sameIdeaDistance)

        // And kept apart, which is the limit worth knowing: at 0.25 the
        // embedding merges neither a plural nor an abbreviation, so matching by
        // meaning is doing nothing that matching by name does not already do.
        #expect(try distance("world model", "world models") > ConceptIndex.sameIdeaDistance)
        #expect(try distance("llm", "large language models") > ConceptIndex.sameIdeaDistance)
    }

    // MARK: Cost

    @Test("de-duplication against a large map does not hold analysis up")
    func dedupeAtScaleIsPrompt() throws {
        // The real embedding, and the map size the old ceiling refused to work
        // at. One Article's analysis attaches up to eight Concepts, so this is
        // eight of these back to back.
        let context = try context()
        let concepts = filler(600, into: context)
        var index = ConceptIndex(concepts)

        let started = Date.now
        for number in 0..<8 {
            _ = KnowledgeEngine.findOrCreateConcept(named: "Fresh Idea \(number)",
                                                    category: "Foundations", definition: "d",
                                                    context: context, index: &index)
        }
        let elapsed = Date.now.timeIntervalSince(started)
        #expect(elapsed < 3, "eight lookups against 600 Concepts took \(elapsed)s")

        // And the next Article in the same batch builds its own index, which is
        // where the cost used to be paid again in full. A name's meaning does
        // not change, so the second pass should be arithmetic and nothing else.
        var second = ConceptIndex(concepts)
        let secondStart = Date.now
        _ = KnowledgeEngine.findOrCreateConcept(named: "Another Fresh Idea",
                                                category: "Foundations", definition: "d",
                                                context: context, index: &second)
        let secondElapsed = Date.now.timeIntervalSince(secondStart)
        #expect(secondElapsed < elapsed / 4,
                "the second index cost \(secondElapsed)s against the first's \(elapsed)s")
    }
}
