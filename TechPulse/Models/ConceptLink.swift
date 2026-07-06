import SwiftData
import Foundation

@Model
final class ConceptLink {
    var conceptA: String        // Concept.name
    var conceptB: String
    var weight: Int             // co-occurrence count across articles

    init(conceptA: String, conceptB: String, weight: Int = 1) {
        self.conceptA = conceptA
        self.conceptB = conceptB
        self.weight = weight
    }
}
