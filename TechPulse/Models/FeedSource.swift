import SwiftData
import Foundation

@Model
final class FeedSource {
    var name: String
    var url: URL
    var category: String        // graph cluster: "LLMs", "Agents", "Vision", ...
    var isEnabled: Bool

    /// When this Source last answered with something worth parsing. Set only on
    /// a fetch that arrived and was accepted, so "last fetched" means what it
    /// says: a Source that has been 429ing for a week still reports the day it
    /// last worked, which is the number that makes the failure legible (#14).
    var lastFetched: Date?

    /// Why the most recent attempt failed, or `nil` if it did not.
    ///
    /// The two records answer different questions and are deliberately not one:
    /// `lastFetched` is when this Source last *worked*, and is left alone by a
    /// failure; this is what is wrong with it *now*, and is cleared the moment
    /// it answers again. Both `nil` is the third state — never tried — which a
    /// single field could not tell apart from working.
    var lastFailure: SourceFailure?

    /// The publication date of the newest item this Source last offered.
    ///
    /// Written from the feed rather than read back from the cache, because the
    /// cache is not a record of what a Source publishes: `prune` deletes read
    /// articles over 60 days old, and *every* article a Source that died in
    /// 2020 has to offer is over 60 days old. Derived from Articles, "nothing
    /// new for years" evaporated the moment the reader finished reading the
    /// last of them — the Source went back to looking fine precisely because
    /// it had nothing left (#14).
    ///
    /// Left alone by a fetch that parsed to nothing, which says nothing about
    /// when this Source last published — only that this answer carried no date.
    var newestOffered: Date?

    init(name: String, url: URL, category: String, isEnabled: Bool = true) {
        self.name = name
        self.url = url
        self.category = category
        self.isEnabled = isEnabled
        self.lastFetched = nil
        self.lastFailure = nil
        self.newestOffered = nil
    }
}
