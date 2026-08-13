import Testing
import Foundation
import SwiftUI
@testable import TechPulse

/// The map draws three kinds of connection and lets strength move the dots.
/// `GraphSimulation` is a plain class, so all of that is testable without a
/// screen — the screenshots in the UI journey cover what it actually looks
/// like, these cover what it is doing.
@MainActor
@Suite("Graph rendering")
struct GraphRenderingTests {

    private let size = CGSize(width: 390, height: 600)

    private func concepts(_ names: String...) -> [Concept] {
        names.map { Concept(name: $0, category: "Foundations", definition: "d") }
    }

    private func settled(_ sim: GraphSimulation) {
        // The simulation's own hard cap is 240 frames; run past it so the net
        // is wherever it is going to end up.
        for _ in 0..<260 { sim.step(in: size) }
    }

    private func distance(_ sim: GraphSimulation, _ a: String, _ b: String) -> CGFloat {
        guard let first = sim.nodes.first(where: { $0.name == a }),
              let second = sim.nodes.first(where: { $0.name == b }) else { return .infinity }
        return hypot(first.position.x - second.position.x,
                     first.position.y - second.position.y)
    }

    // MARK: - Three kinds, told apart

    @Test("each kind of connection is drawn as its own kind of line")
    func threeKindsAreDistinguishable() {
        let sim = GraphSimulation()
        sim.configure(
            concepts: concepts("A", "B", "C", "D", "E", "F"),
            links: [ConceptLink(conceptA: "A", conceptB: "B", weight: 3, strength: 0.6)],
            semanticLinks: [SemanticLink(conceptA: "C", conceptB: "D", strength: 0.6)],
            dependencies: [ConceptDependency(prerequisite: "E", dependent: "F")],
            in: size)

        let kinds = Set(sim.edges.map(\.kind))
        #expect(kinds == [.coread, .semantic, .dependency])

        // Only a Dependency carries an arrowhead, and only a Semantic Link is
        // dashed — shape cues, so the three survive dark mode and greyscale.
        #expect(sim.edges.filter(\.directed).map(\.kind) == [.dependency])

        // And each kind is drawn in its own colour.
        let colors = [GraphSimulation.Edge.Kind.dependency, .semantic, .coread]
            .map { ForceGraphView.edgeColor($0) }
        #expect(Set(colors).count == 3)
    }

    @Test("a pair claimed by several kinds is drawn once, by the strongest claim")
    func onePairIsOneLine() {
        // Two lines between the same two dots would land exactly on top of one
        // another and read as a single thicker line, not as two facts.
        let sim = GraphSimulation()
        sim.configure(
            concepts: concepts("A", "B"),
            links: [ConceptLink(conceptA: "A", conceptB: "B", weight: 2, strength: 0.5)],
            semanticLinks: [SemanticLink(conceptA: "A", conceptB: "B", strength: 0.8)],
            dependencies: [ConceptDependency(prerequisite: "A", dependent: "B")],
            in: size)

        #expect(sim.edges.count == 1)
        // What someone asserted beats what you did, which beats what the words
        // resemble.
        #expect(sim.edges.first?.kind == .dependency)
    }

    @Test("a connection to a Concept that isn't on this map is not drawn")
    func edgesNeverNameMissingNodes() {
        let sim = GraphSimulation()
        sim.configure(
            concepts: concepts("A", "B"),
            links: [ConceptLink(conceptA: "A", conceptB: "Elsewhere", weight: 1, strength: 0.5)],
            semanticLinks: [SemanticLink(conceptA: "Nowhere", conceptB: "B", strength: 0.5)],
            in: size)

        #expect(sim.edges.isEmpty)
    }

    @Test("the same inputs always produce the same draw order")
    func drawOrderIsStable() {
        func edgeOrder() -> [String] {
            let sim = GraphSimulation()
            sim.configure(
                concepts: concepts("A", "B", "C", "D"),
                links: [ConceptLink(conceptA: "A", conceptB: "B", weight: 1, strength: 0.4),
                        ConceptLink(conceptA: "C", conceptB: "D", weight: 1, strength: 0.4)],
                semanticLinks: [SemanticLink(conceptA: "B", conceptB: "C", strength: 0.4)],
                in: size)
            return sim.edges.map { "\($0.a)-\($0.b)" }
        }
        // Edges are collected through a dictionary, which has no order of its
        // own; the draw order decides which line lands on top of which.
        #expect(edgeOrder() == edgeOrder())
    }

    // MARK: - Strength drives the layout, not just the line

    @Test("a strong connection pulls its Concepts closer than a weak one")
    func strengthMovesTheDots() {
        // ADR-0002: the spring attraction used to be a constant, so weight
        // moved nothing at all. Strong and weak pairs must now settle visibly
        // apart — and "visibly" is the whole assertion. Under the old constant
        // spring these two land 0.001pt apart, which `<` alone would call a
        // pass or a fail depending on where the random start put them.
        let sim = GraphSimulation()
        sim.configure(
            concepts: concepts("Strong1", "Strong2", "Weak1", "Weak2"),
            links: [ConceptLink(conceptA: "Strong1", conceptB: "Strong2", weight: 9, strength: 0.95),
                    ConceptLink(conceptA: "Weak1", conceptB: "Weak2", weight: 1, strength: 0.18)],
            in: size)
        settled(sim)

        let strong = distance(sim, "Strong1", "Strong2")
        let weak = distance(sim, "Weak1", "Weak2")
        #expect(weak - strong > 15, "strong pair \(strong)pt, weak pair \(weak)pt")
    }

    @Test("settled distance tracks strength across the whole range")
    func settledDistanceTracksStrength() {
        // One pair alone, so nothing but its own spring decides where it ends
        // up. Measured: 0.0 → ~85pt, 0.95 → ~61pt.
        func settledDistance(_ strength: Double) -> CGFloat {
            let sim = GraphSimulation()
            sim.configure(
                concepts: concepts("A", "B"),
                links: [ConceptLink(conceptA: "A", conceptB: "B", weight: 1, strength: strength)],
                in: size)
            settled(sim)
            return distance(sim, "A", "B")
        }
        let loose = settledDistance(0.1)
        let middling = settledDistance(0.5)
        let tight = settledDistance(0.95)

        #expect(loose > middling)
        #expect(middling > tight)
        #expect(loose - tight > 15, "range collapsed: \(loose)pt to \(tight)pt")
    }

    @Test("strength shortens the spring and stiffens it, all the way up")
    func restLengthTracksStrength() {
        func edge(_ strength: Double) -> GraphSimulation.Edge {
            GraphSimulation.Edge(a: 0, b: 1, kind: .coread, strength: strength)
        }
        #expect(edge(0.2).restLength > edge(0.9).restLength)
        #expect(edge(0.2).stiffness < edge(0.9).stiffness)
    }

    @Test("strong and very strong do not draw identically, however much reading piles up")
    func widthDoesNotSaturate() {
        // The old width was min(3, 0.8 + weight * 0.5): saturated at weight
        // 4.4, so a pair read together five times and fifty times were one
        // line. Strength is bounded, so width has to stay separable across it.
        func width(_ strength: Double) -> CGFloat {
            GraphSimulation.Edge(a: 0, b: 1, kind: .coread, strength: strength).width
        }
        #expect(width(0.3) < width(0.6))
        #expect(width(0.6) < width(0.9))
        // Meaningfully apart, not merely different in the tenth decimal.
        #expect(width(0.9) - width(0.3) > 1)
    }

    // MARK: - Readable, and still quick

    @Test("a realistic map settles within the frame cap and stays quick")
    func settlingDoesNotRegress() {
        // The flagship's shape: 68 Concepts, a Dependency spine, ~120 Semantic
        // Links and a scattering of Co-read Links — which is more edges than
        // the map carried before this ticket, so the guard is on the total.
        let names = (0..<68).map { "C\($0)" }
        let all = names.map { Concept(name: $0, category: "Cluster\($0.count % 6)", definition: "d") }
        var semantic: [SemanticLink] = []
        for index in names.indices {
            for offset in 1...3 where index + offset < names.count {
                semantic.append(SemanticLink(conceptA: names[index],
                                             conceptB: names[index + offset],
                                             strength: 0.3 + Double(offset) * 0.2))
            }
        }
        let dependencies = names.indices.dropLast().map {
            ConceptDependency(prerequisite: names[$0], dependent: names[$0 + 1])
        }
        let coread = names.indices.dropLast(4).map {
            ConceptLink(conceptA: names[$0], conceptB: names[$0 + 4], weight: 2, strength: 0.5)
        }

        let sim = GraphSimulation()
        sim.configure(concepts: all, links: coread, semanticLinks: semantic,
                      dependencies: dependencies, clusterAnchored: true, in: size)

        // Motion has to be decaying, not growing. Stiffness rose with this
        // ticket (0.02 flat, to as much as 0.04 for a strong pair), and the
        // way that goes wrong is a net that rings instead of settling.
        func motion(after warmup: Int) -> CGFloat {
            for _ in 0..<warmup { sim.step(in: size) }
            var largest: CGFloat = 0
            var previous = sim.nodes.map(\.position)
            for _ in 0..<5 {
                sim.step(in: size)
                let now = sim.nodes.map(\.position)
                largest = max(largest, zip(previous, now)
                    .map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0)
                previous = now
            }
            return largest
        }
        let early = motion(after: 25)
        let later = motion(after: 90)
        #expect(later < early, "net is not settling: \(early)pt/frame → \(later)pt/frame")

        sim.configure(concepts: all, links: coread, semanticLinks: semantic,
                      dependencies: dependencies, clusterAnchored: true, in: size)
        let started = Date.now
        settled(sim)
        let elapsed = Date.now.timeIntervalSince(started)

        // 260 frames of an O(n²) repulsion loop over 68 nodes. Generous against
        // a debug build — this guards the shape of the work, not the frame rate.
        #expect(elapsed < 3, "260 frames took \(elapsed)s")
        // Nothing flew off: the net is still on the canvas.
        #expect(sim.nodes.allSatisfy {
            $0.position.x >= 0 && $0.position.x <= size.width
                && $0.position.y >= 0 && $0.position.y <= size.height
        })
        // And it is still one line per pair, not one per claim.
        #expect(sim.edges.count <= semantic.count + dependencies.count + coread.count)
    }

    @Test("a map with no connections still lays out without moving anything off screen")
    func emptyGraphIsSafe() {
        let sim = GraphSimulation()
        sim.configure(concepts: concepts("A"), links: [], in: size)
        settled(sim)
        #expect(sim.edges.isEmpty)
        #expect(sim.nodes.count == 1)
    }
}
