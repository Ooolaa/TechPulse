import Foundation

/// Turns a raw text selection into something worth explaining — or nothing.
///
/// Pure and `nonisolated` so it can be unit tested without a container, and so
/// the guard runs before any model call. That ordering matters twice over: it
/// stops a stray paragraph-drag from spending a generation, and it is the
/// injection guard for `IntelligenceService.define` — the selection comes from
/// attacker-controlled RSS body text, so its shape is checked before it reaches
/// a prompt.
enum WordSelection {
    /// The island looked-up words land on. Deliberately *not* in
    /// `KnowledgePack.clusterOrder`, so vocabulary can never inflate the
    /// curated pack's cluster progress ("2 of 13 lit").
    static let cluster = "Vocabulary"

    static let maxWords = 6
    static let maxCharacters = 60

    /// Decorative characters trimmed from a selection's edges — quotes,
    /// brackets, and sentence punctuation a drag naturally picks up.
    /// Deliberately narrower than `CharacterSet.punctuationCharacters.union(.symbols)`:
    /// that broader set stripped the trailing `+`/`#` off real terms like
    /// "C++" and "C#", collapsing them below the minimum length.
    private static let wrappingCharacters = CharacterSet(charactersIn: "\"'“”‘’()[]{}<>,;:.!?—–-")

    /// nil when the selection isn't a term: empty, a whole paragraph, or long
    /// enough that the user was clearly selecting prose rather than a phrase.
    static func normalize(_ raw: String) -> String? {
        // A newline means the selection spans blocks — prose, not a term.
        guard !raw.contains(where: \.isNewline) else { return nil }

        // Strip surrounding punctuation and quotes: `("transformer"),` → transformer
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: wrappingCharacters)
            .trimmingCharacters(in: .whitespaces)

        guard trimmed.count >= 2, trimmed.count <= maxCharacters else { return nil }

        // Collapse internal runs of whitespace so word counting is honest.
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= maxWords else { return nil }

        let collapsed = words.joined(separator: " ")
        // Needs at least one letter — rejects "42", "—", "()".
        guard collapsed.contains(where: \.isLetter) else { return nil }
        return collapsed
    }

    /// A window of surrounding prose, for disambiguation ("transformer" in ML
    /// vs. electrical). Trimmed to whitespace boundaries so we don't hand the
    /// model half a word.
    static func context(in text: String, around range: Range<String.Index>,
                        radius: Int = 220) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -radius,
                               limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: radius,
                              limitedBy: text.endIndex) ?? text.endIndex
        var window = String(text[lower..<upper])

        // Drop the partial words at each edge, unless that would empty it.
        if lower != text.startIndex, let firstSpace = window.firstIndex(where: \.isWhitespace) {
            window = String(window[window.index(after: firstSpace)...])
        }
        if upper != text.endIndex, let lastSpace = window.lastIndex(where: \.isWhitespace) {
            window = String(window[..<lastSpace])
        }
        return window.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
