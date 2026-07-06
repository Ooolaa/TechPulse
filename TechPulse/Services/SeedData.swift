import SwiftData
import Foundation

/// Default AI feed sources (user-editable in Settings), per build spec §8.
enum SeedData {
    static let defaultSources: [(name: String, url: String, category: String)] = [
        ("arXiv cs.AI", "https://export.arxiv.org/rss/cs.AI", "Research"),
        ("arXiv cs.LG", "https://export.arxiv.org/rss/cs.LG", "Research"),
        ("arXiv cs.CL", "https://export.arxiv.org/rss/cs.CL", "Research"),
        ("Hugging Face Blog", "https://huggingface.co/blog/feed.xml", "Open Source"),
        ("OpenAI News", "https://openai.com/news/rss.xml", "Frontier Labs"),
        ("Google DeepMind Blog", "https://deepmind.google/blog/rss.xml", "Frontier Labs"),
        ("MIT Technology Review — AI", "https://www.technologyreview.com/topic/artificial-intelligence/feed", "Industry"),
        ("The Verge — AI", "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", "Industry"),
        ("VentureBeat — AI", "https://venturebeat.com/category/ai/feed/", "Industry"),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<FeedSource>())) ?? 0
        guard count == 0 else { return }
        for source in defaultSources {
            guard let url = URL(string: source.url) else { continue }
            context.insert(FeedSource(name: source.name, url: url, category: source.category))
        }
        try? context.save()
    }
}
