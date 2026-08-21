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
    private func vectors(sameIdea pair: Set<String> = []) -> @Sendable (String) -> [Double]? {
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

    /// The same names, at roughly what Apple's embedding charges for one.
    ///
    /// Injected rather than measured off `NLEmbedding`, because the question
    /// #42 asks is *which thread waits*, and answering it needs a cost that is
    /// the same on every machine the suite runs on.
    private func slowVectors(sameIdea pair: Set<String> = [],
                             costingEach seconds: TimeInterval = 0.002)
    -> @Sendable (String) -> [Double]? {
        let quick = vectors(sameIdea: pair)
        return { name in
            Thread.sleep(forTimeInterval: seconds)
            return quick(name)
        }
    }

    /// Runs `work` and reports the longest the main actor went unserved while
    /// it did — alongside how long it took, which is the number #42 is *not*
    /// about. The work still costs what it costs; the question is who waits.
    ///
    /// The heartbeat is a task on the main actor that does nothing but yield.
    /// Anything holding the main actor keeps it from being served, and the gap
    /// it then records is what a reader would have seen as a frozen Feed.
    private func mainActorStall<T>(during work: () async -> T)
    async -> (value: T, stall: TimeInterval, elapsed: TimeInterval) {
        let heartbeat = Task { @MainActor in
            var longest: TimeInterval = 0
            var last = Date.now
            while !Task.isCancelled {
                await Task.yield()
                longest = max(longest, Date.now.timeIntervalSince(last))
                last = .now
            }
            return longest
        }
        let started = Date.now
        let value = await work()
        let elapsed = Date.now.timeIntervalSince(started)
        heartbeat.cancel()
        return (value, await heartbeat.value, elapsed)
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

    @Test("a Concept created after the map was embedded is matched by the next lookup")
    func newlyCreatedConceptJoinsAPreparedIndex() async throws {
        // `prepared` computes the map's meanings up front, and a Concept
        // created part way through a pass was not on the map when it did. It
        // still has to be matchable by meaning before the pass ends: analysis
        // attaches up to eight Concepts from one Article, and the second may
        // be the first said differently.
        let context = try context()
        var index = await ConceptIndex.prepared(
            [], vector: vectors(sameIdea: ["world model", "world models"]))
        let first = KnowledgeEngine.findOrCreateConcept(named: "World Model", category: "Foundations",
                                                        definition: "d", context: context,
                                                        index: &index)
        let second = KnowledgeEngine.findOrCreateConcept(named: "World Models", category: "Foundations",
                                                         definition: "d", context: context,
                                                         index: &index)
        #expect(first === second, "the twin arrived after the map's meanings were computed")
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

    @Test("embedding a large map leaves the main actor free to draw the Feed")
    func preparingAnIndexDoesNotBlockTheMainActor() async throws {
        // The work is not the bug and is not reduced: 601 names are still
        // embedded, and no count-based cut-off dodges them the way #11's
        // ceiling did. Only the thread changes.
        let context = try context()
        var concepts = filler(600, into: context)
        let existing = Concept(name: "Large Language Models", category: "Foundations",
                               definition: "d")
        context.insert(existing)
        concepts.append(existing)

        let vector = slowVectors(sameIdea: ["large language models", "llm"])
        let (prepared, stall, elapsed) = await mainActorStall {
            await ConceptIndex.prepared(concepts, vector: vector)
        }
        var index = prepared

        #expect(elapsed > 1, "601 names cost \(elapsed)s — the map was not really embedded")
        // Measured: 47 ms held, of a 1.2 s build. Before this, the whole 1.2 s
        // was held, because the whole 1.2 s was on the main actor. The ratio is
        // the claim; the absolute bar keeps a slow machine from passing on it.
        #expect(stall < elapsed / 5,
                "the main actor was held for \(stall)s of the \(elapsed)s build")
        #expect(stall < 0.25, "the main actor was held for \(stall)s")

        // And what came back is an index, not just a promise of one: the pass
        // that used to freeze the Feed still merges what it merged before.
        let matched = KnowledgeEngine.findOrCreateConcept(named: "LLM", category: "Foundations",
                                                          definition: "d", context: context,
                                                          index: &index)
        #expect(matched === existing)
    }

    @Test("the first analysis after launch does not freeze the Feed")
    func analyzePendingDoesNotBlockTheMainActor() async throws {
        // The criterion as #42 words it, at the seam it names: `analyzePending`
        // is awaited from `FeedView.task`, so main-actor time here is time the
        // Feed is not drawn. The real embedding, and names unique to this test
        // so the launch-long memo is cold whichever order the suite runs in.
        let context = try context()
        for number in 0..<600 {
            context.insert(Concept(name: "Analysed Idea \(number)", category: "Foundations",
                                   definition: "d"))
        }
        UITestSupport.seedArticle(context: context)

        let (_, stall, elapsed) = await mainActorStall {
            await IntelligenceService.analyzePending(context: context)
        }

        #expect(elapsed > 0.5,
                "analysis cost \(elapsed)s — 600 Concepts were not really embedded")
        #expect(stall < elapsed / 5,
                "the Feed was held for \(stall)s of the \(elapsed)s analysis")
    }

    @Test("de-duplication against a large map does not hold analysis up")
    func dedupeAtScaleIsPrompt() async throws {
        // The real embedding, and the map size the old ceiling refused to work
        // at. This is the number #42 was measured from — 2.1 s for 600 names —
        // and it is now paid off the main actor rather than made smaller.
        let context = try context()
        let concepts = filler(600, into: context)

        let coldStart = Date.now
        var index = await ConceptIndex.prepared(concepts)
        let cold = Date.now.timeIntervalSince(coldStart)

        // One Article's analysis attaches up to eight Concepts, so this is
        // eight lookups back to back. What is left on the main actor is one
        // embedding of each incoming name and a scan over meanings already in
        // hand — arithmetic, not the map's worth of model.
        let started = Date.now
        for number in 0..<8 {
            _ = KnowledgeEngine.findOrCreateConcept(named: "Fresh Idea \(number)",
                                                    category: "Foundations", definition: "d",
                                                    context: context, index: &index)
        }
        let elapsed = Date.now.timeIntervalSince(started)
        // Measured: 19 ms, against the 1.2 s the map's own meanings cost. It was
        // a second of this alone until `SemanticLinker.distance` went through
        // `vDSP` — 4,800 comparisons per Article is enough to notice.
        #expect(elapsed < 0.1, "eight lookups against 600 Concepts took \(elapsed)s")

        // And the next Article in the same batch builds its own index, which is
        // where the cost used to be paid again in full. A name's meaning does
        // not change, so the second build should be arithmetic and nothing else.
        let secondStart = Date.now
        var second = await ConceptIndex.prepared(concepts)
        _ = KnowledgeEngine.findOrCreateConcept(named: "Another Fresh Idea",
                                                category: "Foundations", definition: "d",
                                                context: context, index: &second)
        let secondElapsed = Date.now.timeIntervalSince(secondStart)
        #expect(secondElapsed < cold / 8,
                "the second index cost \(secondElapsed)s against the first's \(cold)s")
    }
}
