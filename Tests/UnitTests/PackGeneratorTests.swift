import Testing
import Foundation
import SwiftData
@testable import TechPulse

/// Hostile and sloppy model output must not install.
///
/// The suite the port was worth having for. A generated Pack is untrusted input
/// that the app itself asked for, and the only thing standing between a model's
/// reply and the reader's map is `sanitize` followed by `PackValidator` — so
/// what is asserted here is mostly one sentence: whatever went in, what comes
/// out validates.
@Suite("Pack generator sanitizer")
struct PackGeneratorSanitizerTests {

    private func concept(_ name: String, _ cluster: String = "A",
                         definition: String? = nil,
                         dependsOn dependencies: [String] = []) -> PackFile.PackConcept {
        .init(name: name, cluster: cluster,
              definition: definition ?? "what \(name) means", dependencies: dependencies)
    }

    private func pack(field: String = "Tester",
                      specialty: String? = "A",
                      clusters: [String] = ["A"],
                      concepts: [PackFile.PackConcept],
                      stages: [PackFile.PackStage] = [],
                      sources: [PackFile.PackSource] = []) -> PackFile {
        PackFile(field: field, specialtyCluster: specialty, clusterOrder: clusters,
                 concepts: concepts, stages: stages, suggestedSources: sources)
    }

    // MARK: - The ported three

    @Test("scrubs duplicates, self-references and dangling dependencies, then validates")
    func scrubbing() throws {
        let dirty = pack(
            field: "  Tester  ",
            specialty: "Ghost cluster",
            concepts: [
                concept("X", dependsOn: ["X", "Nonexistent", "Y"]),   // self + dangling
                concept("Y"),
                concept("x"),                                          // duplicate, by case
            ],
            stages: [.init(title: "S", subtitle: "", concepts: ["X", "Ghost"])]
        )

        let clean = PackGenerator.sanitize(dirty)

        try PackValidator.validate(clean)
        #expect(clean.field == "Tester")
        #expect(clean.concepts.count == 2)
        #expect(clean.concepts.first { $0.name == "X" }?.dependencies == ["Y"])
        #expect(clean.specialtyCluster == "A")                         // remapped off the ghost
        #expect(clean.stages.allSatisfy { !$0.concepts.contains("Ghost") })
    }

    @Test("breaks dependency cycles instead of failing")
    func cycleBreaking() throws {
        let cyclic = pack(concepts: [
            concept("P", dependsOn: ["Q"]),
            concept("Q", dependsOn: ["P"]),
        ])

        let clean = PackGenerator.sanitize(cyclic)

        try PackValidator.validate(clean)                              // no cycle left
        #expect(clean.concepts.count == 2, "breaking a cycle costs edges, not Concepts")
        #expect(clean.stages.count == 1, "a reply with no stages gets its Clusters as stages")
    }

    @Test("parses model JSON with fences and prose around it")
    func fencedJSON() throws {
        let text = """
        Sure! Here's the pack:
        ```json
        {"formatVersion":1,"field":"C","specialtyCluster":"A","clusterOrder":["A"],
         "concepts":[{"name":"N","cluster":"A","definition":"d","dependencies":[]}],
         "stages":[],"suggestedSources":[]}
        ```
        Let me know if you'd like it adjusted.
        """

        let pack = try #require(PackGenerator.parseRemoteJSON(text))

        #expect(pack.field == "C")
        #expect(pack.concepts.count == 1)
    }

    @Test("a reply with no object in it is not a pack")
    func unparseableReply() {
        #expect(PackGenerator.parseRemoteJSON("I can't help with that.") == nil)
        #expect(PackGenerator.parseRemoteJSON("") == nil)
        #expect(PackGenerator.parseRemoteJSON("{\"field\":\"C\"}") == nil,
                "a JSON object that is not a Pack is not a Pack")
    }

    // MARK: - The agreement the sanitizer exists to keep

    /// The acceptance criterion, stated once over everything the sanitizer is
    /// supposed to mend. #22 is why it is a table and not a sentence: the
    /// validator gained a rule the sanitizer already happened to satisfy, and
    /// nothing held the two together, so the next rule would not have been
    /// noticed.
    @Test("a sanitized reply that has any usable concept in it validates", arguments: [
        // Names that differ only in case, which the installer resolves onto one
        // stored row and #22 made the validator refuse.
        [PackFile.PackConcept(name: "RAG", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "rag", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Rag", cluster: "B", definition: "d", dependencies: ["RAG"])],
        // Blank names and blank definitions, which the validator refuses.
        [PackFile.PackConcept(name: "  ", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Real", cluster: "A", definition: "   ", dependencies: []),
         PackFile.PackConcept(name: "Kept", cluster: " A ", definition: " d ", dependencies: ["  "])],
        // More dependencies than a Concept may declare, half of them invented.
        [PackFile.PackConcept(name: "Hub", cluster: "A", definition: "d",
                              dependencies: (0..<20).map { "Leaf \($0)" }),
         PackFile.PackConcept(name: "Leaf 0", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Leaf 1", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Leaf 2", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Leaf 3", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Leaf 4", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Leaf 5", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Leaf 6", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Leaf 7", cluster: "A", definition: "d", dependencies: []),
         PackFile.PackConcept(name: "Leaf 8", cluster: "A", definition: "d", dependencies: [])],
        // A three-Concept cycle with a self-reference hanging off it.
        [PackFile.PackConcept(name: "P", cluster: "A", definition: "d", dependencies: ["R", "P"]),
         PackFile.PackConcept(name: "Q", cluster: "A", definition: "d", dependencies: ["P"]),
         PackFile.PackConcept(name: "R", cluster: "A", definition: "d", dependencies: ["Q"])],
        // More Clusters than a Pack may have, each named by a Concept only.
        (0..<14).map {
            PackFile.PackConcept(name: "C\($0)", cluster: "Cluster \($0)",
                                 definition: "d", dependencies: $0 == 0 ? [] : ["C\($0 - 1)"])
        },
    ] as [[PackFile.PackConcept]])
    func sanitizedOutputValidates(concepts: [PackFile.PackConcept]) throws {
        let dirty = pack(specialty: "Not a cluster", clusters: ["A", "B", "A"],
                         concepts: concepts,
                         stages: [.init(title: "S", subtitle: "", concepts: ["Ghost", "  "])],
                         sources: (0..<40).map {
                             .init(name: "S\($0)", url: "https://s\($0).test/feed", category: "K")
                         })

        let clean = PackGenerator.sanitize(dirty)

        #expect(!clean.concepts.isEmpty, "the fixture must leave something to install")
        try PackValidator.validate(clean)
    }

    /// The one thing the sanitizer cannot mend, and must not pretend to. A
    /// reply with nothing usable in it stays empty, `noConcepts` refuses it, and
    /// the reader is told rather than handed a blank map.
    @Test("a reply with nothing usable in it stays refused")
    func nothingUsableIsStillRefused() {
        let clean = PackGenerator.sanitize(pack(concepts: [
            concept("", definition: "d"),
            concept("Nameless", definition: "  "),
        ]))

        #expect(clean.concepts.isEmpty)
        #expect(throws: PackValidationError.noConcepts) { try PackValidator.validate(clean) }
    }

    @Test("more suggested sources than a pack may carry are cut to the cap")
    func suggestedSourcesAreCapped() throws {
        let greedy = pack(concepts: [concept("N")],
                          sources: (0..<200).map {
                              .init(name: "S\($0)", url: "https://s\($0).test/feed", category: "K")
                          })

        let clean = PackGenerator.sanitize(greedy)

        #expect(clean.suggestedSources.count == PackFile.maxSuggestedSources)
        try PackValidator.validate(clean)
    }

    @Test("a cluster named twice draws one lane")
    func repeatedClustersAreOneCluster() throws {
        let clean = PackGenerator.sanitize(
            pack(clusters: ["A", "B", "A", " B "],
                 concepts: [concept("N", "A"), concept("M", " B ")])
        )

        #expect(clean.clusterOrder == ["A", "B"])
        try PackValidator.validate(clean)
    }

    /// Ordering, asserted rather than assumed: the cluster cap drops Concepts,
    /// and a Dependency on one of those is dangling by the time the validator
    /// looks. Scrubbing dependencies before capping clusters would leave it.
    @Test("a dependency on a concept the cluster cap dropped is scrubbed with it")
    func cappingClustersScrubsWhatDependedOnTheDropped() throws {
        var concepts = (0..<PackFile.maxClusters).map {
            concept("Kept \($0)", "Cluster \($0)")
        }
        concepts.append(concept("Dropped", "Cluster \(PackFile.maxClusters)"))
        concepts[0].dependencies = ["Dropped"]

        let clean = PackGenerator.sanitize(pack(specialty: nil, clusters: [], concepts: concepts))

        #expect(clean.clusterOrder.count == PackFile.maxClusters)
        #expect(!clean.concepts.contains { $0.name == "Dropped" })
        #expect(clean.concepts.first { $0.name == "Kept 0" }?.dependencies == [])
        try PackValidator.validate(clean)
    }

    @Test("a pack that named no specialty lane is not given one")
    func noSpecialtyStaysNone() throws {
        for named in [nil, "   "] as [String?] {
            let clean = PackGenerator.sanitize(pack(specialty: named, concepts: [concept("N")]))
            #expect(clean.specialtyCluster == nil)
            try PackValidator.validate(clean)
        }
    }

    @Test("a stage the scrub emptied goes with what was in it")
    func emptiedStagesAreDropped() throws {
        let clean = PackGenerator.sanitize(pack(
            concepts: [concept("N")],
            stages: [.init(title: "Real", subtitle: "", concepts: ["N", "N", "Ghost"]),
                     .init(title: "Ghosts only", subtitle: "", concepts: ["Ghost"])]
        ))

        #expect(clean.stages.map(\.title) == ["Real"])
        #expect(clean.stages.first?.concepts == ["N"], "a Concept is named once in a Stage")
        try PackValidator.validate(clean)
    }
}

// MARK: - What the device can reach, and what it sends

@Suite("Pack generation tiers and payload")
struct PackGeneratorTierTests {

    /// The two features degrade "the same three ways", so the two enums must
    /// reach the same tier from the same device. They are separate types on
    /// purpose — Explain's third tier says nothing and generation's says why —
    /// but *which* tier is one policy, and this is what holds it to one rather
    /// than a comment asking the next reader to remember (the lesson
    /// `UITestLaunchTests` already banked for the launch arguments).
    @Test("generation and Explain agree on what a device can reach",
          arguments: [(true, true), (true, false), (false, true), (false, false)])
    func generationAndExplainAgreeOnWhatADeviceCanReach(model: Bool, key: Bool) {
        let generation = PackGenerator.Tier.choose(modelAvailable: model, hasKey: key)
        let explain = ExplainTier.choose(modelAvailable: model, hasKey: key)

        switch explain {
        case .onDevice: #expect(generation == .onDevice)
        case .optIn: #expect(generation == .optIn)
        case .unavailable: #expect(generation == .unavailable)
        }
    }

    /// The Egress claim `PRIVACY.md` makes about this path, as a test rather
    /// than as a sentence in a document — which is #29's whole lesson.
    @Test("the opt-in path sends the field the reader typed and nothing else")
    func theOptInPathSendsOnlyTheField() {
        let prompt = PackGenerator.remotePrompt(field: "Marine Biology")

        #expect(prompt.user == "Field: Marine Biology")
        // The system half is fixed text: the shape of the reply and the rules
        // it must follow. Nothing of the reader's is interpolated into it.
        #expect(PackGenerator.remotePrompt(field: "Astrophysics").system == prompt.system)
        #expect(!prompt.system.contains("Marine Biology"))
    }

    /// The prompt names the shape the reply is decoded into. Swift's synthesized
    /// decoding does not fall back on a property's default, so a reply that
    /// omits `formatVersion` is not a Pack at all — and a prompt that stopped
    /// asking for it would fail every generation with "the reply wasn't a pack".
    @Test("the prompt asks for the shape the reply is decoded into")
    func thePromptDescribesTheFormat() {
        let system = PackGenerator.remotePrompt(field: "Anything").system

        for key in ["formatVersion", "field", "clusterOrder", "concepts",
                    "dependencies", "stages", "suggestedSources"] {
            #expect(system.contains(key), "the prompt never asks for “\(key)”")
        }
        #expect(system.contains("\(PackFile.currentFormatVersion)"))
        #expect(system.contains("\(PackFile.maxSuggestedSources)"))
        #expect(system.contains("\(PackFile.maxDependenciesPerConcept)"))
    }

    @Test("a typed field is trimmed and bounded")
    func fieldNamesAreBounded() {
        #expect(PackGenerator.normalize("  Site Reliability Engineering \n")
                == "Site Reliability Engineering")
        #expect(PackGenerator.normalize("").isEmpty)
        #expect(PackGenerator.normalize(String(repeating: "x", count: 500)).count
                == PackGenerator.maxFieldLength)
    }
}

// MARK: - Installing what came back

/// A generated Pack installs like any other, and is labelled as generated.
@MainActor
@Suite("Installing a generated Pack", .serialized)
struct GeneratedPackInstallTests {

    private static let store = TestStore()

    private func draft() -> PackDraft {
        PackDraft(file: PackFile(
            field: "Marine Biology",
            specialtyCluster: "Reefs",
            clusterOrder: ["Foundations", "Reefs"],
            concepts: [
                .init(name: "Salinity", cluster: "Foundations",
                      definition: "How much salt the water holds.", dependencies: []),
                .init(name: "RAG", cluster: "Reefs",
                      definition: "Ground answers in your data.", dependencies: ["Salinity"]),
            ],
            stages: [.init(title: "Stage 1 · Foundations", subtitle: "",
                           concepts: ["Salinity", "RAG"])],
            suggestedSources: []
        ), origin: .generated)
    }

    @Test("the record says the Pack was generated, and the reader is told")
    func installedAsGenerated() throws {
        let context = try Self.store.makeContext()

        let record = try PackInstaller.install(draft().file, origin: draft().origin,
                                               context: context, vector: { _ in nil })

        #expect(record.packOrigin == .generated)
        #expect(record.packOrigin.label == "Generated")
        #expect(ActivePackIdentity.recalled?.origin == .generated)
    }

    /// The same promise a Pack switch makes anywhere else: what you learned is
    /// yours, not the Pack's. Asserted for a generated Pack specifically because
    /// it is the one whose Concepts the reader never chose — a generated "RAG"
    /// arriving over a "RAG" they have been reading for a month must join that
    /// dot, not reset it.
    @Test("installing one keeps the mastery and history a concept already had")
    func masteryAndHistorySurvive() throws {
        let context = try Self.store.makeContext()
        let existing = Concept(name: "RAG", category: "Agents",
                               definition: "What the reader's own reading made of it.")
        existing.masteryLevel = 0.8
        existing.isMarkedKnown = true
        context.insert(existing)
        let firstSeen = existing.firstSeen
        try context.save()

        try PackInstaller.install(draft().file, origin: .generated,
                                  context: context, vector: { _ in nil })

        let rag = try #require(try context.fetch(FetchDescriptor<Concept>())
            .first { $0.name == "RAG" })
        #expect(rag.masteryLevel == 0.8)
        #expect(rag.isMarkedKnown)
        #expect(rag.firstSeen == firstSeen)
        #expect(rag.category == "Reefs", "the Pack's own Cluster is adopted")
        #expect(try context.fetch(FetchDescriptor<Concept>()).count == 2,
                "the generated Concept joined the dot that was there rather than twinning it")
    }
}
