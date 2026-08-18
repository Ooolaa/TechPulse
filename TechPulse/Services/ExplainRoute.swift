import Foundation

/// Whether a word the reader selected is a word already on their map.
///
/// Pure and `nonisolated`, so the line between "opens offline" and "reaches a
/// model" is a unit test rather than a claim in a document — the same reason
/// `ExplainPrompt` is pure (#29). ADR-0006 rests an accepted quality cost on
/// that line falling where it says it does, so where it falls is load-bearing.
///
/// Folds spelling, not meaning (ADR-0007): case, separators and English
/// plurals, so "LoRAs" finds the Concept named "LoRA" and
/// "low-rank-adaptation" finds the one named "Low-Rank Adaptation", while a
/// synonym of either still
/// costs a generation. That bound is deliberate — an embedding match here would
/// also catch synonyms, and would buy them with a false positive that hands the
/// reader a definition of a Concept they did not tap, offline and with nothing
/// to signal it happened.
enum ConceptMatch {

    /// Characters that are the same thing as a space in a Concept name.
    /// Sentence punctuation is *not* here: `WordSelection` already trims that
    /// off a selection, and names like "C++" and "C#" have to survive intact.
    private static let separators: Set<Character> = ["-", "\u{2010}", "\u{2011}",
                                                     "\u{2013}", "\u{2014}", "_"]

    /// The key two names are compared under. Same key, same word.
    static func fold(_ name: String) -> String {
        let spaced = String(name.lowercased().map { separators.contains($0) ? " " : $0 })
        let words = spaced.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let last = words.last else { return "" }
        return (words.dropLast() + [singular(last)]).joined(separator: " ")
    }

    /// The item a selection lands on, preferring the name spelled exactly as
    /// selected. The fold only ever widens what matches: where a Concept
    /// already answered a selection, it still answers it.
    static func first<Item>(_ term: String, among items: [Item],
                            name: KeyPath<Item, String>) -> Item? {
        if let exact = items.first(where: {
            $0[keyPath: name].localizedCaseInsensitiveCompare(term) == .orderedSame
        }) { return exact }

        let key = fold(term)
        guard !key.isEmpty else { return nil }
        return items.first { fold($0[keyPath: name]) == key }
    }

    /// English plurals, folded far enough to catch what readers actually select
    /// — "LoRAs", "Agents", "Policies" — and no further. Not a stemmer: it runs
    /// on both sides of the comparison, so folding too hard costs a wrong match
    /// only where two Concept names fold together, and folding too gently costs
    /// a model call the reader was going to pay anyway.
    private static func singular(_ word: String) -> String {
        guard word.count > 2, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        if word.count > 3, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count > 3, word.hasSuffix("es") {
            let stem = String(word.dropLast(2))
            // Only stems that cannot take a bare "s": "losses" → "loss",
            // "batches" → "batch". A single "s" is not enough — it would take
            // "databases" to "databas" and miss the Concept "Vector Database".
            if ["ss", "x", "z", "sh", "ch"].contains(where: stem.hasSuffix) { return stem }
        }
        return String(word.dropLast())
    }
}

/// What selecting a word does next.
///
/// The decision `ArticleView.explain` makes, lifted out of the view so it is
/// something a test can hold. #29's lesson (`1f8334e`) was that pure builders
/// with an untested call site still ship the bug; here the call site *is* the
/// claim — which words are answered from the map and which ones become `Egress`.
enum ExplainRoute {
    /// Already on the map. Opens instantly and offline, on every device,
    /// whether or not any model is reachable. Nothing is sent.
    case existing(Concept)
    /// Not on the map, and this device can ask. On the opt-in path this is the
    /// case that puts the selected word on the wire (ADR-0006).
    case generate
    /// Not on the map, and neither tier is available — ADR-0006's third tier,
    /// which is the reader who has not opted in rather than a broken install.
    case unavailable

    /// Map first, model second. `canDeepen` is asked *after* the map, so a word
    /// the reader already has is explained on hardware that can explain nothing.
    static func decide(term: String, known: [Concept], canDeepen: Bool) -> ExplainRoute {
        if let hit = ConceptMatch.first(term, among: known, name: \.name) {
            return .existing(hit)
        }
        return canDeepen ? .generate : .unavailable
    }
}
