import Testing
import Foundation
@testable import TechPulse

/// ADR-0002's grievances against the old raw-count Co-read Link, turned into
/// assertions: every pair linked, hubs linked to everything, a weight that
/// climbs forever and saturates the moment it is drawn.
@MainActor
@Suite("Co-read scoring")
struct CoreadScoringTests {

    private func pairs(_ edges: [CoreadEdge]) -> Set<String> {
        Set(edges.map { "\($0.conceptA)~\($0.conceptB)" })
    }

    private func strength(_ edges: [CoreadEdge], _ a: String, _ b: String) -> Double? {
        let pair = [a, b].sorted()
        return edges.first { $0.conceptA == pair[0] && $0.conceptB == pair[1] }?.strength
    }

    // MARK: - Association, not raw count

    @Test("a Concept that appears in everything is not strongly linked to everything")
    func hubIsNotLinkedToEverything() {
        // "Transformers" turns up in every reading; A and B turn up together.
        // Raw counting says the hub is joined to all six. Association says it
        // is joined to none of them, and that A~B is the real connection.
        let groups = [
            ["Transformers", "A"], ["Transformers", "B"], ["Transformers", "C"],
            ["Transformers", "D"], ["Transformers", "E"], ["Transformers", "F"],
            ["A", "B"], ["A", "B"], ["A", "B"],
        ]
        let edges = CoreadScoring.score(groups)

        #expect(!edges.contains { $0.conceptA == "Transformers" || $0.conceptB == "Transformers" })
        #expect(pairs(edges).contains("A~B"))
    }

    @Test("Concepts that always appear together beat Concepts that rarely do")
    func constantCompanionsOutrankOccasionalOnes() {
        let groups = [
            ["RAG", "Embeddings"], ["RAG", "Embeddings"], ["RAG", "Embeddings"],
            ["RAG", "Robotics"],
            ["Robotics", "Actuators"], ["Robotics", "Actuators"], ["Robotics", "Sensors"],
        ]
        let edges = CoreadScoring.score(groups)

        let together = try? #require(strength(edges, "RAG", "Embeddings"))
        let occasional = strength(edges, "RAG", "Robotics")
        #expect(together != nil)
        // The one-off pairing is either dropped outright or scores lower.
        #expect(occasional == nil || occasional! < together!)
    }

    @Test("a weak association is dropped rather than stored forever")
    func weakLinksAreDropped() {
        // Met once, in a reading each also shares with better-matched partners.
        var groups = [["Stray", "Common"]]
        for _ in 0..<8 { groups.append(["Common", "Partner"]) }
        let edges = CoreadScoring.score(groups)

        #expect(!pairs(edges).contains("Common~Stray"))
        #expect(pairs(edges).contains("Common~Partner"))
    }

    // MARK: - Density

    @Test("one reading full of Concepts does not emit an edge for every pair")
    func denseReadingDoesNotEmitEveryPair() {
        // ADR-0002's arithmetic: 8 Concepts used to emit 28 Links, and density
        // grew quadratically with how rich the article was.
        let group = (1...8).map { "C\($0)" }
        let edges = CoreadScoring.score([group])

        // Five principals pair up: ten edges, not twenty-eight.
        #expect(edges.count == 10)
        // The reading's trailing Concepts are attached to it and still light
        // up — they just make no claim to have been read *alongside* the rest.
        for trailing in ["C6", "C7", "C8"] {
            #expect(!edges.contains { $0.conceptA == trailing || $0.conceptB == trailing })
        }
    }

    @Test("no Concept keeps more than its strongest few connections")
    func degreeIsBounded() {
        // One Concept met alongside 30 others, repeatedly, so raw counting
        // would give it 30 edges.
        var groups: [[String]] = []
        for i in 1...30 {
            groups.append(["Anchor", "N\(i)"])
            groups.append(["Anchor", "N\(i)"])
        }
        let edges = CoreadScoring.score(groups)

        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.conceptA, default: 0] += 1
            degree[edge.conceptB, default: 0] += 1
        }
        #expect(degree.values.allSatisfy { $0 <= CoreadScoring.neighbourCount })
    }

    // MARK: - Strength stays legible

    @Test("reading a pair together again strengthens it, well past a handful")
    func strengthKeepsClimbing() {
        func strengthAfter(_ readings: Int) -> Double {
            let groups = Array(repeating: ["A", "B"], count: readings)
            return strength(CoreadScoring.score(groups), "A", "B") ?? 0
        }

        // The old rendering saturated at weight ≈ 4.4, so "read together twice"
        // and "read together twenty times" drew identically. #10 needs these
        // to stay apart.
        let two = strengthAfter(2)
        let five = strengthAfter(5)
        let twenty = strengthAfter(20)
        #expect(two < five)
        #expect(five < twenty)
        #expect(twenty <= 1)
    }

    @Test("strength is reported in 0...1 and readings are counted honestly")
    func edgesAreWellFormed() {
        let edges = CoreadScoring.score([["Zebra", "Alpha"], ["Zebra", "Alpha"]])

        let edge = try? #require(edges.first)
        #expect(edges.count == 1)
        #expect(edge?.conceptA == "Alpha")          // sorted: undirected
        #expect(edge?.conceptB == "Zebra")
        #expect(edge?.readings == 2)
        #expect((edge?.strength ?? -1) > 0 && (edge?.strength ?? 2) <= 1)
    }

    @Test("the same readings produce the same links, whatever order they arrive in")
    func scoringIsOrderIndependent() {
        let groups = [["A", "B"], ["B", "C"], ["A", "B"], ["C", "D"], ["A", "B", "C"]]
        let forward = CoreadScoring.score(groups)
        let backward = CoreadScoring.score(groups.reversed())

        #expect(pairs(forward) == pairs(backward))
    }

    // MARK: - Degenerate readings

    @Test("a reading with nothing to pair produces no links")
    func emptyReadingsProduceNothing() {
        #expect(CoreadScoring.score([]).isEmpty)
        #expect(CoreadScoring.score([[]]).isEmpty)
        #expect(CoreadScoring.score([["Alone"]]).isEmpty)
    }

    @Test("a Concept named twice in one reading is not linked to itself")
    func noSelfLinks() {
        let edges = CoreadScoring.score([["A", "A", "B"]])
        #expect(!edges.contains { $0.conceptA == $0.conceptB })
        #expect(pairs(edges) == ["A~B"])
    }
}
