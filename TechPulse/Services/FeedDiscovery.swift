import Foundation

/// Whether a URL is somewhere reading can actually arrive from.
///
/// #20 asked what a Pack may *suggest* and answered it statically:
/// `PackSourceOffer.url` refuses anything `URL(string:)` will not take and
/// anything that is not https, because `FeedSyncService` would drop it on the
/// floor. That rejects what is syntactically unfetchable and asks the host
/// nothing, so a well-formed https URL serving a 404 — or a perfectly good HTML
/// page and no feed at all — was offered and subscribed exactly like a working
/// one (#58).
///
/// Since #14 the reader at least finds out afterwards: the Settings row says
/// `Refused`. But afterwards is a Source in their list that never belonged
/// there, and the case that makes this worth asking *before* is the one #27 is
/// building — a **generated** Pack's suggested Sources are model output, and
/// model output is never trusted.
///
/// Ported from CareerPulse (`Services/PackDraft.swift` at `af8ab0c`), which is
/// where its shape comes from and not its parts: that version carried its own
/// User-Agent, its own 5 MB check and its own acceptance of `http`, all three
/// of which this app has since answered once and centrally.
enum FeedDiscovery {
    /// How long a probe waits on one host.
    ///
    /// Shorter than a sync's, because a reader is watching this one. A sync
    /// runs unwatched and can afford to wait out a slow host; a reader who
    /// tapped Add and is holding a sheet open cannot.
    nonisolated static let timeout: TimeInterval = 10

    /// What asking one URL came to.
    ///
    /// Three answers and not two, and the third is the one that matters: a
    /// refusal is not a verdict about the URL. Reddit answers 429 to a
    /// perfectly good feed (ADR-0003), and refusing to subscribe on that basis
    /// would cost the reader a Source because a host was busy for a second.
    /// Only a host that answered, with something that is not a feed, has told
    /// us anything about the URL itself.
    enum Verdict: Equatable, Sendable {
        /// It answered, and what came back is a feed.
        case isAFeed

        /// It answered, and what came back is not one.
        case notAFeed

        /// Nothing to judge it on. Carries why, in the same vocabulary a
        /// subscribed Source's health speaks (#14).
        case couldNotTell(SourceFailure)
    }

    /// Asks one URL whether it is a feed.
    ///
    /// Being a feed is a property of the *document*, not of how much is in it:
    /// a feed that has published nothing is still a feed, and refusing it would
    /// turn away exactly the new Source a Pack is most likely to be recommending
    /// early. `ParsedFeed.isFeedDocument` is what draws that line, and it is
    /// drawn at the root element — a page is free to contain the word "feed",
    /// and a feed is not free to bury its own root.
    ///
    /// The caller has already refused anything that is not https, the same way
    /// `syncAll` has before its own fetch. Nothing here re-asks that question,
    /// so there is one place it is answered.
    nonisolated static func probe(_ url: URL) async -> Verdict {
        switch await FeedSyncService.fetch(url, timeout: timeout) {
        case .failed(let failure):
            return .couldNotTell(failure)
        case .arrived(let data):
            return RSSParser.read(data).isFeedDocument ? .isAFeed : .notAFeed
        }
    }
}
