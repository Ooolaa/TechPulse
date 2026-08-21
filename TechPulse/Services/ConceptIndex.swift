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
    /// Lowercased name → its meaning. Filled for the whole map by `prepared`,
    /// and one name at a time after that, for names the map did not have when
    /// it was built: the incoming name of a lookup, and Concepts created part
    /// way through a pass.
    private var vectors: [String: [Double]] = [:]
    /// `@Sendable` rather than main-actor isolated, because `prepared` calls it
    /// off the main actor — which is the whole of the fix for #42.
    private let vector: @Sendable (String) -> [Double]?

    /// The distance below which two names are the same idea said twice.
    ///
    /// Conservative on purpose, and unchanged by this work: merging two
    /// distinct Concepts destroys a reader's history, where a near-duplicate
    /// only clutters. The ceiling was the bug; the threshold was never it — and
    /// keeping it meaning what it meant is why the distance is computed on
    /// `NLEmbedding`'s own scale rather than on plain cosine.
    static let sameIdeaDistance = 0.25

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

    /// The Concept already standing for this name, by spelling or by meaning.
    mutating func match(_ rawName: String) -> Concept? {
        let name = rawName.lowercased()
        if let exact = concepts[name] { return exact }

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
    }

    private mutating func meaning(of name: String) -> [Double]? {
        if let known = vectors[name] { return known }
        let computed = vector(name) ?? []
        vectors[name] = computed
        return computed
    }

}
