import SwiftData
import Foundation

@Model
final class Article {
    @Attribute(.unique) var guid: String
    var title: String
    var content: String          // full text cached for offline
    var summary: String?         // generated on-device
    var publishedAt: Date
    var sourceName: String
    var isRead: Bool
    var readAt: Date?
    @Relationship var concepts: [Concept]

    init(guid: String, title: String, content: String,
         publishedAt: Date, sourceName: String) {
        self.guid = guid
        self.title = title
        self.content = content
        self.summary = nil
        self.publishedAt = publishedAt
        self.sourceName = sourceName
        self.isRead = false
        self.readAt = nil
        self.concepts = []
    }
}
