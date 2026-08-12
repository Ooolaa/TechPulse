import Foundation
import SwiftData

/// A Pack's suggested Sources, offered to the reader when it installs.
///
/// `PackInstaller` deliberately subscribes to nothing: a Source is chosen, and
/// the suggestions are kept on the record for the app to offer. This is the
/// other half of that sentence — what is worth offering, and what happens once
/// the reader says yes.
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
        let subscribed = Set(((try? context.fetch(FetchDescriptor<FeedSource>())) ?? [])
            .map(\.url.absoluteString))
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

    /// A suggestion the sync could never fetch is not a place reading can arrive
    /// from, so it is never offered. `URL(string:)` alone would accept "arXiv",
    /// and `FeedSyncService` drops anything that is not https on the floor — so
    /// offering an http feed would subscribe the reader to permanent silence.
    private static func url(_ source: PackFile.PackSource) -> URL? {
        guard let url = URL(string: source.url), url.scheme == "https" else { return nil }
        return url
    }
}
