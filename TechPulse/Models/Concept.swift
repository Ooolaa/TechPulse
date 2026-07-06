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
    }

    var masteryState: MasteryState {
        if isMarkedKnown || masteryLevel >= 0.8 { return .known }
        if masteryLevel > 0.15 { return .learning }
        return .new
    }
}
