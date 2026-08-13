import SwiftData
import Foundation

/// An undirected edge between two Concepts that mean related things (ADR-0002).
///
/// Its own model rather than a flag on `ConceptLink`: a Semantic Link is
/// derived from the Concepts themselves and is rebuilt whenever a Pack is
/// installed, while a Co-read Link is a record of what the reader actually
/// read and must never be thrown away. Storing them together would make
/// "recompute the derived ones" impossible to express safely.
@Model
final class SemanticLink {
    var conceptA: String        // Concept.name, sorted before conceptB
    var conceptB: String
    /// 0...1 — how strongly the two are related, for a renderer to scale by.
    var strength: Double

    init(conceptA: String, conceptB: String, strength: Double) {
        self.conceptA = conceptA
        self.conceptB = conceptB
        self.strength = strength
    }
}
