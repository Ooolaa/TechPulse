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
        // The pair used to be "LLM" ~ "Large Language Models", which the model
        // that ships puts 1.26 apart — further than two unrelated ideas — so
        // the fixture was asserting a merge the app now says in three places
        // it cannot make. Two names for one idea that the fold cannot fold
        // together says what this test is about without the fiction.
        let context = try context()
        var concepts = filler(600, into: context)
        let existing = Concept(name: "World Model", category: "Foundations",
                               definition: "d")
        context.insert(existing)
        concepts.append(existing)

        var index = index(concepts, sameIdea: ["world model", "environment simulator"])
        let matched = KnowledgeEngine.findOrCreateConcept(named: "Environment Simulator",
                                                          category: "Foundations",
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
        // Named so the two spellings have nothing in common, which is what
        // keeps this on the path it is about: a twin caught by *meaning*, not
        // one the spelling fold would have caught whatever the index held.
        let context = try context()
        var index = index([], sameIdea: ["world model", "environment simulator"])
        let first = KnowledgeEngine.findOrCreateConcept(named: "World Model", category: "Foundations",
                                                        definition: "d", context: context,
                                                        index: &index)
        let second = KnowledgeEngine.findOrCreateConcept(named: "Environment Simulator",
                                                         category: "Foundations",
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
            [], vector: vectors(sameIdea: ["world model", "environment simulator"]))
        let first = KnowledgeEngine.findOrCreateConcept(named: "World Model", category: "Foundations",
                                                        definition: "d", context: context,
                                                        index: &index)
        let second = KnowledgeEngine.findOrCreateConcept(named: "Environment Simulator",
                                                         category: "Foundations",
                                                         definition: "d", context: context,
                                                         index: &index)
        #expect(first === second, "the twin arrived after the map's meanings were computed")
    }

    @Test("opposites are not one idea, judged by the embedding the app really uses")
    func realEmbeddingKeepsDistinctConceptsApart() throws {
        // Every other test here injects vectors, so none of them exercises the
        // threshold against the model that ships. These pairs are real Concept
        // names from the built-in Packs and are emphatically not each other.
        //
        // The first four are the closest distinct pairs the calibration for #41
        // turned up over all 7,140 pairs of the two built-in Packs — 0.62 to
        // 0.64, which is what the threshold has to stay under. The rest are
        // pairs chosen by hand for being the kind of near-miss a merge would
        // be worst on.
        let context = try context()
        let pairs = [("Vision Language Models", "Reasoning Models"),
                     ("Container Security", "Supply Chain Security"),
                     ("Prompt Engineering", "Detection Engineering"),
                     ("Data Leakage", "Data Poisoning"),
                     ("Container Security", "Kubernetes Security"),
                     ("Prompt Engineering", "Context Engineering"),
                     ("Supervised Learning", "Unsupervised Learning"),
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

    @Test("the threshold sits in the gap the calibration measured")
    func theCalibrationTheThresholdCameFrom() throws {
        // Where 0.50 comes from, on the scale `NLEmbedding` reports. Recorded
        // as assertions rather than as prose because the previous threshold was
        // prose — 0.25, with a doc comment claiming it merged "LLM" into
        // "Large Language Models", which the model puts five times outside it.
        func distance(_ left: String, _ right: String) throws -> Double {
            let a = try #require(SemanticLinker.embed(left.lowercased()))
            let b = try #require(SemanticLinker.embed(right.lowercased()))
            return try #require(SemanticLinker.distance(between: a, and: b))
        }

        // The band the distance is asked to carry is only the restatements the
        // fold does not already have, so the widest of those is what the
        // threshold has to clear — not `Red-Teaming` ~ `Red Teaming` at 0.545,
        // which merges on spelling whatever the number says.
        let widestByMeaning = try distance("Transformer Architecture",
                                           "The Transformer Architecture")       // 0.392
        let nearestDistinct = try distance("Vision Language Models",
                                           "Reasoning Models")                   // 0.620
        #expect(widestByMeaning < ConceptIndex.sameIdeaDistance)
        #expect(nearestDistinct > ConceptIndex.sameIdeaDistance)
        // Both margins are real, and the empty stretch between them is where
        // the line went: nothing the fold does not already have was measured
        // inside it.
        #expect(ConceptIndex.sameIdeaDistance - widestByMeaning > 0.1)
        #expect(nearestDistinct - ConceptIndex.sameIdeaDistance > 0.1)

        // What the distance alone cannot reach, stated rather than implied.
        //
        // A plural of a one-word name is a bigger share of that name's meaning
        // than a plural of a three-word one, so it lands among the distinct
        // pairs and no threshold can have it. `ConceptMatch.fold` is what
        // merges these, on spelling.
        #expect(try distance("Benchmarks", "Benchmark") > ConceptIndex.sameIdeaDistance)
        #expect(try distance("Guardrails", "Guardrail") > ConceptIndex.sameIdeaDistance)
        #expect(ConceptMatch.fold("Benchmarks") == ConceptMatch.fold("Benchmark"))
        #expect(ConceptMatch.fold("Guardrails") == ConceptMatch.fold("Guardrail"))

        // A spelling neither half catches: one letter inside a one-word name
        // moves it as far as a different idea would, and folding it would be a
        // guess about English rather than about separators and plurals.
        #expect(try distance("Tokenization", "Tokenisation") > ConceptIndex.sameIdeaDistance)
        #expect(ConceptMatch.fold("Tokenization") != ConceptMatch.fold("Tokenisation"))

        // And abbreviations, which are out of reach at any safe threshold:
        // both of these are further apart than two unrelated ideas, so an
        // embedding is the wrong instrument for them (#41).
        #expect(try distance("LLM", "Large Language Models") > 1)
        #expect(try distance("RAG", "Retrieval Augmented Generation") > 1)
    }

    @Test("no two names in the built-in Packs are one idea")
    func builtinPacksHoldNoPairInsideTheThreshold() throws {
        // The claim the calibration actually makes, over the whole corpus it
        // was derived from rather than the handful of pairs quoted from it:
        // 120 Concept names across both built-in Packs, every pair of them, on
        // both halves of the match. A Pack whose own names merge into each
        // other would lose a reader's history on the day it was installed.
        var names: [String] = []
        var seen: Set<String> = []
        for builtin in BuiltinPacks.all {
            for concept in builtin.pack.concepts
            where seen.insert(concept.name.lowercased()).inserted {
                names.append(concept.name)
            }
        }
        #expect(names.count > 100, "both built-in Packs should be in this corpus")

        var folded: [String: String] = [:]
        for name in names {
            let key = ConceptMatch.fold(name)
            #expect(folded[key] == nil,
                    "“\(name)” folds onto “\(folded[key] ?? "")”")
            folded[key] = name
        }

        let vectors = try names.map { try #require(SemanticLinker.embed($0.lowercased())) }
        var nearest = (distance: Double.infinity, pair: ("", ""))
        for i in names.indices {
            for j in names.indices where j > i {
                let measured = try #require(SemanticLinker.distance(between: vectors[i],
                                                                    and: vectors[j]))
                if measured < nearest.distance {
                    nearest = (measured, (names[i], names[j]))
                }
            }
        }
        // Measured: 0.620, for "Vision Language Models" ~ "Reasoning Models".
        #expect(nearest.distance > ConceptIndex.sameIdeaDistance,
                "“\(nearest.pair.0)” ~ “\(nearest.pair.1)” at \(nearest.distance)")
    }

    @Test("one idea said twice is merged, judged by the embedding the app really uses")
    func realEmbeddingMergesRestatements() throws {
        // The other half of #41, and the half that was doing nothing: at 0.25
        // matching by meaning merged nothing matching by name did not already
        // merge. Real Concept names from the built-in Packs, against the way an
        // Article's analysis would have said the same thing.
        //
        // Both routes are here on purpose and the test does not say which is
        // which: what a reader is promised is that a restatement of a Concept
        // they already have does not become a second dot on their map.
        let context = try context()
        let pairs = [("World Models", "World Model"),
                     ("Vector Databases", "Vector Database"),
                     ("Reasoning Models", "Reasoning Model"),
                     ("Identity & Access Management", "Identity and Access Management"),
                     ("Probability & Statistics", "Probability and Statistics"),
                     ("Computer-Use Agents", "Computer Use Agents"),
                     ("Threat Modeling", "Threat Modelling"),
                     ("Quantization", "Quantisation"),
                     ("Prompt Injection Defense", "Prompt Injection Defence"),
                     ("Benchmarks", "Benchmark"),
                     ("Embeddings", "Embedding"),
                     ("Guardrails", "Guardrail"),
                     ("Eval Suites", "Eval Suite"),
                     ("Fine-Tuning", "Fine Tuning"),
                     ("Red-Teaming", "Red Teaming"),
                     ("KV-Cache", "KV Cache"),
                     ("LLM-as-Judge", "LLM as Judge")]

        for (existingName, incomingName) in pairs {
            let existing = Concept(name: existingName, category: "Foundations", definition: "d")
            context.insert(existing)
            var index = ConceptIndex([existing])
            let matched = KnowledgeEngine.findOrCreateConcept(named: incomingName,
                                                              category: "Foundations",
                                                              definition: "d", context: context,
                                                              index: &index)
            #expect(matched === existing,
                    "“\(incomingName)” became a second dot beside “\(existingName)”")
        }
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

        // One embedding on the main actor before the clock starts, and not
        // one of the eight.
        //
        // The first embedding that follows the map's own batch costs 60–130 ms
        // where the next costs 2. It is charged once, and to whichever call
        // happens to be next — which, with the eight lookups run immediately
        // after `prepared`, was the first of them: measured per lookup, the
        // eight were 104, 14, 2.3, 2.3, 2.3, 2.3, 2.4, 2.4 ms. Timing it as
        // though it were the cost of a lookup is what #59 measured, and it is
        // why this assertion passes behind the rest of the suite and fails
        // alone: whether the charge lands inside the clock depends only on
        // what ran before it in the same process.
        //
        // The claim is about what one Article costs, so the charge is paid
        // here — where a launch has long since paid it by the time a second
        // Article is analysed. That the *first* analysis after launch pays it
        // on the main actor is a real cost and a different one, and the test
        // that owns it measures main-actor time rather than wall clock:
        // `analyzePendingDoesNotBlockTheMainActor`.
        _ = SemanticLinker.embed("not a name on any map")

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
        // Measured: 18 ms — 2.3 ms a lookup, of which the incoming name's
        // embedding is 1.9 and the 600-way scan is 0.4. It was a second of
        // this alone until `SemanticLinker.distance` went through `vDSP` —
        // 4,800 comparisons per Article is enough to notice, and they cost
        // 2.9 ms measured on their own.
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
