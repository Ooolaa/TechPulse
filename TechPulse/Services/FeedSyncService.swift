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
    static let dailyIntakeLimit = 30

    /// Articles a Source with nothing cached may take OUTSIDE the daily cap,
    /// so that a Source added on a day whose intake is already spent shows
    /// something rather than an empty tag until tomorrow.
    static let newSourceAllowance = 5

    /// Descriptive User-Agent: some hosts (notably reddit, which serves the
    /// Kaggle community feed) throttle or 403 default CFNetwork agents.
    /// Shared with TopicSearchService.
    nonisolated static let userAgent = "TechPulse/1.0 (iOS offline RSS reader)"

    @discardableResult
    static func syncAll(context: ModelContext) async -> Int {
        let enabled = FetchDescriptor<FeedSource>(predicate: #Predicate { $0.isEnabled })
        guard let sources = try? context.fetch(enabled), !sources.isEmpty else { return 0 }

        // Fetch by host: the groups run concurrently, so a cold sync is still
        // ~max rather than ~sum of feed latencies for the Sources that do not
        // share a host, and the Sources inside one group go one at a time.
        // Host is the unit because host is what the far end counts by — two
        // subreddits are two Sources and one server (#44).
        //
        // Hosts are case-insensitive, so `Reddit.com` and `reddit.com` are one
        // group and not two. A URL with no host is filed under one empty key
        // with the others of its kind, which is the conservative reading: a
        // host that cannot be named cannot be shown to be a different one.
        let requests = sources.enumerated().map { (index: $0.offset, url: $0.element.url) }
        let byHost = Dictionary(grouping: requests) { $0.url.host()?.lowercased() ?? "" }
        let payloads = await withTaskGroup(of: [(index: Int, data: Data)].self) { group in
            for hostGroup in byHost.values {
                group.addTask { await fetchInTurn(hostGroup) }
            }
            var results = [Int: Data]()
            for await fetched in group {
                for entry in fetched { results[entry.index] = entry.data }
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

        // Rationed by name, because an Article names its Source: "has this
        // Source cached anything?" is a name-level question, and two Sources
        // under one name — names are not unique, subscription is deduplicated
        // by URL everywhere it happens — cannot be told apart by it. Taking the
        // names as a set is what says they share one ration (#23).
        let cachedSourceNames = Set(existing.map(\.sourceName))
        let newSourceNames = Set(sources.map(\.name)).subtracting(cachedSourceNames)
        var bootstrap = Dictionary(
            uniqueKeysWithValues: newSourceNames.map { ($0, newSourceAllowance) }
        )

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
            guard allowance > 0 || !bootstrap.isEmpty else { break }
            let item = candidate.item
            guard !item.guid.isEmpty, !knownGuids.contains(item.guid) else { continue }
            // Charge the bootstrap ration first for brand-new sources; the
            // shared daily allowance pays for everything else.
            if let ration = bootstrap[candidate.sourceName] {
                if ration <= 1 { bootstrap.removeValue(forKey: candidate.sourceName) }
                else { bootstrap[candidate.sourceName] = ration - 1 }
            } else if allowance > 0 {
                allowance -= 1
            } else {
                continue
            }
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
        }
        prune(context: context)
        try? context.save()
        return added
    }

    /// One host's Sources, one request at a time.
    ///
    /// The pause separates requests, not list positions: it is paid only after
    /// this host was actually asked something, so the first Source waits for
    /// nothing, no sync ends on a wait, and a Source that is never asked — one
    /// the scheme guard turns away — does not make the Source behind it wait
    /// for a request the host never received.
    ///
    /// It *is* paid after a request that failed. A failure is most likely the
    /// throttling the pause exists for, and that is the worst moment to ask the
    /// same host again immediately.
    private nonisolated static func fetchInTurn(
        _ sources: [(index: Int, url: URL)]
    ) async -> [(index: Int, data: Data)] {
        var fetched = [(index: Int, data: Data)]()
        var asked = false
        for source in sources {
            // Not a request, so not something to pace against: an http Source
            // is refused here rather than sent (`Egress` leaves over TLS only).
            guard source.url.scheme == "https" else { continue }
            if asked {
                // Cancellation ends the group here rather than releasing the
                // rest of it back to back, which is the thing being avoided.
                do { try await Task.sleep(for: HostPacing.betweenRequests) }
                catch { break }
            }
            asked = true
            if let data = await fetch(source.url) { fetched.append((source.index, data)) }
        }
        return fetched
    }

    /// One request, to a Source `fetchInTurn` has decided is askable. A Source
    /// that times out, errors, or answers non-2xx or over the response limit
    /// contributes nothing — and costs the Sources around it nothing either.
    private nonisolated static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              ResponseLimit.accepts(data: data, response: response)
        else { return nil }
        return data
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
