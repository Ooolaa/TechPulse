import Foundation
import SwiftData

/// Fetches all enabled feed sources and caches new articles in SwiftData.
/// Offline-first: failures are silently skipped; whatever is cached stays readable.
@MainActor
enum FeedSyncService {
    /// Newest items kept per feed per sync (arXiv daily feeds can carry hundreds).
    private static let perFeedLimit = 30

    @discardableResult
    static func syncAll(context: ModelContext) async -> Int {
        let enabled = FetchDescriptor<FeedSource>(predicate: #Predicate { $0.isEnabled })
        guard let sources = try? context.fetch(enabled), !sources.isEmpty else { return 0 }

        var knownGuids = Set(((try? context.fetch(FetchDescriptor<Article>())) ?? []).map(\.guid))
        var added = 0

        for source in sources {
            guard let (data, response) = try? await URLSession.shared.data(from: source.url) else { continue }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { continue }

            for item in RSSParser.parse(data).prefix(perFeedLimit) {
                guard !item.guid.isEmpty, !knownGuids.contains(item.guid) else { continue }
                // Some publishers post-date RSS timestamps; clamp so the feed
                // never shows articles from "the future".
                let article = Article(
                    guid: item.guid,
                    title: item.title.strippingHTML,
                    content: item.content,
                    publishedAt: min(item.publishedAt ?? .now, .now),
                    sourceName: source.name
                )
                context.insert(article)
                knownGuids.insert(item.guid)
                added += 1
            }
            source.lastFetched = .now
        }
        prune(context: context)
        try? context.save()
        return added
    }

    /// Cap the offline cache: read articles older than 60 days are deleted.
    /// Concepts and learning history are never pruned — the map only grows.
    private static func prune(context: ModelContext) {
        let cutoff = Date.now.addingTimeInterval(-60 * 86_400)
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.isRead && $0.publishedAt < cutoff }
        )
        for article in (try? context.fetch(descriptor)) ?? [] {
            context.delete(article)
        }
    }
}
