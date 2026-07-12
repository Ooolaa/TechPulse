import Foundation
import SwiftData

/// Fetches all enabled feed sources and caches new articles in SwiftData.
/// Offline-first: failures are silently skipped; whatever is cached stays readable.
@MainActor
enum FeedSyncService {
    /// Newest items parsed per feed per sync (arXiv daily feeds can carry hundreds).
    private static let perFeedLimit = 30

    /// Daily intake cap across ALL feeds. 30 fresh articles a day is plenty
    /// for a starting reader — an overflowing feed kills the habit
    /// (Atomic Habits: make it easy; an achievable pile gets opened).
    private static let dailyIntakeLimit = 30

    @discardableResult
    static func syncAll(context: ModelContext) async -> Int {
        let enabled = FetchDescriptor<FeedSource>(predicate: #Predicate { $0.isEnabled })
        guard let sources = try? context.fetch(enabled), !sources.isEmpty else { return 0 }

        // Fetch all feeds concurrently (network-bound), then parse/insert on
        // the main actor. Cuts a cold sync from ~sum to ~max of feed latencies.
        let requests = sources.enumerated().map { (index: $0.offset, url: $0.element.url) }
        let payloads = await withTaskGroup(of: (Int, Data?).self) { group in
            for request in requests {
                group.addTask {
                    guard let (data, response) = try? await URLSession.shared.data(from: request.url),
                          (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
                    else { return (request.index, nil) }
                    return (request.index, data)
                }
            }
            var results = [Int: Data]()
            for await (index, data) in group {
                if let data { results[index] = data }
            }
            return results
        }

        let existing = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        var knownGuids = Set(existing.map(\.guid))

        // Enforce the daily intake cap: count what was already cached today.
        let todayStart = Calendar.current.startOfDay(for: .now)
        let addedToday = existing.count { ($0.addedAt ?? .distantPast) >= todayStart }
        var allowance = max(0, dailyIntakeLimit - addedToday)
        var added = 0

        // Pool candidates across all feeds, newest first, so the cap keeps the
        // best (freshest) 30 rather than whichever feed happened to come first.
        var candidates: [(sourceName: String, item: ParsedFeedItem)] = []
        for (index, source) in sources.enumerated() {
            guard let data = payloads[index] else { continue }
            for item in RSSParser.parse(data).prefix(perFeedLimit) {
                candidates.append((source.name, item))
            }
            source.lastFetched = .now
        }
        candidates.sort { ($0.item.publishedAt ?? .now) > ($1.item.publishedAt ?? .now) }

        for candidate in candidates {
            guard allowance > 0 else { break }
            let item = candidate.item
            guard !item.guid.isEmpty, !knownGuids.contains(item.guid) else { continue }
            // Some publishers post-date RSS timestamps; clamp so the feed
            // never shows articles from "the future".
            let article = Article(
                guid: item.guid,
                title: item.title.strippingHTML,
                content: item.content,
                publishedAt: min(item.publishedAt ?? .now, .now),
                sourceName: candidate.sourceName,
                link: item.link.isEmpty ? nil : item.link
            )
            context.insert(article)
            knownGuids.insert(item.guid)
            added += 1
            allowance -= 1
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
