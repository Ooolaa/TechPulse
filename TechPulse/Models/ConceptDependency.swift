import SwiftData
import Foundation

/// Directed prerequisite edge from the knowledge pack:
/// you're "ready to learn" `dependent` once `prerequisite` is lit.
@Model
final class ConceptDependency {
    var prerequisite: String    // Concept.name
    var dependent: String       // Concept.name

    init(prerequisite: String, dependent: String) {
        self.prerequisite = prerequisite
        self.dependent = dependent
    }
}
