import Foundation

/// The map, as the de-duplicator needs to see it: every Concept by name, and
/// every name's meaning, computed once.
///
/// This exists because computing it *twice* is what put a ceiling on
/// de-duplication. `NLEmbedding.distance(between:and:)` embeds both of its
/// arguments on every call, so matching one name against a 500-Concept map cost
/// a thousand embeddings — and analysis attaches up to eight Concepts per
/// Article. `KnowledgeEngine` bought its way out with `guard cache.count < 500`,
/// which switched merging off at exactly the size where a reader has most to
/// lose from twins of one idea (#11).
///
/// Held once per pass and passed `inout`, so a Concept created early in a batch
/// is matchable by the end of it — the same contract the plain dictionary had.
///
/// Computing it *once* still costs what it costs: a 600-Concept map is two
/// seconds of embedding, and paying that on the main actor froze the Feed for
/// as long (#42). So the map's meanings are computed by `prepared`, away from
/// the main actor, and `match` stays synchronous over a table that is already
/// filled in.
@MainActor
struct ConceptIndex {

    /// Lowercased name → Concept.
    private(set) var concepts: [String: Concept]
    /// `ConceptMatch.fold` of each name → Concept: the same table again, keyed
    /// by spelling folded to case, separators and English plurals. Free to
    /// build and free to consult, and it catches what the embedding measurably
    /// cannot — see `sameIdeaDistance`.
    private var folded: [String: Concept] = [:]
    /// Lowercased name → its meaning. Filled for the whole map by `prepared`,
    /// and one name at a time after that, for names the map did not have when
    /// it was built: the incoming name of a lookup, and Concepts created part
    /// way through a pass.
    private var vectors: [String: [Double]] = [:]
    /// `@Sendable` rather than main-actor isolated, because `prepared` calls it
    /// off the main actor — which is the whole of the fix for #42.
    private let vector: @Sendable (String) -> [Double]?

    /// The distance below which two names are the same idea said twice, on the
    /// scale `SemanticLinker.distance` reports — which is `NLEmbedding`'s own
    /// scale, over 0…2, and not plain cosine.
    ///
    /// ## Where 0.50 comes from
    ///
    /// Measured over the 120 Concept names of the two built-in Packs — every
    /// one of their 7,140 pairs — against restatements of those same names
    /// written the way an Article's analysis says them (#41). Only the
    /// restatements `match` has to reach *by meaning* are listed: the ones a
    /// fold of spelling already has are below, and their distance decides
    /// nothing.
    ///
    /// | what is left for the distance to merge | measured |
    /// | --- | --- |
    /// | "&" spelled "and": `Identity & Access Management` | 0.24–0.30 |
    /// | one letter of spelling: `Defence`, `Modelling`, `Quantisation` | 0.33–0.38 |
    /// | an article in front: `The Transformer Architecture` | 0.392 |
    /// | **nothing the fold does not already have** | **0.39–0.62** |
    /// | closest two distinct names ship: `Vision Language Models` ~ `Reasoning Models` | 0.620 |
    /// | `Container Security` ~ `Supply Chain Security` | 0.626 |
    /// | `Batch Normalization` ~ `Layer Normalization` | 0.635 |
    /// | `Supervised Learning` ~ `Unsupervised Learning` | 0.691 |
    ///
    /// 0.50 is the middle of that empty stretch: 0.11 above the widest
    /// restatement the distance is asked to carry, 0.12 below the closest pair
    /// of distinct names either built-in Pack contains. Both margins matter,
    /// and not equally — a merge is destructive, because the incoming Concept
    /// is never created and Mastery, Lit state and `LearningEvent` history
    /// consolidate onto whichever name arrived first, where a near-duplicate
    /// only clutters. `ConceptDedupeTests.builtinPacksHoldNoPairInsideTheThreshold`
    /// measures the lower margin over every pair rather than restating it.
    ///
    /// It replaces 0.25, which admitted nothing at all: not a plural (`world
    /// model` ~ `world models`, 0.449), and not "LLM" ≈ "Large Language
    /// Models" (1.26), the pair the doc comment on `findOrCreateConcept`
    /// advertised from the day it was written. Below the old 500-Concept
    /// ceiling and above it, matching by meaning was doing nothing matching by
    /// name did not already do (#11, #41).
    ///
    /// ## What it still cannot reach
    ///
    /// **Abbreviations**, at any safe threshold: `llm` ~ `large language
    /// models` is 1.26 and `rag` ~ `retrieval augmented generation` is 1.32 —
    /// further apart than two unrelated ideas, so widening cannot have them and
    /// something other than a sentence embedding would be needed.
    ///
    /// **A plural of a one-word name**: `Benchmarks` ~ `Benchmark` is 0.67 and
    /// `Guardrails` ~ `Guardrail` is 0.75, because one word of a one-word name
    /// is the whole of its meaning. Those land among the distinct pairs, which
    /// is why `match` folds spelling before it asks about meaning — the fold
    /// Explain already uses (ADR-0007) has them, and the plurals and separators
    /// between 0.33 and 0.57 with them, for nothing.
    ///
    /// **A one-word name spelled another way**: `Quantisation` merges at 0.377,
    /// but `Tokenisation` is 0.578 and folds differently, so it does not.
    static let sameIdeaDistance = 0.50

    /// An index that has not embedded anything yet, and will do it on the main
    /// actor when a lookup first needs meaning. Cheap to build and expensive to
    /// use: on a 600-Concept map the first inexact lookup pays for the whole map
    /// at once, which is two seconds with nothing to interrupt it (#42).
    ///
    /// Fine for a handful of Concepts, which is what tests hold. Production
    /// builds through `prepared`.
    init(_ concepts: [Concept],
         vector: @escaping @Sendable (String) -> [Double]? = SemanticLinker.embed) {
        self.concepts = Dictionary(concepts.map { ($0.name.lowercased(), $0) },
                                   uniquingKeysWith: { first, _ in first })
        // By name where two Concepts fold together, so which of them answers a
        // lookup does not depend on what order a fetch happened to return.
        self.folded = Dictionary(self.concepts.values.map { (ConceptMatch.fold($0.name), $0) },
                                 uniquingKeysWith: { $0.name <= $1.name ? $0 : $1 })
        self.vector = vector
    }

    /// The same index with the map's meanings already computed — the whole of
    /// the cost, paid once, off the main actor.
    ///
    /// The work itself is unchanged and unconditional: no count-based cut-off
    /// comes back, because switching de-duplication off above 500 Concepts is
    /// what #11 was. What changes is the thread. `analyzePending` is awaited
    /// from `FeedView.task`, so the first Article analysed after launch used to
    /// hold the Feed for as long as embedding the map took.
    ///
    /// Names the map does not have — the incoming name of a lookup, a Concept
    /// created earlier in this pass — are still embedded by `match`, one at a
    /// time, on whichever actor is asking. That is a single embedding each, not
    /// the map's worth.
    ///
    /// The map is embedded whether or not the lookups turn out to need it. On
    /// the analysis path they do: an Article attaches up to eight Concepts and
    /// one of them missing an exact name is near-certain. On the paths where a
    /// single exact name might have cost nothing at all — `HotTopics.adopt`,
    /// Explain — `SemanticLinker.embed` memoises across the launch, and the
    /// offer that produced the tap has usually embedded the map already.
    static func prepared(_ concepts: [Concept],
                         vector: @escaping @Sendable (String) -> [Double]? = SemanticLinker.embed)
    async -> ConceptIndex {
        var index = ConceptIndex(concepts, vector: vector)
        index.vectors = await meanings(of: Array(index.concepts.keys), from: vector)
        return index
    }

    /// Embeds a batch of names away from whoever asked.
    ///
    /// `nonisolated` and `async`, so calling it from the main actor leaves it:
    /// under Swift 6.0 a nonisolated async function runs on the generic
    /// executor, and the caller suspends rather than spinning. Handing back a
    /// whole table rather than making callers await a name at a time is what
    /// keeps `match` synchronous.
    ///
    /// That is a language rule, not a promise this code makes, and adopting
    /// `nonisolated(nonsending)` as the default would hand this loop back to
    /// the caller's actor and #42 with it. The test that would notice is
    /// `preparingAnIndexDoesNotBlockTheMainActor`, which is why it measures
    /// main-actor time rather than how long the build took.
    private nonisolated static func meanings(
        of names: [String],
        from vector: @escaping @Sendable (String) -> [Double]?
    ) async -> [String: [Double]] {
        var meanings: [String: [Double]] = [:]
        meanings.reserveCapacity(names.count)
        // A name the embedding cannot place is remembered as empty rather than
        // left out, so it is not attempted again for the life of the index —
        // the same bargain `meaning(of:)` strikes.
        for name in names { meanings[name] = vector(name) ?? [] }
        return meanings
    }

    /// The Concept already standing for this name: spelled it, spelled it
    /// another way, or meaning it.
    ///
    /// Spelling is asked first and separately, because the two halves fail in
    /// different places and neither covers the other. The fold has plurals of
    /// one-word names, which sit further apart under the embedding than two
    /// distinct ideas do; the embedding has "&" for "and", and a letter of
    /// spelling inside a longer name, which no fold reaches. A name spelled
    /// exactly as an existing Concept still wins over one that merely folds
    /// the same, so the order here only ever widens what matches.
    mutating func match(_ rawName: String) -> Concept? {
        let name = rawName.lowercased()
        if let exact = concepts[name] { return exact }

        let key = ConceptMatch.fold(rawName)
        if !key.isEmpty, let spelled = folded[key] { return spelled }

        guard let incoming = meaning(of: name), !incoming.isEmpty else { return nil }
        var best: (concept: Concept, distance: Double)?
        for (existingName, concept) in concepts {
            guard let existing = meaning(of: existingName),
                  let distance = SemanticLinker.distance(between: incoming, and: existing),
                  distance < Self.sameIdeaDistance,
                  distance < (best?.distance ?? .infinity)
                      || (distance == best?.distance && concept.name < best!.concept.name)
            else { continue }
            best = (concept, distance)
        }
        return best?.concept
    }

    /// Records a Concept the caller has just created, so the rest of the pass
    /// can match against it.
    mutating func insert(_ concept: Concept) {
        concepts[concept.name.lowercased()] = concept
        // Overwrites, like the line above it. On the analysis path there is
        // nothing to overwrite — a Concept reaches `insert` because `match`
        // found nothing, and a fold key already taken is exactly what `match`
        // looks under. Two cases sit outside that: a name folding to the empty
        // key, which `match` skips, and `HotTopics.adopt` catching its index up
        // with Concepts a concurrent pass created. Last writer wins in both,
        // and neither is consulted under a key it did not put there.
        folded[ConceptMatch.fold(concept.name)] = concept
    }

    private mutating func meaning(of name: String) -> [Double]? {
        if let known = vectors[name] { return known }
        let computed = vector(name) ?? []
        vectors[name] = computed
        return computed
    }

}
