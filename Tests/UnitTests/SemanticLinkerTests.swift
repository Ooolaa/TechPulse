import Testing
import Foundation
@testable import TechPulse

/// Semantic Links are derived from what Concepts *mean*, so most of these run
/// against hand-built vectors: the graph rules are testable exactly, without
/// asking Apple's embedding to behave a particular way. The last section runs
/// the real embedding over the real flagship Pack, which is the claim the
/// ticket actually makes — a new Pack opens connected.
@MainActor
@Suite("Semantic linker")
struct SemanticLinkerTests {

    // MARK: - Fixtures

    /// A vector source built from explicit coordinates, so "related" is
    /// something the test decides rather than something it hopes for.
    private func vectors(_ table: [String: [Double]]) -> @MainActor @Sendable (String) -> [Double]? {
        { table[$0] }
    }

    private func concepts(_ names: String...) -> [LinkableConcept] {
        names.map { LinkableConcept(name: $0, definition: "definition of \($0)") }
    }

    /// The linker embeds "name. definition", so fixtures key on the same text.
    private func text(_ name: String) -> String { "\(name). definition of \(name)" }

    private func pairs(_ edges: [SemanticEdge]) -> Set<String> {
        Set(edges.map { "\($0.conceptA)~\($0.conceptB)" })
    }

    // MARK: - The graph rules

    @Test("Concepts pointing the same way are linked; one pointing elsewhere is not")
    func relatedConceptsLink() {
        // A and B are near-parallel, C is orthogonal to both.
        let table = [
            text("A"): [1.0, 0.05, 0.0],
            text("B"): [0.98, 0.1, 0.0],
            text("C"): [0.0, 0.0, 1.0],
        ]
        let edges = SemanticLinker.link(concepts("A", "B", "C"), vector: vectors(table))

        #expect(pairs(edges) == ["A~B"])
    }

    @Test("an edge is stored once, undirected, with its Concepts in sorted order")
    func edgesAreUndirectedAndDeduplicated() {
        let table = [
            text("Zebra"): [1.0, 0.05, 0.0],
            text("Alpha"): [0.98, 0.1, 0.0],
        ]
        let edges = SemanticLinker.link(concepts("Zebra", "Alpha"), vector: vectors(table))

        #expect(edges.count == 1)
        // Sorted, so the pair has one representation no matter the input order.
        #expect(edges.first?.conceptA == "Alpha")
        #expect(edges.first?.conceptB == "Zebra")
    }

    @Test("the same Pack always produces the same links, whatever order it arrives in")
    func linkingIsOrderIndependent() {
        let table = [
            text("A"): [1.0, 0.1, 0.0], text("B"): [0.95, 0.2, 0.05],
            text("C"): [0.9, 0.3, 0.1], text("D"): [0.0, 0.1, 1.0],
            text("E"): [0.05, 0.2, 0.95],
        ]
        let forward = SemanticLinker.link(concepts("A", "B", "C", "D", "E"), vector: vectors(table))
        let backward = SemanticLinker.link(concepts("E", "D", "C", "B", "A"), vector: vectors(table))

        #expect(pairs(forward) == pairs(backward))
    }

    @Test("no Concept exceeds the neighbour cap — the threshold that keeps the map readable")
    func degreeIsBounded() {
        // Twelve Concepts all pointing nearly the same way: without a cap this
        // is a 66-edge hairball, which is the failure ADR-0002 names.
        let names = (1...12).map { "C\($0)" }
        var table: [String: [Double]] = [:]
        for (index, name) in names.enumerated() {
            table[text(name)] = [1.0, Double(index) * 0.01, 0.0]
        }
        let edges = SemanticLinker.link(names.map {
            LinkableConcept(name: $0, definition: "definition of \($0)")
        }, vector: vectors(table))

        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.conceptA, default: 0] += 1
            degree[edge.conceptB, default: 0] += 1
        }
        #expect(degree.values.allSatisfy { $0 <= SemanticLinker.neighbourCount })
        #expect(edges.count < names.count * (names.count - 1) / 2)
    }

    @Test("a Concept unrelated to the Pack is left unlinked, however lonely it is")
    func unrelatedConceptIsNotLinked() {
        // "Stray" is orthogonal to a tight cluster. Nearest-neighbour alone
        // would still hand it a neighbour — the floor is what refuses.
        let table = [
            text("A"): [1.0, 0.02, 0.0],
            text("B"): [0.99, 0.05, 0.0],
            text("C"): [0.98, 0.08, 0.0],
            text("Stray"): [0.0, 0.0, 1.0],
        ]
        let edges = SemanticLinker.link(concepts("A", "B", "C", "Stray"), vector: vectors(table))

        #expect(!edges.contains { $0.conceptA == "Stray" || $0.conceptB == "Stray" })
        #expect(!edges.isEmpty)
    }

    @Test("strength is reported in 0...1 so a renderer can scale by it")
    func strengthIsNormalized() {
        let table = [
            text("A"): [1.0, 0.05, 0.0],
            text("B"): [0.98, 0.1, 0.0],
            text("C"): [0.9, 0.3, 0.0],
        ]
        let edges = SemanticLinker.link(concepts("A", "B", "C"), vector: vectors(table))

        #expect(!edges.isEmpty)
        #expect(edges.allSatisfy { $0.strength >= 0 && $0.strength <= 1 })
    }

    // MARK: - Degenerate Packs

    @Test("a Pack too small to have a pair produces no links")
    func tinyPacksProduceNoLinks() {
        #expect(SemanticLinker.link([], vector: { _ in [1.0, 0.0] }).isEmpty)
        #expect(SemanticLinker.link(concepts("Only"), vector: { _ in [1.0, 0.0] }).isEmpty)
    }

    @Test("a Concept the embedding cannot place is skipped, and the rest still link")
    func unembeddableConceptsAreSkipped() {
        let table = [
            text("A"): [1.0, 0.05, 0.0],
            text("B"): [0.98, 0.1, 0.0],
            // "Untranslatable" has no entry — the embedding returns nothing.
        ]
        let edges = SemanticLinker.link(concepts("A", "B", "Untranslatable"),
                                        vector: vectors(table))

        #expect(pairs(edges) == ["A~B"])
    }

    @Test("with no embedding at all there are no Semantic Links, and no crash")
    func noEmbeddingMeansNoLinks() {
        // Hardware or a language the embedding has no model for. The map is
        // poorer; the install still works.
        let edges = SemanticLinker.link(concepts("A", "B", "C"), vector: { _ in nil })
        #expect(edges.isEmpty)
    }

    @Test("identical definitions do not divide by zero")
    func identicalDefinitionsAreSafe() {
        // Every vector equal means the centred vectors are all zero — the
        // degenerate case that would produce NaN strengths.
        let edges = SemanticLinker.link(concepts("A", "B", "C"), vector: { _ in [1.0, 0.0, 0.0] })
        #expect(edges.allSatisfy { $0.strength.isFinite })
    }

    // MARK: - The real embedding, over the real Pack

    @Test("a freshly installed flagship Pack opens as a connected map, not dust")
    func flagshipPackIsConnected() throws {
        let pack = try BuiltinPacks.aiEngineer()
        let edges = SemanticLinker.link(pack.concepts.map {
            LinkableConcept(name: $0.name, definition: $0.definition)
        })

        // Every Concept is joined to something: no dot sits alone on day one.
        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.conceptA, default: 0] += 1
            degree[edge.conceptB, default: 0] += 1
        }
        let isolated = pack.concepts.map(\.name).filter { (degree[$0] ?? 0) == 0 }
        #expect(isolated.isEmpty, "isolated Concepts: \(isolated)")

        // And the map is one field, not a scatter of islands.
        #expect(componentCount(of: edges, over: pack.concepts.map(\.name)) == 1)
    }

    @Test("a Concept from another field entirely earns no Semantic Link")
    func outsiderIsNotLinkedIntoTheFlagshipPack() throws {
        let pack = try BuiltinPacks.aiEngineer()
        var linkable = pack.concepts.map {
            LinkableConcept(name: $0.name, definition: $0.definition)
        }
        // Judged by exactly the machinery a real stray Concept would meet.
        let outsiders = [
            LinkableConcept(name: "Sourdough Bread Baking",
                            definition: "Fermenting flour and water with wild yeast to make bread."),
            LinkableConcept(name: "Baroque Counterpoint",
                            definition: "Writing independent melodic lines that harmonise, as Bach did."),
            LinkableConcept(name: "Offside Rule",
                            definition: "The football law that stops attackers goal-hanging behind the last defender."),
        ]
        linkable.append(contentsOf: outsiders)

        let edges = SemanticLinker.link(linkable)
        for outsider in outsiders {
            #expect(!edges.contains { $0.conceptA == outsider.name || $0.conceptB == outsider.name },
                    "\(outsider.name) should not be linked into an AI Pack")
        }
    }

    @Test("linking a realistic Pack is quick enough not to hold the reader up")
    func linkingIsFastEnoughToBlockOn() throws {
        let pack = try BuiltinPacks.aiEngineer()
        let linkable = pack.concepts.map {
            LinkableConcept(name: $0.name, definition: $0.definition)
        }
        _ = SemanticLinker.link(Array(linkable.prefix(2)))     // pay the model load first

        let started = Date.now
        _ = SemanticLinker.link(linkable)
        let elapsed = Date.now.timeIntervalSince(started)

        // Generous against a debug simulator build: this is a regression guard
        // on the algorithm's shape, not a benchmark. The measured cost is ~0.4s
        // for 68 Concepts, nearly all of it Apple's per-Concept embedding call.
        #expect(elapsed < 5, "linking \(linkable.count) Concepts took \(elapsed)s")
    }

    // MARK: - Helpers

    /// Connected components over the Semantic Links alone.
    private func componentCount(of edges: [SemanticEdge], over names: [String]) -> Int {
        var parent = Dictionary(uniqueKeysWithValues: names.map { ($0, $0) })
        func find(_ name: String) -> String {
            var root = name
            while parent[root] != root { root = parent[root]! }
            return root
        }
        for edge in edges {
            let a = find(edge.conceptA), b = find(edge.conceptB)
            if a != b { parent[a] = b }
        }
        return Set(names.map(find)).count
    }
}
