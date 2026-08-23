import Foundation
import SwiftData

/// A Pack's suggested Sources, offered to the reader rather than subscribed on
/// their behalf.
///
/// `PackInstaller` deliberately subscribes to nothing: a Source is chosen, and
/// the suggestions are kept on the record for the app to offer. This is the
/// other half of that sentence — what is worth offering, what happens once the
/// reader says yes, and what happens once they say no.
///
/// There is exactly one exception, and it is not here: the very first launch of
/// an empty store subscribes the Active Pack's suggestions outright, because a
/// reader with nothing to read cannot be offered anything worth reading. See
/// `SeedData.acquireSourcesIfNeeded` and ADR-0011.
@MainActor
enum PackSourceOffer {

    /// The suggestions worth putting in front of the reader: the ones they are
    /// not already subscribed to, and that could become a Source at all.
    ///
    /// Matched by URL rather than by name, so a Pack suggesting a Source the
    /// reader already has under a different name does not offer a duplicate.
    ///
    /// Both sides of that match are the URL as `FeedSource` would store it, not
    /// as the Pack wrote it: `URL(string:)` escapes what it must, so comparing
    /// the raw suggestion text against a stored `absoluteString` would miss the
    /// Source every time a suggestion needed escaping — and offer it forever.
    static func pending(_ suggestions: [PackFile.PackSource],
                        context: ModelContext) -> [PackFile.PackSource] {
        pending(suggestions, subscribedTo: subscribedURLs(context: context))
    }

    /// The same question asked of Sources the caller already has in hand.
    ///
    /// `SettingsView` holds them in a `@Query` and redraws its body on every
    /// toggle, so re-fetching them per redraw would pay for a list it was
    /// already handed.
    static func pending(_ suggestions: [PackFile.PackSource],
                        subscribedTo subscribed: Set<String>) -> [PackFile.PackSource] {
        var offered: Set<String> = []
        return suggestions.filter { suggestion in
            guard let stored = url(suggestion)?.absoluteString,
                  !subscribed.contains(stored) else {
                return false
            }
            return offered.insert(stored).inserted
        }
    }

    /// Subscribes to the suggestions the reader accepted, and reports how many
    /// were new. Runs through `pending`, so accepting twice adds nothing the
    /// second time.
    @discardableResult
    static func subscribe(_ accepted: [PackFile.PackSource],
                          context: ModelContext) -> Int {
        let new = pending(accepted, context: context)
        for source in new {
            guard let url = url(source) else { continue }
            context.insert(FeedSource(name: source.name, url: url, category: source.category))
        }
        guard !new.isEmpty else { return 0 }
        do {
            try context.save()
        } catch {
            // Nothing was subscribed to. Say so, rather than report a count the
            // caller will act on — it syncs and analyses what it is told was added.
            context.rollback()
            return 0
        }
        return new.count
    }

    // MARK: - What the sheet opens with, and what Add means

    /// The longest offer that opens with every suggestion ticked.
    ///
    /// Pre-checking is consent by default, and it is honest only while the
    /// reader can see what they are agreeing to. The built-in Packs suggest 14
    /// and 13 — the largest list the app itself vouches for — and a list that
    /// size reads in one screen, where having nothing to read is a worse first
    /// impression than one Source too many. A Pack past this is asking for more
    /// than the app ever asks for, and a list that long is one nobody scrolled
    /// before tapping Add.
    ///
    /// Well under `PackFile.maxSuggestedSources`, deliberately. The cap says
    /// what a Pack may suggest; this says what the app will take on the reader's
    /// behalf, and the second is the smaller question (#20).
    static let preCheckedUpTo = 15

    /// Whether an offer this long arrives ticked. The rule `accept` needs as
    /// well as the sheet, which is why it is a question and not a private
    /// comparison inside `preChecked`.
    static func opensTicked(_ sources: [PackFile.PackSource]) -> Bool {
        sources.count <= preCheckedUpTo
    }

    /// What opens ticked: all of them, or none.
    ///
    /// All-or-nothing rather than the first fifteen. Which suggestions a Pack
    /// listed first is the author's ordering, not a ranking the app can read as
    /// consent, and a half-ticked list invites the reader to trust the ticks
    /// instead of the names.
    static func preChecked(_ sources: [PackFile.PackSource]) -> Set<String> {
        opensTicked(sources) ? Set(sources.map(\.url)) : []
    }

    /// What answering an offer came to.
    struct Accepted {
        /// How many became Sources.
        let subscribed: Int

        /// Ticked, asked, and shown not to be a feed — so not subscribed.
        ///
        /// Deliberately **not** recorded as declined either. The reader said
        /// yes; it is the app that could not use it, and a suggestion nobody
        /// turned down has to stay in the standing offer, or one afternoon on
        /// the host's side buries it close to permanently (ADR-0011).
        let refused: [PackFile.PackSource]
    }

    /// Answering the offer: ask what the reader ticked whether it is really a
    /// feed, subscribe what is, and record what they turned down.
    ///
    /// **An unticked box is an answer only where the box arrived ticked.**
    /// ADR-0011 made a leftover count as a decline because the sheet was always
    /// pre-ticked, so unticking was deliberate. Above `preCheckedUpTo` nothing
    /// arrives ticked, and a reader who ticks three of thirty-one has said
    /// nothing whatever about the other twenty-eight — recording those as
    /// declined would bury them close to permanently, on a list the reader was
    /// never shown as ticked. Unanswered is what the standing offer is for, and
    /// "Not now" is still there for a reader who means to refuse the lot.
    ///
    /// **Only what is shown not to be a feed is turned away.** A host that
    /// refused, timed out or answered nothing has said nothing about its URL —
    /// reddit 429s a feed that is unquestionably a feed (ADR-0003) — so those
    /// are subscribed, and if the trouble persists the Source says so on its own
    /// Settings row (#14). That is a better place to lose an argument with a
    /// host than the moment the reader asked for it.
    ///
    /// Only the ticked ones are asked: probing what the reader left alone would
    /// spend a host's patience on a Source nobody wanted.
    ///
    /// One call rather than three at the call site, so the rules cannot be
    /// half-applied by a caller that remembers to subscribe and forgets what
    /// silence meant, or that subscribes before asking (#58).
    @discardableResult
    static func accept(_ accepted: Set<String>,
                       of offered: [PackFile.PackSource],
                       context: ModelContext) async -> Accepted {
        if opensTicked(offered) {
            recordDeclined(offered.filter { !accepted.contains($0.url) })
        }
        let ticked = offered.filter { accepted.contains($0.url) }
        // Keyed by the suggestion's own URL text, which is what identifies a
        // `PackSource` everywhere else here — the sheet's ticks are that string
        // too. Nothing http can be ticked in the first place: `pending` builds
        // the offer through `url(_:)`, which refuses it, so the refusal below
        // is a second lock on a door already shut rather than the only one.
        let verdicts = await HostPacing.askInTurn(
            ticked.compactMap { suggestion in
                url(suggestion).map { (key: suggestion.url, url: $0) }
            },
            refusingUnencryptedWith: .couldNotTell(.insecure),
            { await FeedDiscovery.probe($0) }
        )
        // A suggestion with no verdict was never asked — the probe was
        // cancelled before its host's group reached it. Not asked is not
        // refused, so it is subscribed like the rest.
        let refused = ticked.filter { verdicts[$0.url] == .notAFeed }
        let usable = ticked.filter { verdicts[$0.url] != .notAFeed }
        return Accepted(subscribed: subscribe(usable, context: context), refused: refused)
    }

    // MARK: - The standing offer

    /// The Active Pack's suggestions the app raises unprompted: the ones the
    /// reader has neither subscribed to nor turned down.
    ///
    /// This is what a Source added to a Pack in a new version of the app
    /// arrives as. Subscribing it at launch instead would be the app choosing a
    /// Source on the reader's behalf — and, because `pending` filters out what
    /// is already subscribed, would suppress the offer for that Source
    /// permanently: the reader could never be asked, because they already had
    /// it (#47).
    static func standing(_ suggestions: [PackFile.PackSource],
                         subscribedTo subscribed: Set<String>) -> [PackFile.PackSource] {
        let refused = declined
        return pending(suggestions, subscribedTo: subscribed).filter { suggestion in
            url(suggestion).map { !refused.contains($0.absoluteString) } ?? false
        }
    }


    private nonisolated static let declinedKey = "declinedSourceSuggestions"

    /// What a store wipe has to clear to leave a fresh install. A decline is
    /// deliberately kept outside the store, so emptying the store cannot reach
    /// it — the same reason `ActivePackIdentity` needs forgetting explicitly.
    nonisolated static let defaultsKeys = [declinedKey]

    /// Suggestions the reader has been shown and left unchecked.
    ///
    /// Kept in `UserDefaults` rather than the store, alongside the other
    /// memories that outlive a record (`ActivePackIdentity`): a decline is
    /// about what the reader has been asked, not about what their map holds,
    /// and it has to survive a Pack being reinstalled over the top.
    ///
    /// Stored as the URL `FeedSource` would store, so it compares against the
    /// same string `pending` does.
    static var declined: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: declinedKey) ?? [])
    }

    /// Records suggestions the reader was shown and did not take, so the
    /// standing offer stops raising them.
    ///
    /// Only `standing` consults this. Installing a Pack by hand is a reader
    /// asking to see its Sources, so `PackLibraryView` offers all of them
    /// again — which is also the only way back from a decline.
    static func recordDeclined(_ suggestions: [PackFile.PackSource]) {
        let urls = suggestions.compactMap { url($0)?.absoluteString }
        guard !urls.isEmpty else { return }
        UserDefaults.standard.set(declined.union(urls).sorted(), forKey: declinedKey)
    }

    /// Drops the record. For tests, which share one `UserDefaults` across stores.
    static func forgetDeclined() {
        UserDefaults.standard.removeObject(forKey: declinedKey)
    }

    // MARK: - Reading the store

    private static func subscribedURLs(context: ModelContext) -> Set<String> {
        Set(((try? context.fetch(FetchDescriptor<FeedSource>())) ?? [])
            .map(\.url.absoluteString))
    }

    /// A suggestion the sync could never fetch is not a place reading can arrive
    /// from, so it is never offered. `URL(string:)` alone would accept "arXiv",
    /// and `FeedSyncService` drops anything that is not https on the floor — so
    /// offering an http feed would subscribe the reader to permanent silence.
    private static func url(_ source: PackFile.PackSource) -> URL? {
        guard let url = URL(string: source.url), url.scheme == "https" else { return nil }
        return url
    }
}
