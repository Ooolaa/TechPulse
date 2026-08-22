import Testing
import Foundation
import SwiftData
@testable import TechPulse

// Which selected words are answered from the map, and which cost a model call.
//
// ADR-0006 accepts a quality cost on the grounds that the words it affects are
// "disproportionately words already on the map, which never reach a model at
// all". Until #31 that held only for a word spelled exactly as the Pack spelled
// it: "LoRAs" and "low-rank-adaptation" fell through to a generation, and on the
// opt-in path that is one more selected word leaving the device. ADR-0007 folds
// case, separators and plurals before the match and stops there. These tests are
// the boundary those two ADRs describe — the line between offline and Egress.

@Suite("Concept name folding")
struct ConceptMatchTests {

    /// The map a reader already has, as the Pack spelled it.
    private let map = ["LoRA", "Low-Rank Adaptation", "RAG", "Vector Database", "C++"]

    // MARK: What the fold catches — answered from the map, nothing sent

    @Test("the exact name still matches, in any case")
    func exactName() {
        #expect(ConceptMatch.first("LoRA", among: map, name: \.self) == "LoRA")
        #expect(ConceptMatch.first("lora", among: map, name: \.self) == "LoRA")
        #expect(ConceptMatch.first("RAG", among: map, name: \.self) == "RAG")
    }

    @Test("a plural of a word on the map is that word")
    func plurals() {
        #expect(ConceptMatch.first("LoRAs", among: map, name: \.self) == "LoRA")
        #expect(ConceptMatch.first("Vector Databases", among: map, name: \.self) == "Vector Database")
        // -ies and sibilant -es, so the fold isn't only a trailing "s".
        #expect(ConceptMatch.fold("Policies") == ConceptMatch.fold("Policy"))
        #expect(ConceptMatch.fold("Losses") == ConceptMatch.fold("Loss"))
    }

    @Test("hyphens and spaces are the same separator")
    func separators() {
        #expect(ConceptMatch.first("low-rank-adaptation", among: map, name: \.self) == "Low-Rank Adaptation")
        #expect(ConceptMatch.first("Low Rank Adaptation", among: map, name: \.self) == "Low-Rank Adaptation")
        #expect(ConceptMatch.first("low_rank_adaptation", among: map, name: \.self) == "Low-Rank Adaptation")
    }

    @Test("a name whose own punctuation is the name survives the fold")
    func punctuationInNames() {
        // `WordSelection` protects these on the way in; the fold must not undo
        // that by collapsing "C++" into something no Concept is named.
        #expect(ConceptMatch.first("c++", among: map, name: \.self) == "C++")
        #expect(ConceptMatch.fold("C#") == "c#")
    }

    // MARK: What it deliberately does not catch — these reach a model

    /// ADR-0007's accepted cost, stated as a test so it is a decision rather
    /// than an oversight: the fold is spelling, not meaning.
    @Test("a synonym of a word on the map is not a match")
    func synonymsStillGenerate() {
        #expect(ConceptMatch.first("low-rank adapters", among: ["LoRA"], name: \.self) == nil)
        #expect(ConceptMatch.first("retrieval augmented generation", among: ["RAG"], name: \.self) == nil)
    }

    @Test("a phrase around a word on the map is not that word")
    func phrasesStillGenerate() {
        #expect(ConceptMatch.first("RAG systems", among: map, name: \.self) == nil)
        #expect(ConceptMatch.first("quantization", among: map, name: \.self) == nil)
    }

    @Test("a selection that folds to nothing matches nothing")
    func emptyFold() {
        #expect(ConceptMatch.first("", among: map, name: \.self) == nil)
        #expect(ConceptMatch.first("   ", among: map, name: \.self) == nil)
    }

    // MARK: Which of two candidates wins

    @Test("an exact name beats a name that merely folds the same")
    func exactBeatsFolded() {
        // Both are on the map. Tapping "Agents" opens "Agents", not "Agent" —
        // the fold widens what matches, it never re-points an existing hit.
        let both = ["Agent", "Agents"]
        #expect(ConceptMatch.first("Agents", among: both, name: \.self) == "Agents")
        #expect(ConceptMatch.first("Agent", among: both, name: \.self) == "Agent")
    }
}

// MARK: - The call site

/// `ConceptMatch` being right is not enough: #29's lesson (`1f8334e`) was that
/// tested builders had an untested call site. This is the decision
/// `ArticleView.explain` makes — map first, model second — held where a test can
/// see it.
@MainActor
@Suite("Explain route", .serialized)
struct ExplainRouteTests {

    private static let store = TestStore()

    private func makeMap() throws -> [Concept] {
        let context = try Self.store.makeContext()
        for name in ["LoRA", "RAG"] {
            context.insert(Concept(name: name, category: "LLMs", definition: "d"))
        }
        try context.save()
        return try context.fetch(FetchDescriptor<Concept>())
    }

    private func named(_ route: ExplainRoute) -> String? {
        if case .existing(let concept) = route { return concept.name }
        return nil
    }

    @Test("an inflection of a word on the map opens that Concept, sending nothing")
    func inflectionStaysOffline() throws {
        let map = try makeMap()
        #expect(named(ExplainRoute.decide(term: "LoRAs", known: map, canDeepen: true)) == "LoRA")
    }

    @Test("the map answers even where no model is reachable at all")
    func mapNeedsNoModel() throws {
        let map = try makeMap()
        // The guard order, asserted: ADR-0006's third tier is about words the
        // map does not have, not about the feature being off.
        #expect(named(ExplainRoute.decide(term: "lora", known: map, canDeepen: false)) == "LoRA")
    }

    @Test("a word the map does not have reaches a model")
    func unknownTermGenerates() throws {
        let map = try makeMap()
        guard case .generate = ExplainRoute.decide(term: "Chain of thought",
                                                   known: map, canDeepen: true) else {
            Issue.record("expected an unknown term to reach a model")
            return
        }
    }

    @Test("a word the map does not have does nothing without a tier")
    func unknownTermWithoutATier() throws {
        let map = try makeMap()
        guard case .unavailable = ExplainRoute.decide(term: "Chain of thought",
                                                      known: map, canDeepen: false) else {
            Issue.record("expected no tier to end in nothing happening")
            return
        }
    }
}
