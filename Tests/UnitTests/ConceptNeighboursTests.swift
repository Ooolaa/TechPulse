import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// ADR-0002's day-one failure, turned into assertions: a Concept no reading has
/// met still has neighbours, because Semantic Links are computed at install.
@MainActor
@Suite("Concept neighbours", .serialized)
struct ConceptNeighboursTests {


    private static let sharedContainer: ModelContainer = {
        try! AppSchema.inMemoryContainer()
    }()

    private static func freshContext() throws -> ModelContext {
        let context = sharedContainer.mainContext
        for concept in try context.fetch(FetchDescriptor<Concept>()) { context.delete(concept) }
        for dep in try context.fetch(FetchDescriptor<ConceptDependency>()) { context.delete(dep) }
        for link in try context.fetch(FetchDescriptor<ConceptLink>()) { context.delete(link) }
        for link in try context.fetch(FetchDescriptor<SemanticLink>()) { context.delete(link) }
        for pack in try context.fetch(FetchDescriptor<InstalledPack>()) { context.delete(pack) }
        try context.save()
        return context
    }

    private func concept(_ name: String) -> Concept {
        Concept(name: name, category: "Foundations", definition: "d")
    }

    private func coread(_ a: String, _ b: String, _ strength: Double) -> ConceptLink {
        let pair = [a, b].sorted()
        return ConceptLink(conceptA: pair[0], conceptB: pair[1], weight: 1, strength: strength)
    }

    private func semantic(_ a: String, _ b: String, _ strength: Double) -> SemanticLink {
        let pair = [a, b].sorted()
        return SemanticLink(conceptA: pair[0], conceptB: pair[1], strength: strength)
    }

    private func names(_ concepts: [Concept]) -> [String] { concepts.map(\.name) }

    // MARK: Day one

    @Test("a Concept no reading has met still has neighbours to jump to")
    func semanticLinksCoverDayOne() {
        // The frontier Concept: unlit, so the one a reader opens first and is
        // least likely to have read anything about (#33).
        let concepts = ["Attention", "Embeddings", "Tokenization"].map(concept)
        let neighbours = ConceptNeighbours.around("Attention", concepts: concepts, coread: [],
                                                  semantic: [semantic("Attention", "Embeddings", 0.7),
                                                             semantic("Attention", "Tokenization", 0.5)])
        #expect(neighbours.readTogether.isEmpty)
        #expect(names(neighbours.related) == ["Embeddings", "Tokenization"])
        #expect(!neighbours.isEmpty)
    }

    @Test("no links of either kind is genuinely no neighbours")
    func noLinksAtAll() {
        let neighbours = ConceptNeighbours.around("Attention", concepts: [concept("Attention")],
                                                  coread: [], semantic: [])
        #expect(neighbours.isEmpty)
    }

    // MARK: The two claims stay apart

    @Test("read together and related in meaning are kept as separate claims")
    func kindsStaySeparate() {
        let concepts = ["RAG", "Embeddings", "Chunking"].map(concept)
        let neighbours = ConceptNeighbours.around("RAG", concepts: concepts,
                                                  coread: [coread("RAG", "Chunking", 0.4)],
                                                  semantic: [semantic("RAG", "Embeddings", 0.9)])
        #expect(names(neighbours.readTogether) == ["Chunking"])
        #expect(names(neighbours.related) == ["Embeddings"])
    }

    @Test("a pair that is both is claimed once, by the reading")
    func readingWinsOverMeaning() {
        // Having read them together is the stronger claim, and the same chip
        // twice under two headings would be a lie about one of them.
        let concepts = ["RAG", "Embeddings"].map(concept)
        let neighbours = ConceptNeighbours.around("RAG", concepts: concepts,
                                                  coread: [coread("RAG", "Embeddings", 0.3)],
                                                  semantic: [semantic("RAG", "Embeddings", 0.9)])
        #expect(names(neighbours.readTogether) == ["Embeddings"])
        #expect(neighbours.related.isEmpty)
    }

    // MARK: Ordering

    @Test("the strongest association heads each list, whichever end of the pair it is")
    func strongestFirst() {
        let concepts = ["RAG", "Embeddings", "Chunking", "Agents"].map(concept)
        // "Agents" sorts before "RAG", so this pair is stored the other way round.
        let neighbours = ConceptNeighbours.around("RAG", concepts: concepts,
                                                  coread: [coread("RAG", "Chunking", 0.2),
                                                           coread("Agents", "RAG", 0.8),
                                                           coread("RAG", "Embeddings", 0.5)],
                                                  semantic: [])
        #expect(names(neighbours.readTogether) == ["Agents", "Embeddings", "Chunking"])
    }

    @Test("the strongest link of a pair decides its place, not the weakest")
    func strongestLinkOfAPairWins() {
        let concepts = ["RAG", "Embeddings", "Chunking"].map(concept)
        let neighbours = ConceptNeighbours.around("RAG", concepts: concepts,
                                                  coread: [coread("RAG", "Embeddings", 0.1),
                                                           coread("RAG", "Embeddings", 0.9),
                                                           coread("RAG", "Chunking", 0.5)],
                                                  semantic: [])
        #expect(names(neighbours.readTogether) == ["Embeddings", "Chunking"])
    }

    // MARK: What the sheet can show

    @Test("both kinds present share the row rather than one crowding the other out")
    func bothKindsShareTheCap() {
        let concepts = (1...6).map { concept("Read\($0)") } + (1...6).map { concept("Means\($0)") }
            + [concept("Attention")]
        let coreadLinks = (1...6).map { coread("Attention", "Read\($0)", Double($0) / 10) }
        let semanticLinks = (1...6).map { semantic("Attention", "Means\($0)", Double($0) / 10) }
        let neighbours = ConceptNeighbours.around("Attention", concepts: concepts,
                                                  coread: coreadLinks, semantic: semanticLinks)
        #expect(neighbours.readTogether.count == 3)
        #expect(neighbours.related.count == 3)
        #expect(names(neighbours.readTogether).first == "Read6")
        #expect(names(neighbours.related).first == "Means6")
    }

    @Test("slots one kind cannot fill go to the other rather than staying empty")
    func unusedSlotsGoToTheOtherKind() {
        // One Concept read together, six that mean something similar. Reserving
        // half the row for the Co-read kind would show four chips and a gap.
        let concepts = [concept("Attention"), concept("Read1")] + (1...6).map { concept("Means\($0)") }
        let neighbours = ConceptNeighbours.around("Attention", concepts: concepts,
                                                  coread: [coread("Attention", "Read1", 0.5)],
                                                  semantic: (1...6).map { semantic("Attention", "Means\($0)", Double($0) / 10) })
        #expect(neighbours.readTogether.count == 1)
        #expect(neighbours.readTogether.count + neighbours.related.count == ConceptNeighbours.chipCount)
    }

    @Test("one kind alone takes the whole row")
    func oneKindTakesTheWholeCap() {
        let concepts = (1...8).map { concept("Read\($0)") } + [concept("Attention")]
        let coreadLinks = (1...8).map { coread("Attention", "Read\($0)", Double($0) / 10) }
        let onlyCoread = ConceptNeighbours.around("Attention", concepts: concepts,
                                                  coread: coreadLinks, semantic: [])
        #expect(onlyCoread.readTogether.count == 6)

        // `SemanticLinker.neighbourCount` bounds a real Concept to 5 Semantic
        // Links; the row's cap is the sheet's rule, not the linker's, so it is
        // asserted on its own terms.
        let semanticLinks = (1...8).map { semantic("Attention", "Read\($0)", Double($0) / 10) }
        let onlySemantic = ConceptNeighbours.around("Attention", concepts: concepts,
                                                    coread: [], semantic: semanticLinks)
        #expect(onlySemantic.related.count == 6)
    }

    // MARK: Links outliving their Concepts

    @Test("a link naming a Concept that is no longer installed offers no chip")
    func linksToAbsentConceptsAreDropped() {
        // Retiring a Pack leaves its Concepts behind but a regenerated map can
        // still name one that this store never had; a chip with nothing to push
        // is worse than one fewer chip.
        let concepts = ["Attention", "Embeddings"].map(concept)
        let neighbours = ConceptNeighbours.around("Attention", concepts: concepts, coread: [],
                                                  semantic: [semantic("Attention", "Sourdough", 0.9),
                                                             semantic("Attention", "Embeddings", 0.4)])
        #expect(names(neighbours.related) == ["Embeddings"])
    }

    @Test("a Concept is never its own neighbour")
    func noSelfLink() {
        let neighbours = ConceptNeighbours.around("Attention", concepts: [concept("Attention")],
                                                  coread: [coread("Attention", "Attention", 0.9)],
                                                  semantic: [semantic("Attention", "Attention", 0.9)])
        #expect(neighbours.isEmpty)
    }

    // MARK: Day one, on the Pack that ships

    /// The rule above is pure, so it cannot say whether a real install leaves
    /// the frontier Concept anything to jump to. This installs the flagship
    /// with the embedding the app ships with — no injected vectors — and asks
    /// the question #33 was filed about, of the Concept it was filed about.
    @Test("the flagship Pack's frontier Concept has neighbours before any reading")
    func flagshipFrontierHasNeighboursOnDayOne() throws {
        let context = try Self.freshContext()
        let record = try PackInstaller.install(try BuiltinPacks.aiEngineer(),
                                               origin: .builtin, context: context)
        let pack = ActivePack(record: record)
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let dependencies = try context.fetch(FetchDescriptor<ConceptDependency>())
        let semanticLinks = try context.fetch(FetchDescriptor<SemanticLink>())
        let coreadLinks = try context.fetch(FetchDescriptor<ConceptLink>())

        // Day one is the premise: nothing has been read, so there are no
        // Co-read Links for the sheet to fall back on.
        #expect(coreadLinks.isEmpty)
        #expect(!semanticLinks.isEmpty, "installing a Pack computes its Semantic Links (ADR-0002)")

        let frontier = KnowledgePathEngine.frontier(concepts: concepts,
                                                    dependencies: dependencies, pack: pack)
        #expect(!frontier.isEmpty)
        for name in frontier {
            let neighbours = ConceptNeighbours.around(name, concepts: concepts,
                                                      coread: coreadLinks, semantic: semanticLinks)
            #expect(!neighbours.related.isEmpty,
                    "\(name) is on the frontier and has nothing to jump to on day one")
            #expect(neighbours.readTogether.isEmpty)
        }
    }
}
