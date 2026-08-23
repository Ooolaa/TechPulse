import Foundation
import SwiftData

/// What one Source is doing, as opposed to what it is.
///
/// A Source that is being throttled, that has been answering 404 since the
/// publisher moved, or that has quietly stopped posting all produce the same
/// thing today: an empty Cluster. Kaggle's Medium blog stopped publishing in
/// 2020 and nothing in the app ever said so (#14, ROADMAP item 12).
///
/// Derived on demand and never stored, so it cannot disagree with the cache it
/// describes: the two halves it reads — what the last fetch did, and what is
/// cached under this Source's name — are already in the store, and a third copy
/// of them would only be a thing to keep in step.
struct SourceHealth: Equatable, Sendable {
    /// How long a Source may go without publishing before the app is willing to
    /// say out loud that it looks dead. Six months, per ROADMAP item 12: long
    /// enough that a quarterly newsletter is not accused of dying, short enough
    /// that a blog which stopped in 2020 does not sit there looking fine.
    ///
    /// "Likely" is the whole of the claim. Nothing observable separates a
    /// publisher that stopped from one that is between posts, so the app says
    /// what it saw — nothing since a date — and leaves the verdict to the reader.
    static let likelyDeadAfter: TimeInterval = 180 * 86_400

    /// The one thing a Source can be said to be right now, in the order that
    /// decides it: a Source that is failing is failing whatever its cache looks
    /// like, and one that has never been asked is not evidence of anything.
    enum State: Equatable, Sendable {
        /// Neither a success nor a failure on record. A Source subscribed to a
        /// minute ago, not a Source with a problem.
        case neverFetched

        /// The most recent attempt did not come back with anything to parse.
        case failing(SourceFailure)

        /// Answering, but nothing it has offered is newer than
        /// `likelyDeadAfter`.
        case likelyDead

        /// Answering, with something recent enough to believe in.
        case answering
    }

    /// When this Source last answered, whatever it is doing now.
    let lastFetched: Date?

    /// Articles cached under this Source's name — what the reader can actually
    /// read from it offline, which is the number an empty Cluster is about.
    let cached: Int

    /// When this Source last published something, as of its last successful
    /// fetch — not the newest of `cached`. The cache is pruned and the reader
    /// reads it away; what a Source publishes is a fact about the Source, and
    /// is what "likely dead" is a judgement about.
    let newestOffered: Date?

    let state: State

    /// The health of each of `sources`, keyed by the Source it belongs to.
    ///
    /// Batched because a Settings screen wants all of them: the Articles are
    /// fetched and tallied once here rather than once per row.
    ///
    /// Articles are joined to a Source **by name**, which is the only join an
    /// `Article` carries — and names are not unique, since subscription is
    /// deduplicated by URL and not by name. So two Sources sharing a name are
    /// reported the same cached *count*, the same trade the bootstrap ration
    /// already makes for the same reason (#23). Everything else here is read
    /// off the Source itself and stays exact: which one is failing, when each
    /// last answered, and when each last published.
    ///
    /// A Source the reader has switched off keeps whatever it was last seen
    /// doing. Nothing asks it while it is off, so there is nothing newer to
    /// say, and the row's own toggle is what marks the reading as history.
    @MainActor
    static func read(_ sources: [FeedSource], in context: ModelContext,
                     asOf now: Date = .now) -> [PersistentIdentifier: SourceHealth] {
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        var cached: [String: Int] = [:]
        for article in articles {
            cached[article.sourceName, default: 0] += 1
        }
        // Tolerant of a repeated key rather than trapping on one. A
        // `PersistentIdentifier` is unique per row, so there should be none —
        // but the last duplicate-intolerant initializer in this codebase was
        // also keyed on something that "could not" repeat, and it crashed the
        // first sync of a store with two Sources under one name (#23).
        return Dictionary(
            sources.map { source in
                (source.persistentModelID,
                 SourceHealth(source, cached: cached[source.name] ?? 0, asOf: now))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private init(_ source: FeedSource, cached: Int, asOf now: Date) {
        self.lastFetched = source.lastFetched
        self.cached = cached
        self.newestOffered = source.newestOffered
        self.state = Self.state(of: source, asOf: now)
    }

    private static func state(of source: FeedSource, asOf now: Date) -> State {
        if let failure = source.lastFailure { return .failing(failure) }
        guard source.lastFetched != nil else { return .neverFetched }
        // Only a Source that has been heard from can be shown to have stopped:
        // until one answers with something dated, there is no date to be old.
        if let newest = source.newestOffered, now.timeIntervalSince(newest) > likelyDeadAfter {
            return .likelyDead
        }
        return .answering
    }
}
