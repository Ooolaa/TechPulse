import SwiftData
import Foundation

/// Where a Pack came from, and what the reader is told about it.
///
/// Stored as its raw value rather than as itself, because the store predates
/// this type and a record written by an older build must still read.
enum PackOrigin: String, Codable, Sendable, CaseIterable {
    case builtin
    case generated
    case imported

    var label: String {
        switch self {
        case .builtin: "Built-in"
        case .generated: "Generated"
        case .imported: "Imported"
        }
    }
}

/// A Pack that has been installed, remembered across launches.
///
/// The Concepts, Dependencies and Sources a Pack creates live in their own
/// tables — this record holds what is true of the Pack itself: which field it
/// covers, how its Clusters are ordered, its authored reading order, and which
/// Concepts belong to it. That last part is what lets a later install tell a
/// Pack's own Concepts from ones the reader's own reading discovered.
@Model
final class InstalledPack {
    var field: String
    var specialtyCluster: String?
    var clusterOrder: [String]
    /// Encoded `[PackFile.PackStage]` — SwiftData stores no array of structs.
    var stagesData: Data
    /// Encoded `[PackFile.PackSource]`. Held rather than re-read from
    /// `FeedSource` so exporting a Pack shares its author's suggestions, not
    /// the reader's own subscriptions.
    var suggestedSourcesData: Data
    /// Concept names in the Pack's authored order.
    var conceptNames: [String]
    /// The specialty Cluster's members, in authored order. Derived at install
    /// rather than recomputed, because it needs each Concept's Cluster and the
    /// record does not carry those.
    var sideQuestConcepts: [String] = []
    /// Where the Pack came from, as a `PackOrigin` raw value.
    var origin: String
    /// Which built-in Pack file this record is the app's copy of, for a Pack
    /// that came with the app. This is what says a record and a shipped Pack
    /// file are the same Pack: the file name is an identifier the app controls,
    /// where `field` is prose its author may rewrite (#19).
    ///
    /// Nil for a Pack the reader imported or generated, and for a built-in
    /// installed by a build that did not record it — `PackMigration` recognises
    /// those by field the once and writes the file name onto them.
    var builtinFileName: String?
    var isActive: Bool
    var installedAt: Date

    /// The Pack's origin, or `.imported` for a raw value no build understands
    /// — an unknown origin is at least not the app's own.
    var packOrigin: PackOrigin { PackOrigin(rawValue: origin) ?? .imported }

    init(field: String, specialtyCluster: String?, clusterOrder: [String],
         stages: [PackFile.PackStage], suggestedSources: [PackFile.PackSource],
         conceptNames: [String], sideQuestConcepts: [String], origin: PackOrigin,
         builtinFileName: String? = nil) {
        self.field = field
        self.specialtyCluster = specialtyCluster
        self.clusterOrder = clusterOrder
        self.stagesData = (try? JSONEncoder().encode(stages)) ?? Data()
        self.suggestedSourcesData = (try? JSONEncoder().encode(suggestedSources)) ?? Data()
        self.conceptNames = conceptNames
        self.sideQuestConcepts = sideQuestConcepts
        self.origin = origin.rawValue
        self.builtinFileName = builtinFileName
        self.isActive = true
        self.installedAt = .now
    }

    var stages: [PackFile.PackStage] {
        (try? JSONDecoder().decode([PackFile.PackStage].self, from: stagesData)) ?? []
    }

    var suggestedSources: [PackFile.PackSource] {
        (try? JSONDecoder().decode([PackFile.PackSource].self, from: suggestedSourcesData)) ?? []
    }
}
