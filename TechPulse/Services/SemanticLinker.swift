import Accelerate
import Foundation
import NaturalLanguage

/// A Concept as the linker sees it: a name, and the definition its Pack gives
/// it. Deliberately not a `Concept` — the linker is pure, so its rules can be
/// tested against vectors a test chooses rather than whatever Apple's
/// embedding happens to believe about AI jargon.
struct LinkableConcept: Sendable, Equatable {
    let name: String
    let definition: String
}

/// An undirected edge between two Concepts that mean related things.
/// `conceptA` sorts before `conceptB`, so a pair has exactly one representation.
struct SemanticEdge: Sendable, Equatable {
    let conceptA: String
    let conceptB: String
    /// 0...1 — how strongly the pair is related, for a renderer to scale by.
    let strength: Double
}

/// Derives Semantic Links from what Concepts *mean*, using the sentence
/// embedding already in the app for Concept de-duplication: on device, no
/// network, and no dependency on Apple Intelligence.
///
/// ## Why not a plain similarity threshold
///
/// Measured over the flagship Pack's own definitions, raw cosine barely
/// separates anything: the median pair scores 0.47, same-Cluster pairs 0.52,
/// and an unrelated outsider ("Sourdough Bread Baking") still manages 0.46.
/// Every English sentence is a bit like every other, and that common component
/// swamps the signal. A threshold generous enough to connect the map produced
/// 909 links over 68 Concepts with one Concept joined to 53 others — ADR-0002's
/// hairball. A threshold strict enough to stay readable left 33 of 68 Concepts
/// alone — ADR-0002's dust.
///
/// So relatedness is judged two ways at once, each doing the job it is good at:
///
/// - **Ranking** uses the *centred* vectors — each Concept's distance from the
///   Pack's own mean meaning. Subtracting what every definition shares leaves
///   what makes this Concept distinctive, and that is what ranks neighbours
///   sensibly. It has no absolute scale, so it cannot decide "related at all".
/// - **The floor** stays on the *raw* cosine, which does have an absolute
///   scale. A Concept from another field scores below everything the Pack says
///   about itself, so the floor is what refuses it.
/// - **Mutual top-K** bounds the result: an edge survives only if each Concept
///   is among the other's nearest few. This is the guarantee the readability
///   criterion actually needs — no Concept can exceed `neighbourCount` links,
///   whatever the Pack looks like — and it is what stops hub Concepts
///   attaching themselves to everything.
@MainActor
enum SemanticLinker {

    /// The most Semantic Links one Concept may keep. Measured over the two
    /// built-in Packs, 5 is where the flagship becomes a single connected map
    /// with nothing isolated, while unrelated outsiders still earn nothing.
    static let neighbourCount = 5

    /// The least raw cosine at which two Concepts count as related at all.
    /// Sits above the best score any of three deliberately foreign Concepts
    /// managed against the flagship Pack (0.46), and below the scores its own
    /// Concepts reach for each other.
    static let relatednessFloor = 0.5

    /// The embedding, and everything already computed from it. `nonisolated`,
    /// so the thread that draws the Feed is not the thread that does this.
    private nonisolated static let store = VectorStore()

    /// The distance between two names, on the scale `NLEmbedding.distance`
    /// reports — which is **not** cosine distance, however it is spelled.
    ///
    /// `NLDistanceType.cosine` returns the Euclidean distance between the
    /// L2-normalised vectors, `sqrt(2·(1 − cos))`, over 0…2. Computing `1 − cos`
    /// and keeping a threshold calibrated against the other is how a radius set
    /// at 0.25 became 0.707 — eight times wider — and merged "supervised
    /// learning" into "unsupervised learning" (#11). Measured against
    /// `NLEmbedding` over 2,211 pairs, this agrees to within 1.2e-06.
    ///
    /// Through `vDSP` rather than `zip`/`reduce`, which is the same arithmetic
    /// and not the same cost: `ConceptIndex.match` runs this once per Concept on
    /// the map, so a 600-Concept map is 600 of these per lookup and eight
    /// lookups per Article. Written by hand it was a second of main-actor work
    /// per Article — the arithmetic left over once #42 moved the embedding off.
    static func distance(between left: [Double], and right: [Double]) -> Double? {
        guard left.count == right.count, !left.isEmpty else { return nil }
        let dot = vDSP.dot(left, right)
        let magnitude = vDSP.sumOfSquares(left).squareRoot()
            * vDSP.sumOfSquares(right).squareRoot()
        guard magnitude > 0 else { return nil }
        return (2 * (1 - dot / magnitude)).squareRoot()
    }

    /// Where vectors come from unless a caller substitutes its own. Returns
    /// nil on hardware or in a language the embedding has no model for — the
    /// map is poorer, the install still works.
    ///
    /// `nonisolated` deliberately. This was main-actor isolated only because
    /// its enclosing type is, and `NLEmbedding.vector(for:)` asks for no such
    /// thing — while a caller embedding a whole map wants to be anywhere but
    /// the thread drawing the Feed. `ConceptIndex.prepared` is that caller, and
    /// this being callable off the main actor is what lets it be (#42).
    nonisolated static func embed(_ text: String) -> [Double]? {
        store.vector(for: text)
    }

    /// The Semantic Links for one Pack's Concepts, strongest first.
    ///
    /// Cost is dominated by one embedding call per Concept (~6 ms); the
    /// similarity pass is vectorised and costs a few milliseconds at Pack
    /// scale. The flagship's 68 Concepts link in ~0.4 s.
    static func link(_ concepts: [LinkableConcept],
                     vector: @Sendable (String) -> [Double]? = embed) -> [SemanticEdge] {
        // By name, so a Pack produces the same map however its file is ordered:
        // the mean below is a floating-point sum, and summing in a different
        // order can otherwise nudge a borderline neighbour in or out.
        var seen: Set<String> = []
        let ordered = concepts
            .sorted { $0.name < $1.name }
            .filter { seen.insert($0.name).inserted }

        // A Concept the embedding cannot place is left out rather than joined
        // by a zero vector, which would read as "related to everything".
        var names: [String] = []
        var raw: [[Double]] = []
        for concept in ordered {
            guard let placed = vector("\(concept.name). \(concept.definition)"),
                  !placed.isEmpty,
                  raw.first.map({ placed.count == $0.count }) ?? true
            else { continue }
            names.append(concept.name)
            raw.append(placed)
        }
        guard names.count > 1 else { return [] }

        let rawUnit = raw.map(unit)
        let centredUnit = centred(raw).map(unit)

        // Each Concept's nearest few that clear the floor, ranked by what makes
        // them distinctive. Held per row rather than as an N×N matrix so a
        // large Pack costs memory in the Concepts, not in their square.
        var neighbours: [[(index: Int, strength: Double)]] = []
        for i in names.indices {
            var best: [(index: Int, strength: Double)] = []
            for j in names.indices where j != i {
                guard vDSP.dot(rawUnit[i], rawUnit[j]) >= relatednessFloor else { continue }
                let strength = vDSP.dot(centredUnit[i], centredUnit[j])
                guard strength.isFinite else { continue }
                best.append((j, strength))
            }
            // Ties break by name, so the cap never has to pick arbitrarily.
            best.sort { $0.strength == $1.strength
                ? names[$0.index] < names[$1.index]
                : $0.strength > $1.strength }
            neighbours.append(Array(best.prefix(neighbourCount)))
        }

        // Mutual only: A keeps B only if B also keeps A. One-sided nearness is
        // how a hub Concept ends up attached to the whole Pack.
        var edges: [SemanticEdge] = []
        for i in names.indices {
            for neighbour in neighbours[i] where neighbour.index > i {
                guard neighbours[neighbour.index].contains(where: { $0.index == i }) else { continue }
                let pair = [names[i], names[neighbour.index]].sorted()
                edges.append(SemanticEdge(conceptA: pair[0], conceptB: pair[1],
                                          strength: min(1, max(0, neighbour.strength))))
            }
        }
        return edges.sorted { $0.strength == $1.strength
            ? ($0.conceptA, $0.conceptB) < ($1.conceptA, $1.conceptB)
            : $0.strength > $1.strength }
    }

    // MARK: - Vector arithmetic

    /// Scaled to length 1, so a cosine is a dot product.
    private static func unit(_ vector: [Double]) -> [Double] {
        let norm = vDSP.sumOfSquares(vector).squareRoot()
        // A zero vector has no direction — leave it, and let the caller's
        // `isFinite` check drop the pairs it takes part in.
        guard norm > 0 else { return vector }
        return vDSP.divide(vector, norm)
    }

    /// Each vector less the Pack's mean meaning — what is distinctive about
    /// this Concept, rather than what every English definition shares.
    private static func centred(_ vectors: [[Double]]) -> [[Double]] {
        guard let dimension = vectors.first?.count else { return vectors }
        var mean = [Double](repeating: 0, count: dimension)
        for vector in vectors { mean = vDSP.add(mean, vector) }
        mean = vDSP.divide(mean, Double(vectors.count))
        return vectors.map { vDSP.subtract($0, mean) }
    }
}

/// The sentence embedding, and every vector already computed from it.
///
/// Behind a lock rather than on an actor because both of its callers are real
/// and neither can become the other: `ConceptIndex.match` is synchronous and
/// has nowhere to await, while `ConceptIndex.prepared` embeds a whole map and
/// must not run on the main actor. An actor would force the first to change
/// shape; the main actor would leave the second where #42 found it.
///
/// The lock is taken once per name rather than once per batch, so embedding a
/// 600-Concept map never holds it for more than the one name in flight. What a
/// synchronous caller arriving mid-batch waits for is that one name — a few
/// milliseconds — except for the first name of the launch, which is holding
/// the lock across the several-MB model load as well.
private final class VectorStore: @unchecked Sendable {

    private let lock = NSLock()

    /// Loaded once, on whichever thread asks first. The embedding is several MB
    /// of model; building one per call would cost more than the linking does.
    /// Nil after loading is a real answer — hardware or a language with no
    /// model — so the attempt is remembered separately from its result.
    private var embedding: NLEmbedding?
    private var hasLoaded = false

    /// Vectors already computed this launch. A Concept's name does not change,
    /// and the same names are embedded over and over: de-duplication builds an
    /// index per Article analysed, so a 600-Concept map was paying 600
    /// embeddings eight times for one batch (#11).
    ///
    /// Bounded by how many distinct names the app has seen — a large map is a
    /// few megabytes of Double, against ~3.5 ms saved per hit.
    private var cache: [String: [Double]] = [:]

    func vector(for text: String) -> [Double]? {
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[text] { return known }
        if !hasLoaded {
            embedding = NLEmbedding.sentenceEmbedding(for: .english)
            hasLoaded = true
        }
        guard let computed = embedding?.vector(for: text) else { return nil }
        cache[text] = computed
        return computed
    }
}
