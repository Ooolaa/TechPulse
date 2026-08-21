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

        // What each Source has to offer, in the order the Source itself put it.
        // The order is deliberately left alone: what a Source is ordered by is
        // part of what the reader subscribed to (`CONTEXT.md`, **Source**), so
        // a vote-ranked Source offers its best first and a chronological one
        // offers its newest first, and neither is the app's decision to make.
        var queues: [SourceQueue] = []
        for (index, source) in sources.enumerated() {
            guard let data = payloads[index] else { continue }
            queues.append(SourceQueue(sourceName: source.name,
                                      items: Array(RSSParser.parse(data).prefix(perFeedLimit))))
            source.lastFetched = .now
        }

        // Round-robin: one item per Source per turn, until the cap is spent or
        // nobody has anything left to give (ADR-0009). The pooled newest-first
        // sort this replaces let one prolific Source take the whole day —
        // three arXiv feeds can each offer `perFeedLimit` same-day items — and
        // in doing so silently made every Source chronological, whatever the
        // reader actually subscribed to. Round-robin decides *how many* items
        // a Source contributes and never *which*.
        var someoneTookATurn = true
        while someoneTookATurn && (allowance > 0 || !bootstrap.isEmpty) {
            someoneTookATurn = false
            for index in queues.indices {
                guard allowance > 0 || !bootstrap.isEmpty else { break }
                let sourceName = queues[index].sourceName
                // Nothing left to pay with: this Source has no bootstrap ration
                // — it never had one, or it has spent it — and the day's
                // allowance is gone. It is not exhausted, though, so its items
                // keep their place rather than being passed over.
                let ration = bootstrap[sourceName]
                guard ration != nil || allowance > 0 else { continue }
                guard let item = queues[index].nextUnread(knownGuids) else { continue }

                // Charge the bootstrap ration first for brand-new sources; the
                // shared daily allowance pays for everything else.
                if let ration {
                    if ration <= 1 { bootstrap.removeValue(forKey: sourceName) }
                    else { bootstrap[sourceName] = ration - 1 }
                } else {
                    allowance -= 1
                }
                // Some publishers post-date RSS timestamps; clamp so the feed
                // never shows articles from "the future".
                let article = Article(
                    guid: item.guid,
                    title: item.title.strippingHTML,
                    content: item.content,
                    publishedAt: min(item.publishedAt ?? .now, .now),
                    sourceName: sourceName,
                    link: item.link.isEmpty ? nil : item.link
                )
                context.insert(article)
                knownGuids.insert(item.guid)
                added += 1
                someoneTookATurn = true
            }
        }
        prune(context: context)
        try? context.save()
        return added
    }

    /// What one Source has left to give this sync, and how far the round has
    /// got through it. The order is the Source's own and is never rearranged:
    /// what a Source is ordered by is part of what the reader subscribed to.
    ///
    /// Not an "offer": `PackSourceOffer` already means suggestions put to the
    /// reader when a Pack installs, which is a different thing entirely.
    private struct SourceQueue {
        let sourceName: String
        let items: [ParsedFeedItem]
        private var taken = 0

        init(sourceName: String, items: [ParsedFeedItem]) {
            self.sourceName = sourceName
            self.items = items
        }

        /// The next item the reader does not already have, consuming everything
        /// passed over on the way. An article already cached is not something
        /// offered, so skipping it must not cost this Source its turn — which
        /// is why the skipping happens here rather than in the round.
        mutating func nextUnread(_ knownGuids: Set<String>) -> ParsedFeedItem? {
            while taken < items.count {
                let candidate = items[taken]
                taken += 1
                if !candidate.guid.isEmpty, !knownGuids.contains(candidate.guid) {
                    return candidate
                }
            }
            return nil
        }
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
