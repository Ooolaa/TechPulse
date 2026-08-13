import Foundation

/// Two Concepts the reader has met together, and how strongly that reading
/// record ties them. `conceptA` sorts before `conceptB`, so a pair has exactly
/// one representation.
struct CoreadEdge: Sendable, Equatable {
    let conceptA: String
    let conceptB: String
    /// How many readings joined the two — the raw observation behind `strength`.
    let readings: Int
    /// 0...1 — strength of association, for a renderer to scale by.
    let strength: Double
}

/// Turns readings into Co-read Links.
///
/// A *reading* is a group of Concepts met together: an article's Concepts, or
/// the Concepts one project used. The scorer is pure — it takes the groups and
/// returns the edges, so none of these rules need a store to test.
///
/// ## What was wrong with counting
///
/// ADR-0002 recorded three failures of the raw pairwise count this replaces,
/// and each maps to a rule here:
///
/// - **Every pair was linked**, so an 8-Concept article emitted 28 edges and
///   density grew quadratically with how rich the article was. Pairs now form
///   among a reading's `principalConcepts` only.
/// - **`weight` incremented forever and was never normalised**, so a Concept
///   that appears in everything ended up strongly linked to everything.
///   Strength is now an *association*: how often two Concepts appear together
///   against how often they appear at all. A hub scores low against each
///   individual partner precisely because it partners with everyone.
/// - **The weight was invisible anyway** — the old line width saturated at
///   weight ≈ 4.4, so "read together twice" and "read together twenty times"
///   drew identically. Strength keeps climbing, which is what #10 renders.
enum CoreadScoring {

    /// How many of a reading's Concepts pair up. An article's later Concepts
    /// are still attached to it and still light up — they just don't assert
    /// that everything in a long list was read *together*.
    static let principalConcepts = 5

    /// The most Co-read Links one Concept keeps.
    static let neighbourCount = 6

    /// Below this, two Concepts have met but have no association worth drawing.
    static let strengthFloor = 0.15

    /// The Co-read Links these readings support, strongest first.
    static func score(_ groups: [[String]]) -> [CoreadEdge] {
        // Appearances and co-appearances are counted over the same principal
        // Concepts that form pairs, or the association would be measured
        // against a denominator its numerator never had a chance at.
        var appearances: [String: Int] = [:]
        var together: [String: Int] = [:]
        var names: [String: (String, String)] = [:]

        for group in groups {
            var seen: Set<String> = []
            let principals = group.filter { seen.insert($0).inserted }
                .prefix(principalConcepts)
            for name in principals { appearances[name, default: 0] += 1 }
            for (offset, first) in principals.enumerated() {
                for second in principals.dropFirst(offset + 1) {
                    let pair = [first, second].sorted()
                    let key = "\(pair[0])\u{0}\(pair[1])"
                    together[key, default: 0] += 1
                    names[key] = (pair[0], pair[1])
                }
            }
        }

        var candidates: [CoreadEdge] = []
        for (key, readings) in together {
            guard let (a, b) = names[key],
                  let countA = appearances[a], let countB = appearances[b]
            else { continue }
            // Dice: how much of the two Concepts' reading lives is shared.
            // A hub with 60 appearances and one shared reading scores near
            // zero however many partners it has.
            let dice = 2 * Double(readings) / Double(countA + countB)
            // Tempered by how much reading is actually behind it, so a single
            // chance pairing cannot claim the same certainty as a habit. This
            // is also what keeps strong and very strong apart as reading piles
            // up, rather than saturating.
            let support = Double(readings) / Double(readings + 1)
            let strength = dice * support
            guard strength >= strengthFloor else { continue }
            candidates.append(CoreadEdge(conceptA: a, conceptB: b,
                                         readings: readings, strength: strength))
        }

        return prunedToStrongest(candidates)
    }

    /// Each Concept keeps only its strongest few, and both ends have to agree.
    ///
    /// Mutual rather than one-sided for the same reason `SemanticLinker` is:
    /// a Concept that everything else considers a near neighbour is exactly
    /// how a hub reassembles itself out of other Concepts' shortlists.
    private static func prunedToStrongest(_ edges: [CoreadEdge]) -> [CoreadEdge] {
        var byConcept: [String: [CoreadEdge]] = [:]
        for edge in edges {
            byConcept[edge.conceptA, default: []].append(edge)
            byConcept[edge.conceptB, default: []].append(edge)
        }
        // Ties break by name, so the cap never has to choose arbitrarily.
        let strongest = byConcept.mapValues { edges in
            Set(edges.sorted(by: isStronger)
                .prefix(neighbourCount)
                .map { "\($0.conceptA)\u{0}\($0.conceptB)" })
        }
        return edges
            .filter {
                let key = "\($0.conceptA)\u{0}\($0.conceptB)"
                return strongest[$0.conceptA]?.contains(key) == true
                    && strongest[$0.conceptB]?.contains(key) == true
            }
            .sorted(by: isStronger)
    }

    private static func isStronger(_ first: CoreadEdge, _ second: CoreadEdge) -> Bool {
        first.strength == second.strength
            ? (first.conceptA, first.conceptB) < (second.conceptA, second.conceptB)
            : first.strength > second.strength
    }
}
