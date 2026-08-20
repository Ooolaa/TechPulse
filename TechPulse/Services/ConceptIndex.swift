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
@MainActor
struct ConceptIndex {

    /// Lowercased name → Concept.
    private(set) var concepts: [String: Concept]
    /// Lowercased name → its meaning, filled the first time it is needed.
    private var vectors: [String: [Double]] = [:]
    private let vector: @MainActor (String) -> [Double]?

    /// The distance below which two names are the same idea said twice.
    ///
    /// Conservative on purpose, and unchanged by this work: merging two
    /// distinct Concepts destroys a reader's history, where a near-duplicate
    /// only clutters. The ceiling was the bug; the threshold was never it — and
    /// keeping it meaning what it meant is why the distance is computed on
    /// `NLEmbedding`'s own scale rather than on plain cosine.
    static let sameIdeaDistance = 0.25

    init(_ concepts: [Concept],
         vector: @escaping @MainActor (String) -> [Double]? = SemanticLinker.embed) {
        self.concepts = Dictionary(concepts.map { ($0.name.lowercased(), $0) },
                                   uniquingKeysWith: { first, _ in first })
        self.vector = vector
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
