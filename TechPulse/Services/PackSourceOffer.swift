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
