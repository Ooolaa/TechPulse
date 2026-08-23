import Testing
import Foundation
@testable import TechPulse

/// Editing a Pack that is not installed yet.
///
/// The property every test here is about is the same one: a draft stays
/// installable. `PackValidator.validate` is the assertion that matters — the
/// `#expect`s around it say *how* the edit propagated, but the throw is what
/// the reader would have hit at Install.
@Suite("Pack draft editing")
struct PackDraftTests {

    /// The flagship, read the way the app reads it. A real Pack rather than a
    /// three-Concept fixture, because propagation is only interesting where a
    /// name is referenced from several places at once: "Prompt Engineering" is
    /// a Dependency of five Concepts and sits in Stage 4.
    private func makeDraft() throws -> PackDraft {
        PackDraft(file: try BuiltinPacks.load(BuiltinPacks.aiEngineerFileName),
                  origin: .builtin)
    }

    private let referenced = "Prompt Engineering"

    @Test("removing a concept scrubs dependencies and stages — the draft stays installable")
    func removePropagates() throws {
        var draft = try makeDraft()
        #expect(draft.file.concepts.contains { $0.dependencies.contains(referenced) },
                "the fixture must name a Concept other Concepts depend on")

        draft.removeConcept(named: referenced)

        #expect(!draft.file.concepts.contains { $0.name == referenced })
        #expect(!draft.file.concepts.contains { $0.dependencies.contains(referenced) })
        #expect(!draft.file.stages.contains { $0.concepts.contains(referenced) })
        try PackValidator.validate(draft.file)
    }

    @Test("renaming propagates through dependencies and stages — the draft stays installable")
    func renamePropagates() throws {
        var draft = try makeDraft()
        draft.renameConcept(referenced, to: "Prompting")

        #expect(draft.file.concepts.contains { $0.name == "Prompting" })
        #expect(!draft.file.concepts.contains { $0.name == referenced })
        #expect(draft.file.concepts.contains { $0.dependencies.contains("Prompting") })
        #expect(draft.file.stages.contains { $0.concepts.contains("Prompting") })
        try PackValidator.validate(draft.file)
    }

    @Test("rename to an existing name, or to nothing, is a no-op")
    func renameGuards() throws {
        var draft = try makeDraft()
        draft.renameConcept(referenced, to: "RAG")              // collision
        #expect(draft.file.concepts.contains { $0.name == referenced })
        draft.renameConcept(referenced, to: "   ")              // nothing
        #expect(draft.file.concepts.contains { $0.name == referenced })
        try PackValidator.validate(draft.file)
    }

    /// The half the port did not have. #22 made `PackValidator` reject two
    /// Concept names differing only in case — they resolve onto one stored row —
    /// so a guard that compared the new name exactly would let this rename
    /// through and produce a draft that will not install.
    @Test("rename onto another concept's name in different case is a no-op")
    func renameOntoACaseVariantIsRefused() throws {
        var draft = try makeDraft()
        #expect(draft.file.concepts.contains { $0.name == "RAG" },
                "the fixture must contain the Concept this rename would collide with")

        draft.renameConcept(referenced, to: "rag")

        #expect(draft.file.concepts.contains { $0.name == referenced },
                "the rename should not have happened")
        #expect(draft.file.concepts.filter { $0.name.lowercased() == "rag" }.count == 1)
        try PackValidator.validate(draft.file)
    }

    /// A Concept may still be recapitalized: the name it collides with is its
    /// own, and one row is what it was going to be either way.
    @Test("a concept may be renamed into a different case of itself")
    func renameToOwnCaseVariant() throws {
        var draft = try makeDraft()
        draft.renameConcept("RAG", to: "rag")

        #expect(draft.file.concepts.contains { $0.name == "rag" })
        #expect(draft.file.concepts.contains { $0.dependencies.contains("rag") })
        try PackValidator.validate(draft.file)
    }

    /// A Stage the edit emptied is dropped rather than left drawing a blank rung
    /// on the "You are here" ladder — the same thing `PackGenerator.sanitize`
    /// does with a Stage a model left nothing in.
    @Test("a stage emptied by removals goes with them")
    func removingAStagesLastConceptDropsTheStage() throws {
        var draft = try makeDraft()
        let stage = try #require(draft.file.stages.first)
        for name in stage.concepts { draft.removeConcept(named: name) }

        #expect(!draft.file.stages.contains { $0.title == stage.title })
        #expect(!draft.file.stages.contains { $0.concepts.isEmpty })
        try PackValidator.validate(draft.file)
    }

    @Test("clusters group in the pack's own order, skipping the empty ones")
    func clusterGrouping() throws {
        let draft = try makeDraft()
        let clusters = draft.conceptsByCluster.map(\.cluster)

        #expect(clusters == draft.file.clusterOrder.filter { cluster in
            draft.file.concepts.contains { $0.cluster == cluster }
        })
        #expect(draft.conceptsByCluster.allSatisfy { group in
            group.concepts.allSatisfy { $0.cluster == group.cluster }
        })
        #expect(draft.conceptsByCluster.reduce(0) { $0 + $1.concepts.count }
                == draft.file.concepts.count,
                "every Concept belongs to a Cluster the Pack declares")
    }
}
