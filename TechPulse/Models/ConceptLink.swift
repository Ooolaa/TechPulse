import SwiftData
import Foundation

/// An undirected edge between two Concepts the reader has met together in the
/// same reading (ADR-0002). Observed, never authored.
///
/// Derived rather than accumulated: `KnowledgeEngine.rebuildCoreadLinks`
/// recomputes the whole table from the readings that justify it. The reading
/// record is the truth; this is a scored view of it.
@Model
final class ConceptLink {
    var conceptA: String        // Concept.name, sorted before conceptB
    var conceptB: String
    /// How many readings joined the two — the raw observation behind `strength`.
    var weight: Int
    /// 0...1 — strength of association, not a raw count. Defaulted so stores
    /// written before scoring existed open cleanly; the first rebuild fills it.
    var strength: Double = 0

    init(conceptA: String, conceptB: String, weight: Int = 1, strength: Double = 0) {
        self.conceptA = conceptA
        self.conceptB = conceptB
        self.weight = weight
        self.strength = strength
    }
}
