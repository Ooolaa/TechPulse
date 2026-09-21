import SwiftData
import Foundation

@Model
final class Concept {
    @Attribute(.unique) var name: String   // e.g. "RAG", "Swift Concurrency"
    var category: String
    var conceptDefinition: String          // one-line beginner explanation
    var masteryLevel: Double               // 0.0 (new) … 1.0 (mastered)
    var firstSeen: Date
    var lastReviewed: Date?
    var isMarkedKnown: Bool                // user said "I already know this"
    @Relationship(inverse: \Article.concepts) var articles: [Article]

    init(name: String, category: String, definition: String = "") {
        self.name = name
        self.category = category
        self.conceptDefinition = definition
        self.masteryLevel = 0.1            // new concept seen
        self.firstSeen = .now
        self.lastReviewed = nil
        self.isMarkedKnown = false
        self.articles = []
    }
}

extension Concept {
    /// Mastery state drives the app's single color code:
    /// gray = new, blue = learning, green = known.
    enum MasteryState {
        case new, learning, known

        /// The one place the three states are put into words.
        ///
        /// The map's legend and VoiceOver both read from here for the reason
        /// `ForceGraphView.edgeColor` is shared with the legend: a key that can
        /// drift from what it describes is worse than no key. A sighted reader
        /// sees "Learning" under a blue dot; a VoiceOver reader hears the same
        /// word for the same dot.
        var label: String {
            switch self {
            case .new: "New"
            case .learning: "Learning"
            case .known: "Known"
            }
        }
    }

    var masteryState: MasteryState {
        if isMarkedKnown || masteryLevel >= 0.8 { return .known }
        if masteryLevel > 0.15 { return .learning }
        return .new
    }
}
