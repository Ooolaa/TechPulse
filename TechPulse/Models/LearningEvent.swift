import SwiftData
import Foundation

@Model
final class LearningEvent {
    var date: Date
    var kind: String             // "read", "markedKnown", "quizPassed"
    var conceptName: String
    var masteryDelta: Double

    init(kind: String, conceptName: String, masteryDelta: Double, date: Date = .now) {
        self.date = date
        self.kind = kind
        self.conceptName = conceptName
        self.masteryDelta = masteryDelta
    }
}
