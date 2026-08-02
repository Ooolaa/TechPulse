import SwiftData
import Foundation

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
    /// Where the Pack came from: "builtin", "generated" or "imported".
    var origin: String
    var isActive: Bool
    var installedAt: Date

    init(field: String, specialtyCluster: String?, clusterOrder: [String],
         stages: [PackFile.PackStage], suggestedSources: [PackFile.PackSource],
         conceptNames: [String], sideQuestConcepts: [String], origin: String) {
        self.field = field
        self.specialtyCluster = specialtyCluster
        self.clusterOrder = clusterOrder
        self.stagesData = (try? JSONEncoder().encode(stages)) ?? Data()
        self.suggestedSourcesData = (try? JSONEncoder().encode(suggestedSources)) ?? Data()
        self.conceptNames = conceptNames
        self.sideQuestConcepts = sideQuestConcepts
        self.origin = origin
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
