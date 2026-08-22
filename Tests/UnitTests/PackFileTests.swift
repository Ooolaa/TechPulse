import Testing
import Foundation
@testable import TechPulse

/// The Pack file format and its validator. Every rejection reason
/// `PackValidationError` can produce has a test here — a reader handed a
/// malformed Pack must get a message, never a corrupted map.
@Suite("Pack file format")
struct PackFileTests {

    // MARK: - Builders

    /// A minimal well-formed Pack. Each test bends one thing about it.
    private func pack(
        formatVersion: Int = PackFile.currentFormatVersion,
        clusterOrder: [String] = ["Foundations", "Agents"],
        specialtyCluster: String? = "Agents",
        concepts: [PackFile.PackConcept] = [
            .init(name: "Embeddings", cluster: "Foundations",
                  definition: "Meaning as vectors.", dependencies: []),
            .init(name: "RAG", cluster: "Agents",
                  definition: "Ground answers in your data.", dependencies: ["Embeddings"]),
        ],
        // Stages are opt-in: a test bending the Concepts would otherwise trip
        // the stage check before reaching the rule it is about.
        stages: [PackFile.PackStage] = [],
        suggestedSources: [PackFile.PackSource] = [
            .init(name: "Import AI", url: "https://jack-clark.net/feed", category: "LLMs"),
        ]
    ) -> PackFile {
        PackFile(formatVersion: formatVersion, field: "AI Engineering",
                 specialtyCluster: specialtyCluster, clusterOrder: clusterOrder,
                 concepts: concepts, stages: stages, suggestedSources: suggestedSources)
    }

    private func concepts(_ count: Int, cluster: String = "Foundations") -> [PackFile.PackConcept] {
        (0..<count).map {
            .init(name: "Concept \($0)", cluster: cluster, definition: "d", dependencies: [])
        }
    }

    /// Suggestions on distinct hosts, so a count is all that separates them —
    /// the cap counts Sources, not the servers behind them.
    private func sources(_ count: Int) -> [PackFile.PackSource] {
        (0..<count).map {
            .init(name: "Feed \($0)", url: "https://feed-\($0).test/rss", category: "LLMs")
        }
    }

    /// The error thrown by `validate`, or `nil` if it accepted the Pack.
    private func rejection(_ file: PackFile) -> PackValidationError? {
        reason { try PackValidator.validate(file) }
    }

    /// The error thrown by `decodeAndValidate`, or `nil` if it accepted the bytes.
    private func decodeRejection(_ data: Data) -> PackValidationError? {
        reason { _ = try PackValidator.decodeAndValidate(data) }
    }

    /// Every way in must fail as a `PackValidationError` — a reader always
    /// gets a reason, never a raw decoder complaint.
    private func reason(_ body: () throws -> Void) -> PackValidationError? {
        do {
            try body()
            return nil
        } catch let error as PackValidationError {
            return error
        } catch {
            Issue.record("threw a non-PackValidationError: \(error)")
            return nil
        }
    }

    // MARK: - Decoding

    @Test("a well-formed Pack decodes into Concepts, Clusters, Dependencies, stages and Sources")
    func decodesWellFormedPack() throws {
        let json = """
        {
          "formatVersion": 1,
          "field": "AI Engineering",
          "specialtyCluster": "On-Device AI",
          "clusterOrder": ["Foundations", "On-Device AI"],
          "concepts": [
            {"name": "Embeddings", "cluster": "Foundations",
             "definition": "Meaning as vectors.", "dependencies": []},
            {"name": "Core ML", "cluster": "On-Device AI",
             "definition": "Apple's model deployment runtime.", "dependencies": ["Embeddings"]}
          ],
          "stages": [
            {"title": "Stage 1 · Foundations", "subtitle": "Start here",
             "concepts": ["Embeddings"]}
          ],
          "suggestedSources": [
            {"name": "Import AI", "url": "https://jack-clark.net/feed", "category": "LLMs"}
          ]
        }
        """

        let file = try PackValidator.decodeAndValidate(Data(json.utf8))

        #expect(file.formatVersion == 1)
        #expect(file.field == "AI Engineering")
        #expect(file.clusterOrder == ["Foundations", "On-Device AI"])
        #expect(file.specialtyCluster == "On-Device AI")
        #expect(file.concepts.map(\.name) == ["Embeddings", "Core ML"])
        #expect(file.concepts[1].cluster == "On-Device AI")
        #expect(file.concepts[1].definition == "Apple's model deployment runtime.")
        #expect(file.concepts[1].dependencies == ["Embeddings"])
        #expect(file.stages.map(\.title) == ["Stage 1 · Foundations"])
        #expect(file.stages[0].subtitle == "Start here")
        #expect(file.stages[0].concepts == ["Embeddings"])
        #expect(file.suggestedSources.map(\.name) == ["Import AI"])
        #expect(file.suggestedSources[0].url == "https://jack-clark.net/feed")
        #expect(file.suggestedSources[0].category == "LLMs")
    }

    @Test("specialtyCluster is optional — a Pack without one decodes")
    func specialtyClusterIsOptional() throws {
        let json = """
        {
          "formatVersion": 1,
          "field": "Data Science",
          "clusterOrder": ["Foundations"],
          "concepts": [{"name": "Pandas", "cluster": "Foundations",
                        "definition": "Dataframes.", "dependencies": []}],
          "stages": [],
          "suggestedSources": []
        }
        """

        let file = try PackValidator.decodeAndValidate(Data(json.utf8))
        #expect(file.specialtyCluster == nil)
    }

    @Test("a Pack survives a round trip through JSON")
    func roundTrips() throws {
        let original = pack(stages: [
            .init(title: "Stage 1", subtitle: "Start here", concepts: ["Embeddings"]),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try PackValidator.decodeAndValidate(data)
        #expect(decoded == original)
    }

    @Test("a well-formed Pack is accepted")
    func acceptsWellFormedPack() throws {
        try PackValidator.validate(pack(stages: [
            .init(title: "Stage 1", subtitle: "Start here", concepts: ["Embeddings", "RAG"]),
        ]))
    }

    // MARK: - Versioning

    @Test("an unsupported format version is rejected with a readable reason")
    func rejectsUnsupportedVersion() {
        let error = rejection(pack(formatVersion: 99))
        #expect(error == .unsupportedVersion(99))
        #expect(error?.errorDescription?.contains("99") == true)
    }

    @Test("a format version older than the supported one is rejected too")
    func rejectsOlderVersion() {
        #expect(rejection(pack(formatVersion: 0)) == .unsupportedVersion(0))
    }

    // MARK: - Dependencies

    @Test("a Dependency naming a Concept the Pack does not contain is rejected, naming both")
    func rejectsDanglingDependency() {
        let file = pack(concepts: [
            .init(name: "RAG", cluster: "Foundations", definition: "d",
                  dependencies: ["Vector Databases"]),
        ])

        let error = rejection(file)
        #expect(error == .danglingDependency(concept: "RAG", missing: "Vector Databases"))
        let reason = error?.errorDescription ?? ""
        #expect(reason.contains("RAG"))
        #expect(reason.contains("Vector Databases"))
    }

    @Test("a Concept with more Dependencies than the format allows is rejected, naming it")
    func rejectsTooManyDependencies() {
        var all = concepts(PackFile.maxDependenciesPerConcept + 1)
        all.append(.init(name: "Overloaded", cluster: "Foundations", definition: "d",
                         dependencies: all.map(\.name)))

        let error = rejection(pack(concepts: all))
        #expect(error == .tooManyDependencies("Overloaded"))
        #expect(error?.errorDescription?.contains("Overloaded") == true)
    }

    @Test("a cycle in the Dependency graph is rejected")
    func rejectsDependencyCycle() {
        let file = pack(concepts: [
            .init(name: "A", cluster: "Foundations", definition: "d", dependencies: ["C"]),
            .init(name: "B", cluster: "Foundations", definition: "d", dependencies: ["A"]),
            .init(name: "C", cluster: "Foundations", definition: "d", dependencies: ["B"]),
        ])

        #expect(rejection(file) == .dependencyCycle)
    }

    @Test("a Concept depending on itself is rejected")
    func rejectsSelfDependency() {
        let file = pack(concepts: [
            .init(name: "A", cluster: "Foundations", definition: "d", dependencies: ["A"]),
        ])

        #expect(rejection(file) == .dependencyCycle)
    }

    // MARK: - Concepts

    @Test("a Concept with no definition is rejected, naming it")
    func rejectsEmptyDefinition() {
        let file = pack(concepts: [
            .init(name: "Attention", cluster: "Foundations", definition: "", dependencies: []),
        ])

        let error = rejection(file)
        #expect(error == .emptyDefinition("Attention"))
        #expect(error?.errorDescription?.contains("Attention") == true)
    }

    @Test("a definition of nothing but whitespace counts as no definition")
    func rejectsWhitespaceDefinition() {
        let file = pack(concepts: [
            .init(name: "Attention", cluster: "Foundations", definition: "  \n\t ",
                  dependencies: []),
        ])

        #expect(rejection(file) == .emptyDefinition("Attention"))
    }

    @Test("two Concepts sharing a name are rejected, naming the name")
    func rejectsDuplicateConcepts() {
        let file = pack(concepts: [
            .init(name: "RAG", cluster: "Foundations", definition: "d", dependencies: []),
            .init(name: "RAG", cluster: "Agents", definition: "d", dependencies: []),
        ])

        let error = rejection(file)
        #expect(error == .duplicateConcept(first: "RAG", second: "RAG"))
        #expect(error?.errorDescription?.contains("RAG") == true)
    }

    @Test("two Concepts differing only in case are rejected — install would collapse them")
    func rejectsCaseDifferingDuplicateConcepts() {
        // The installer resolves a Pack's names against the store without
        // regard to case, so “RAG” and “rag” can land on one Concept. Two
        // names that can become one must not get past the validator.
        let file = pack(concepts: [
            .init(name: "RAG", cluster: "Foundations", definition: "d", dependencies: []),
            .init(name: "rag", cluster: "Agents", definition: "d", dependencies: []),
        ])

        // Both spellings are named: an author told only about “rag” would
        // search their file, find one entry, and conclude the error is wrong.
        let error = rejection(file)
        #expect(error == .duplicateConcept(first: "RAG", second: "rag"))
        let reason = error?.errorDescription ?? ""
        #expect(reason.contains("RAG"))
        #expect(reason.contains("rag"))
    }

    @Test("a Concept in a Cluster the Pack does not list is rejected, naming both")
    func rejectsConceptInUnknownCluster() {
        let file = pack(concepts: [
            .init(name: "Kubernetes", cluster: "Infra", definition: "d", dependencies: []),
        ])

        let error = rejection(file)
        #expect(error == .conceptInUnknownCluster(concept: "Kubernetes", cluster: "Infra"))
        let reason = error?.errorDescription ?? ""
        #expect(reason.contains("Kubernetes"))
        #expect(reason.contains("Infra"))
    }

    // MARK: - Bounds

    @Test("a Pack with no Concepts is rejected")
    func rejectsNoConcepts() {
        let file = pack(concepts: [])
        #expect(rejection(file) == .noConcepts)
    }

    @Test("a Pack with more Concepts than the format allows is rejected, naming the count")
    func rejectsTooManyConcepts() {
        let over = PackFile.maxConcepts + 1
        let file = pack(concepts: concepts(over))

        let error = rejection(file)
        #expect(error == .tooManyConcepts(over))
        #expect(error?.errorDescription?.contains("\(over)") == true)
    }

    @Test("a Pack at exactly the Concept limit is accepted")
    func acceptsConceptLimit() throws {
        try PackValidator.validate(pack(concepts: concepts(PackFile.maxConcepts)))
    }

    @Test("a Pack with no Clusters is rejected")
    func rejectsNoClusters() {
        let file = pack(clusterOrder: [], specialtyCluster: nil)
        #expect(rejection(file) == .badClusterCount(0))
    }

    @Test("a Pack with more Clusters than the format allows is rejected, naming the count")
    func rejectsTooManyClusters() {
        let over = PackFile.maxClusters + 1
        let file = pack(clusterOrder: (0..<over).map { "Cluster \($0)" },
                        specialtyCluster: nil,
                        concepts: concepts(1, cluster: "Cluster 0"))

        let error = rejection(file)
        #expect(error == .badClusterCount(over))
        #expect(error?.errorDescription?.contains("\(over)") == true)
    }

    @Test("a Pack suggesting more Sources than the format allows is rejected, naming the count")
    func rejectsTooManySuggestedSources() {
        let over = PackFile.maxSuggestedSources + 1
        let file = pack(suggestedSources: sources(over))

        let error = rejection(file)
        #expect(error == .tooManySuggestedSources(over))
        #expect(error?.errorDescription?.contains("\(over)") == true)
    }

    @Test("a Pack at exactly the suggested-Source limit is accepted")
    func acceptsSuggestedSourceLimit() throws {
        try PackValidator.validate(pack(suggestedSources: sources(PackFile.maxSuggestedSources)))
    }

    /// The cap is on the file, so it is enforced on the way in from bytes and
    /// not only against a `PackFile` some other code already built. An import
    /// is the only way an over-cap Pack can reach a reader at all.
    @Test("an over-cap Pack is rejected on decode, not merely on validate")
    func rejectsTooManySuggestedSourcesOnDecode() throws {
        let over = PackFile.maxSuggestedSources + 1
        let data = try JSONEncoder().encode(pack(suggestedSources: sources(over)))

        #expect(decodeRejection(data) == .tooManySuggestedSources(over))
    }

    @Test("a Pack at exactly the Cluster limit is accepted")
    func acceptsClusterLimit() throws {
        let file = pack(clusterOrder: (0..<PackFile.maxClusters).map { "Cluster \($0)" },
                        specialtyCluster: nil,
                        concepts: concepts(1, cluster: "Cluster 0"))
        try PackValidator.validate(file)
    }

    // MARK: - Stages and the specialty Cluster

    @Test("a stage referencing an unknown Concept is rejected, naming it")
    func rejectsUnknownStageConcept() {
        let file = pack(stages: [
            .init(title: "Stage 1", subtitle: "s", concepts: ["Embeddings", "Ghost Concept"]),
        ])

        let error = rejection(file)
        #expect(error == .unknownStageConcept("Ghost Concept"))
        #expect(error?.errorDescription?.contains("Ghost Concept") == true)
    }

    @Test("a specialty Cluster the Pack does not list is rejected, naming it")
    func rejectsUnknownSpecialtyCluster() {
        let file = pack(specialtyCluster: "Robotics")

        let error = rejection(file)
        #expect(error == .unknownSpecialtyCluster("Robotics"))
        #expect(error?.errorDescription?.contains("Robotics") == true)
    }

    // MARK: - Malformed bytes

    @Test("bytes that are not JSON at all are rejected with a readable reason")
    func rejectsMalformedJSON() {
        let error = decodeRejection(Data("not a pack".utf8))
        #expect(error == .unreadable("it is not valid JSON"))
        #expect(error?.errorDescription?.isEmpty == false)
    }

    @Test("a Pack missing a required key names the key")
    func rejectsMissingKey() {
        let json = """
        {"formatVersion": 1, "field": "AI", "clusterOrder": ["Foundations"],
         "stages": [], "suggestedSources": []}
        """

        let error = decodeRejection(Data(json.utf8))
        #expect(error?.errorDescription?.contains("concepts") == true)
    }

    @Test("a Pack whose value is the wrong shape is rejected, naming where")
    func rejectsWrongShape() {
        let json = """
        {"formatVersion": 1, "field": "AI", "clusterOrder": "Foundations",
         "concepts": [], "stages": [], "suggestedSources": []}
        """

        let error = decodeRejection(Data(json.utf8))
        #expect(error?.errorDescription?.contains("clusterOrder") == true)
    }

    @Test("a file in a later format reports its version, not a missing key")
    func futureFormatReportsItsVersion() {
        // A version-2 file is free to have dropped every key this build needs;
        // the reader must still be told it is a newer pack, not a broken one.
        let error = decodeRejection(Data(#"{"formatVersion": 2}"#.utf8))
        #expect(error == .unsupportedVersion(2))
    }

    @Test("bytes with no format version at all are rejected as unreadable")
    func rejectsMissingFormatVersion() {
        let error = decodeRejection(Data("{}".utf8))
        #expect(error?.errorDescription?.contains("formatVersion") == true)
    }

    @Test("decodeAndValidate rejects a decodable but invalid Pack")
    func decodeAndValidateValidates() throws {
        let data = try JSONEncoder().encode(pack(formatVersion: 42))
        #expect(throws: PackValidationError.unsupportedVersion(42)) {
            try PackValidator.decodeAndValidate(data)
        }
    }

    // MARK: - Every reason is readable

    @Test("every rejection reason has a non-empty, readable description")
    func everyReasonIsReadable() {
        let reasons: [PackValidationError] = [
            .unsupportedVersion(9), .noConcepts, .tooManyConcepts(999), .badClusterCount(0),
            .tooManySuggestedSources(500),
            .emptyDefinition("A"),
            // Both readings of one case: the same name twice, and two
            // spellings of it. They word themselves differently.
            .duplicateConcept(first: "A", second: "A"),
            .duplicateConcept(first: "A", second: "a"),
            .danglingDependency(concept: "A", missing: "B"), .tooManyDependencies("A"),
            .dependencyCycle, .unknownStageConcept("A"),
            .conceptInUnknownCluster(concept: "A", cluster: "C"),
            .unknownSpecialtyCluster("C"), .unreadable("it is not valid JSON"),
        ]

        for reason in reasons {
            #expect(reason.errorDescription?.isEmpty == false,
                    "\(reason) has no readable description")
        }
    }
}
