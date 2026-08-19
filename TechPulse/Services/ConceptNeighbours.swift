import Foundation

/// The two undirected edge kinds of ADR-0002, as the sheet reads them: a pair
/// of Concept names and how strongly the edge joins them. `ConceptLink` adds a
/// reading count and `SemanticLink` does not, and neither difference matters to
/// a caller that only wants to know who the neighbours are.
protocol UndirectedConceptEdge {
    var conceptA: String { get }
    var conceptB: String { get }
    var strength: Double { get }
}

extension ConceptLink: UndirectedConceptEdge {}
extension SemanticLink: UndirectedConceptEdge {}

/// The Concepts a sheet offers as jumps from one Concept, grouped by the claim
/// that joins them.
///
/// ADR-0002 stores three kinds of edge and draws each differently, and the two
/// undirected kinds make different claims: a Concept you *read together* with
/// this one is a record of your own reading, where a Concept that merely
/// *means* something similar was computed from the Pack's definitions at
/// install. Flattening them into one row would assert the first about pairs
/// that only earned the second.
///
/// Reading Semantic Links here is what makes the sheet work on day one. The
/// map already draws them (`FullMapView`), so before this the map showed a
/// Concept joined to its neighbours and the sheet — where a reader actually
/// goes to follow a connection — said nothing about them (#33).
@MainActor
struct ConceptNeighbours {
    /// Met in the same reading — Co-read Links.
    let readTogether: [Concept]
    /// Related in meaning — Semantic Links, present from install.
    let related: [Concept]

    var isEmpty: Bool { readTogether.isEmpty && related.isEmpty }

    /// How many chips the sheet's row holds before it starts pushing the
    /// Article list down. Each kind is guaranteed up to half of them, so a
    /// well-read Concept still shows what it *means* alongside what it was read
    /// with; slots a kind cannot fill go to the other, so the row is never
    /// short while a neighbour is waiting to be shown.
    static let chipCount = 6

    static func around(_ concept: String, concepts: [Concept],
                       coread: [ConceptLink], semantic: [SemanticLink]) -> ConceptNeighbours {
        let byName = Dictionary(concepts.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        /// Strongest link to each neighbour. A pair can be linked more than
        /// once — a rebuild that has not yet swept the old row, a Concept
        /// renamed into an existing pair — and the strongest is the honest one.
        func neighbours(_ links: [any UndirectedConceptEdge]) -> [(Concept, Double)] {
            let strongest = links.reduce(into: [String: Double]()) { acc, link in
                let other: String
                switch concept {
                case link.conceptA: other = link.conceptB
                case link.conceptB: other = link.conceptA
                default: return
                }
                guard other != concept else { return }
                acc[other] = max(acc[other] ?? 0, link.strength)
            }
            // A link can name a Concept this store doesn't have — a retired
            // Pack's edge, a map regenerated elsewhere. A chip with nothing to
            // push is worse than one chip fewer.
            return strongest.compactMap { name, strength in
                byName[name].map { ($0, strength) }
            }
            // Name breaks ties so the row doesn't reshuffle between renders.
            .sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }
        }

        let read = neighbours(coread)
        let readNames = Set(read.map(\.0.name))
        // Having read two Concepts together is the stronger claim, so a pair
        // that earned both kinds is claimed by the reading and appears once.
        let means = neighbours(semantic).filter { !readNames.contains($0.0.name) }

        // Half the row is reserved for whichever kind has fewer to show, and
        // only for as many as it actually has — a Concept with one Co-read
        // neighbour and six Semantic ones fills the row rather than showing
        // four chips and a gap.
        let readSlots = min(read.count, chipCount - min(means.count, chipCount / 2))
        let meanSlots = min(means.count, chipCount - readSlots)
        return ConceptNeighbours(readTogether: read.prefix(readSlots).map(\.0),
                                 related: means.prefix(meanSlots).map(\.0))
    }
}
