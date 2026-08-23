import Foundation

/// The one pause between two requests to the same host.
///
/// A Source is a subscription and the app is indifferent to what is on the
/// other end — but the other end is not indifferent to us, and it counts
/// requests by host rather than by Source. Reddit serves the vote-ranked feeds
/// the 🔥 lane wants (ADR-0003) and throttles hard: `r/MachineLearning/top/
/// .rss?t=week` returned HTTP 429 and then zero bytes on plain sequential
/// fetches two minutes apart while #43 was being written, with the descriptive
/// User-Agent set. Two Sources on one host fired at once is how one of them
/// comes back empty and the reader is told nothing.
///
/// So this is not a number that makes throttling go away — nothing a client
/// does can promise that, and the two-minute finding says so. It is the app's
/// whole answer to *how fast will you ask one host for things*, named once so
/// that a second fetcher cannot answer it differently, which is the reason
/// `ResponseLimit` is one value and not three.
enum HostPacing {
    /// Two seconds: twice the request-a-second pace hosts commonly ask for, and
    /// cheap — a sync runs unwatched, and only Sources that share a host wait
    /// at all.
    nonisolated static let betweenRequests: Duration = .seconds(2)

    /// Asks for each of `requests`, one host at a time.
    ///
    /// Grouped by URL host: the groups run concurrently, so a batch spanning
    /// ten hosts is ~max rather than ~sum of their latencies, and the requests
    /// inside one group go one at a time with `betweenRequests` between them.
    /// Host is the unit because host is what the far end counts by — two
    /// subreddits are two requests and one server (#44).
    ///
    /// Hosts are case-insensitive, so `Reddit.com` and `reddit.com` are one
    /// group and not two. A URL with no host is filed under one empty key with
    /// the others of its kind, which is the conservative reading: a host that
    /// cannot be named cannot be shown to be a different one.
    ///
    /// **Anything that is not https is answered with `refusal` and never
    /// sent** — `Egress` leaves over TLS only. The rule lives here rather than
    /// in each caller because a caller that forgot it would send the request,
    /// and a rule enforced by everyone remembering it is the shape #36 folded
    /// away. Refusing it here also keeps the pause a property of *requests*
    /// rather than of list positions: a URL nothing was sent for does not make
    /// the one behind it wait for an answer no host was ever asked for.
    ///
    /// The pause *is* paid after a request that failed, because a failure is
    /// most likely the throttling it exists for, and that is the worst moment
    /// to ask the same host again immediately. And no group ends on a wait: the
    /// pause is paid before a request, never after the last one.
    ///
    /// Keyed rather than positional, so a caller with two requests to the same
    /// URL still gets two answers. Cancellation ends a host's group where it
    /// stands rather than releasing the rest of it back to back, so the answers
    /// may be fewer than the requests — a key that is absent was never asked,
    /// which is not the same as one that failed and not the same as one that
    /// was refused.
    nonisolated static func askInTurn<Key: Hashable & Sendable, Answer: Sendable>(
        _ requests: [(key: Key, url: URL)],
        refusingUnencryptedWith refusal: Answer,
        _ ask: @Sendable @escaping (URL) async -> Answer
    ) async -> [Key: Answer] {
        var answers = [Key: Answer]()
        var sendable = [(key: Key, url: URL)]()
        for request in requests {
            if request.url.scheme == "https" { sendable.append(request) }
            else { answers[request.key] = refusal }
        }
        let byHost = Dictionary(grouping: sendable) { $0.url.host()?.lowercased() ?? "" }
        let asked = await withTaskGroup(of: [(key: Key, answer: Answer)].self) { group in
            for hostGroup in byHost.values {
                group.addTask { await askOneHost(hostGroup, ask) }
            }
            var fetched = [(key: Key, answer: Answer)]()
            for await entries in group { fetched += entries }
            return fetched
        }
        for entry in asked { answers[entry.key] = entry.answer }
        return answers
    }

    private nonisolated static func askOneHost<Key: Hashable & Sendable, Answer: Sendable>(
        _ requests: [(key: Key, url: URL)],
        _ ask: @Sendable (URL) async -> Answer
    ) async -> [(key: Key, answer: Answer)] {
        var asked = [(key: Key, answer: Answer)]()
        for request in requests {
            if !asked.isEmpty {
                do { try await Task.sleep(for: betweenRequests) }
                catch { break }
            }
            asked.append((request.key, await ask(request.url)))
        }
        return asked
    }
}
