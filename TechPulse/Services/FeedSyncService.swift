import Foundation
import SwiftData

/// Fetches all enabled feed sources and caches new articles in SwiftData.
///
/// Offline-first: a failure costs the Source that suffered it and nothing else,
/// and whatever is cached stays readable. It is no longer *silent*, though —
/// every attempt ends by writing what it was on the Source it was for, so a
/// Source that is being throttled, refused, or was never a valid thing to ask
/// can be told apart from one having a quiet week (#14, `SourceHealth`).
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

        // Only what may be sent is handed to the pacing. An http Source is
        // refused here rather than sent — `Egress` leaves over TLS only — and
        // refusing it *before* the queue is also what keeps the pause a
        // property of requests: a Source the guard turns away does not make the
        // Source behind it wait for a request no host ever received. It is
        // still an outcome, and the one failure nothing on the wire can
        // explain, which is why it is recorded at the guard.
        var outcomes = [Int: FetchOutcome]()
        var askable = [(key: Int, url: URL)]()
        for (index, source) in sources.enumerated() {
            if source.url.scheme == "https" { askable.append((index, source.url)) }
            else { outcomes[index] = .failed(.insecure) }
        }
        // One host at a time, hosts concurrently (#44). A Source missing from
        // the answers was never asked — the sync was cancelled before its
        // host's group reached it — which is not the same as one that failed.
        for (index, outcome) in await HostPacing.askInTurn(askable, { await fetch($0) }) {
            outcomes[index] = outcome
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
            // The two records are written together and never both: what a
            // Source last *did* is one fact, so a success clears the failure it
            // recovered from and a failure leaves the date it last worked alone.
            switch outcomes[index] {
            case .arrived(let data):
                let items = RSSParser.parse(data)
                queues.append(SourceQueue(sourceName: source.name,
                                          items: Array(items.prefix(perFeedLimit))))
                source.lastFetched = .now
                source.lastFailure = nil
                // What this Source is publishing, taken from the whole answer
                // rather than the prefix the round-robin will draw on: how much
                // of a feed the app takes is the cap's business, and how recently
                // the Source published is not. Clamped like the Article below —
                // some publishers post-date — and left alone when the answer
                // carried no date at all.
                if let newest = items.compactMap(\.publishedAt).map({ min($0, .now) }).max() {
                    source.newestOffered = newest
                }
            case .failed(let failure):
                source.lastFailure = failure
            case nil:
                // Never attempted — the sync was cancelled before this host's
                // group reached it. Nothing was learned about this Source, so
                // nothing about it is rewritten: an expiring background refresh
                // must not leave the reader's Settings full of failures.
                continue
            }
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

    /// What one request came back as. Not `Data?`: the failures are the point
    /// of #14, and an optional could only say that there had been one.
    enum FetchOutcome {
        case arrived(Data)
        case failed(SourceFailure)
    }

    /// How long a sync waits on one host. Generous, because a sync runs
    /// unwatched — `FeedDiscovery` passes a shorter one, because a reader is
    /// watching that.
    nonisolated static let timeout: TimeInterval = 30

    /// One request for a feed, to a URL the caller has decided is askable —
    /// https, since `Egress` leaves over TLS only, which `syncAll` checks
    /// before anything reaches here. A Source that times out, errors, or
    /// answers non-2xx, empty, or over the response limit contributes nothing —
    /// and costs the Sources around it nothing either. It does now say which of
    /// those happened, which is all a reader needs to tell a throttled Source
    /// from a quiet one.
    ///
    /// Shared with `FeedDiscovery`, which asks the same question of a URL
    /// nobody has subscribed to yet (#58). One agent, one response limit, one
    /// reading of what a refusal was — the property #28 folded three copies of
    /// these questions into one to get.
    nonisolated static func fetch(_ url: URL,
                                  timeout: TimeInterval = timeout) async -> FetchOutcome {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            // No answer to judge. As likely to be the reader's connection as
            // the Source, and `SourceFailure.unreachable` is worded for that.
            return .failed(.unreachable)
        }
        switch ResponseLimit.verdict(data: data, response: response) {
        // An empty body passes every question `ResponseLimit` asks — it is a
        // 2xx, and zero is under the cap — and answers none of the ones a
        // reader has. It is judged here rather than there because "zero bytes
        // is not a feed" is a fact about feeds, and the other two fetchers
        // behind that cap are not fetching one.
        case .acceptable: return data.isEmpty ? .failed(.empty) : .arrived(data)
        case .refused(let status): return .failed(.refusal(status: status))
        case .oversized: return .failed(.oversized)
        }
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
