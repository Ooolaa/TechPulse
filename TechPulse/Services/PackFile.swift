import Foundation

// MARK: - The portable Pack file format (JSON)

/// A Pack as it travels: a field's worth of Concepts, their Clusters, their
/// Dependencies, a staged reading order and a suggested set of Sources.
///
/// This is the interchange format — authored by hand, generated, exported and
/// installed. It is plain `Codable` data with no SwiftData or store types in
/// it, so a file can be read and checked before anything is installed from it.
struct PackFile: Codable, Equatable {

    /// One dot on the map, with the Concepts it should be learned after.
    struct PackConcept: Codable, Equatable {
        var name: String
        var cluster: String
        var definition: String
        /// Names of Concepts in this same Pack to learn first — the authored
        /// Dependency edges, pointing at this Concept.
        var dependencies: [String]
    }

    /// A step in the Pack's reading order ("You are here").
    struct PackStage: Codable, Equatable {
        var title: String
        var subtitle: String
        var concepts: [String]
    }

    /// A Source the Pack's author suggests subscribing to — offered on install,
    /// never subscribed to on the reader's behalf.
    struct PackSource: Codable, Equatable {
        var name: String
        var url: String
        /// The Source's own topic label ("LLMs", "Vision"), mirroring
        /// `FeedSource.category`. Not a Cluster — Sources are grouped for the
        /// reader's benefit and need not line up with `clusterOrder`.
        var category: String
    }

    /// The only format version this build can read. Bumping it is a breaking
    /// change: older builds reject the new files rather than misreading them.
    static let currentFormatVersion = 1

    /// Bounds a Pack must sit inside to be installable. A Pack past these is
    /// not a richer map, it is a file that will not draw or navigate.
    static let maxConcepts = 120
    static let maxClusters = 10
    static let maxDependenciesPerConcept = 8

    var formatVersion: Int = PackFile.currentFormatVersion
    /// What the map covers — "AI Engineering", "Data Science".
    var field: String
    /// The Cluster given the full-width lane, if the author named one.
    var specialtyCluster: String?
    /// Cluster display order; also the set of Clusters Concepts may claim.
    var clusterOrder: [String]
    var concepts: [PackConcept]
    var stages: [PackStage]
    var suggestedSources: [PackSource]
}

// MARK: - Validation

/// Why a Pack was rejected. Every case carries enough to name the offending
/// part of the file, because the reader has to be able to go and fix it.
enum PackValidationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case noConcepts
    case tooManyConcepts(Int)
    case badClusterCount(Int)
    case emptyDefinition(String)
    case duplicateConcept(String)
    case danglingDependency(concept: String, missing: String)
    case tooManyDependencies(String)
    case dependencyCycle
    case unknownStageConcept(String)
    case conceptInUnknownCluster(concept: String, cluster: String)
    case unknownSpecialtyCluster(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported pack format version \(version) — this app reads version \(PackFile.currentFormatVersion)."
        case .noConcepts:
            "The pack has no concepts."
        case .tooManyConcepts(let count):
            "Too many concepts (\(count) > \(PackFile.maxConcepts))."
        case .badClusterCount(let count):
            "Packs need 1–\(PackFile.maxClusters) clusters (got \(count))."
        case .emptyDefinition(let name):
            "Concept “\(name)” has no definition."
        case .duplicateConcept(let name):
            "The pack contains two concepts named “\(name)”."
        case .danglingDependency(let concept, let missing):
            "“\(concept)” depends on “\(missing)”, which the pack does not contain."
        case .tooManyDependencies(let name):
            "“\(name)” has more than \(PackFile.maxDependenciesPerConcept) dependencies."
        case .dependencyCycle:
            "The dependency graph contains a cycle."
        case .unknownStageConcept(let name):
            "A stage references unknown concept “\(name)”."
        case .conceptInUnknownCluster(let concept, let cluster):
            "“\(concept)” belongs to “\(cluster)”, which is not in clusterOrder."
        case .unknownSpecialtyCluster(let cluster):
            "The specialty cluster “\(cluster)” is not in clusterOrder."
        case .unreadable(let detail):
            "This is not a readable pack file — \(detail)."
        }
    }

    /// Turns a decoder's complaint into something a reader can act on: which
    /// part of their file is missing or the wrong shape.
    static func unreadable(decoding error: any Error) -> PackValidationError {
        guard let error = error as? DecodingError else {
            return .unreadable("the file could not be read")
        }
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }
            return keys.isEmpty ? "the pack" : "“\(keys.joined(separator: "."))”"
        }
        return switch error {
        case .keyNotFound(let key, let context):
            .unreadable("\(path(context)) is missing “\(key.stringValue)”")
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            .unreadable("\(path(context)) is the wrong shape")
        case .dataCorrupted:
            .unreadable("it is not valid JSON")
        @unknown default:
            .unreadable("the file could not be read")
        }
    }
}

/// Checks a Pack before anything is installed from it.
///
/// Pure by construction: no store access, no network, no `UserDefaults` — a
/// `PackFile` in, a thrown `PackValidationError` or nothing out. Never trust a
/// pack, whether it was generated, imported or shipped with the app.
enum PackValidator {

    static func validate(_ pack: PackFile) throws {
        guard pack.formatVersion == PackFile.currentFormatVersion else {
            throw PackValidationError.unsupportedVersion(pack.formatVersion)
        }
        guard !pack.concepts.isEmpty else { throw PackValidationError.noConcepts }
        guard pack.concepts.count <= PackFile.maxConcepts else {
            throw PackValidationError.tooManyConcepts(pack.concepts.count)
        }
        guard (1...PackFile.maxClusters).contains(pack.clusterOrder.count) else {
            throw PackValidationError.badClusterCount(pack.clusterOrder.count)
        }

        // Names must be unique before anything indexes by them — a duplicate
        // would otherwise silently overwrite its twin on install.
        var names: Set<String> = []
        for concept in pack.concepts {
            guard names.insert(concept.name).inserted else {
                throw PackValidationError.duplicateConcept(concept.name)
            }
        }

        let clusters = Set(pack.clusterOrder)
        if let specialty = pack.specialtyCluster, !clusters.contains(specialty) {
            throw PackValidationError.unknownSpecialtyCluster(specialty)
        }

        for concept in pack.concepts {
            guard !concept.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PackValidationError.emptyDefinition(concept.name)
            }
            guard concept.dependencies.count <= PackFile.maxDependenciesPerConcept else {
                throw PackValidationError.tooManyDependencies(concept.name)
            }
            guard clusters.contains(concept.cluster) else {
                throw PackValidationError.conceptInUnknownCluster(concept: concept.name,
                                                                 cluster: concept.cluster)
            }
            for dependency in concept.dependencies where !names.contains(dependency) {
                throw PackValidationError.danglingDependency(concept: concept.name,
                                                            missing: dependency)
            }
        }

        for stage in pack.stages {
            for name in stage.concepts where !names.contains(name) {
                throw PackValidationError.unknownStageConcept(name)
            }
        }

        try checkAcyclic(pack)
    }

    /// Kahn's algorithm: the Dependency graph must be a DAG, or the Frontier
    /// has no starting point and the reading order never terminates.
    private static func checkAcyclic(_ pack: PackFile) throws {
        var remaining = Dictionary(uniqueKeysWithValues:
            pack.concepts.map { ($0.name, $0.dependencies.count) })
        var dependents: [String: [String]] = [:]
        for concept in pack.concepts {
            for dependency in concept.dependencies {
                dependents[dependency, default: []].append(concept.name)
            }
        }

        var queue = remaining.filter { $0.value == 0 }.map(\.key)
        var settled = 0
        while let name = queue.popLast() {
            settled += 1
            for dependent in dependents[name] ?? [] {
                remaining[dependent]? -= 1
                if remaining[dependent] == 0 { queue.append(dependent) }
            }
        }
        guard settled == pack.concepts.count else { throw PackValidationError.dependencyCycle }
    }

    /// Just enough of a Pack to learn what format it claims to be in.
    private struct FormatProbe: Decodable {
        var formatVersion: Int
    }

    /// Reads Pack bytes and checks them. Every failure is a
    /// `PackValidationError`, so there is always a reason to show the reader.
    static func decodeAndValidate(_ data: Data) throws -> PackFile {
        // The version is read before the body: a file in some later format
        // would otherwise be reported as a missing key rather than as the
        // unsupported version it actually is.
        let probe: FormatProbe
        do {
            probe = try JSONDecoder().decode(FormatProbe.self, from: data)
        } catch {
            throw PackValidationError.unreadable(decoding: error)
        }
        guard probe.formatVersion == PackFile.currentFormatVersion else {
            throw PackValidationError.unsupportedVersion(probe.formatVersion)
        }

        let pack: PackFile
        do {
            pack = try JSONDecoder().decode(PackFile.self, from: data)
        } catch {
            throw PackValidationError.unreadable(decoding: error)
        }
        try validate(pack)
        return pack
    }
}
