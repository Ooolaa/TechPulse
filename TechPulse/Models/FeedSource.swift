import SwiftData
import Foundation

@Model
final class FeedSource {
    var name: String
    var url: URL
    var category: String        // graph cluster: "LLMs", "Agents", "Vision", ...
    var isEnabled: Bool
    var lastFetched: Date?

    init(name: String, url: URL, category: String, isEnabled: Bool = true) {
        self.name = name
        self.url = url
        self.category = category
        self.isEnabled = isEnabled
        self.lastFetched = nil
    }
}
