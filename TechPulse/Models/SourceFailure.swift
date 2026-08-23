import Foundation

/// Why the last attempt to read a Source did not produce anything to parse.
///
/// Stored on the Source rather than derived, because the attempt is over by the
/// time anyone asks: a 429 leaves nothing behind but the fact that it happened.
/// `syncAll` used to swallow exactly this with `try?`, so a Source that was
/// being throttled, refused, or was never a valid thing to ask contributed
/// nothing and said nothing — an empty Cluster was all the reader ever saw
/// (#14, ADR-0003).
///
/// The cases are what the app can honestly tell apart from one response, and no
/// finer. A refusal keeps only *that* it was refused and whether it was the
/// throttling this product has a live finding about; the exact status code is
/// not carried, because the row this ends up on is a reader's Settings screen
/// and "403 rather than 404" is not a distinction they can act on.
enum SourceFailure: String, Codable, Sendable {
    /// HTTP 429. The one status the app names, because it is the one ADR-0003
    /// watched reddit return — and the one a reader can act on, by removing a
    /// Source or accepting that this host answers when it feels like it.
    case throttled

    /// Any other non-2xx answer: gone, forbidden, moved without a redirect.
    case refused

    /// No answer at all — a timeout, a name that does not resolve, no network.
    /// The one failure that is as likely to be about the reader's connection as
    /// about the Source, which is why it is not worded as the Source's fault.
    case unreachable

    /// An answer over `ResponseLimit.maxBytes`, discarded rather than parsed.
    case oversized

    /// A 2xx carrying nothing at all. The other half of ADR-0003's live
    /// finding — reddit answered `r/MachineLearning/top/.rss?t=week` with
    /// **429 and then zero bytes** — and the half that would otherwise slip
    /// through as a success: a feed with no entries is a legitimate answer,
    /// but zero bytes is not a feed, and recording it as a fetch would date
    /// `lastFetched` for a Source that told us nothing.
    case empty

    /// Not `https`, so it was never sent. Egress leaves over TLS only, which
    /// makes this the one failure that costs no request and will not clear
    /// itself: the URL is what is wrong with it.
    case insecure

    /// The refusal a status code amounts to. Named here rather than at the
    /// fetch, so the one status the product cares about is a property of the
    /// record and not of whichever fetcher happened to write it.
    static func refusal(status: Int) -> SourceFailure {
        status == 429 ? .throttled : .refused
    }
}
