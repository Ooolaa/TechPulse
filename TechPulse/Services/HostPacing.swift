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
}
