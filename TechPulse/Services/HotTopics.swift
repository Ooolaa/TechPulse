import Foundation
import NaturalLanguage

/// A term the reader's own Sources have started talking about.
struct HotTerm: Equatable, Sendable {
    let text: String
    /// How many recent Articles mention it — the observation behind `rise`.
    let articles: Int
    /// How much more of the recent window it occupies than it did before.
    let rise: Double

    /// Whether the two terms are the same story: one's words run inside the
    /// other's, in order. Compared as *words*, not characters — "world model"
    /// says "world", where "modelling" does not say "model", and dropping that
    /// because the letters line up would lose a topic to a coincidence of
    /// spelling. Symmetric, so whichever scored better takes the slot.
    func shares(words other: HotTerm) -> Bool {
        Self.runs(other.text.split(separator: " "), inside: text.split(separator: " "))
            || Self.runs(text.split(separator: " "), inside: other.text.split(separator: " "))
    }

    private static func runs(_ needle: [Substring], inside haystack: [Substring]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { start in
            Array(haystack[start..<(start + needle.count)]) == needle
        }
    }
}

/// The 🔥 lane's vocabulary, observed rather than typed.
///
/// ADR-0003 rejected both alternatives on the record: an aliases field on
/// `PackFile` ages the moment a Pack is generated, and a platform API would
/// break what a Source is. What is left is the reader's own reading — so a term
/// is hot when *their* Sources have started saying it, which needs no list, no
/// network, and nothing that knows what field they are in.
///
/// ## Why not the most frequent terms
///
/// The same failure `CoreadScoring` records for raw co-occurrence: counting
/// rewards whatever is always there. In a feed about AI engineering the top
/// terms by frequency are "model", "AI" and "data" every day — true, useless,
/// and unchanged by anything happening in the field.
///
/// ## Why not a ratio either
///
/// The obvious repair — recent share over baseline share — fails the other way,
/// and measurably: a term appearing three times where it never appeared scores
/// near-infinitely, while a term going from a fifth of the feed to two thirds
/// scores about three. So a single new Source saying hello outranks the story
/// of the week, and `newSourceAllowance` guarantees a new Source every time one
/// is added. Novelty from zero is not the same as rising.
///
/// ## What is scored
///
/// The difference in log-odds between the two windows, divided by its own
/// standard error — the standard way to ask which terms distinguish one corpus
/// from another. The division is the whole point: a term seen three times
/// carries most of its score in its own uncertainty and lands near zero, while
/// a term seen fifty times has to move a long way to score at all. Magnitude
/// and shift both count, and neither alone is enough.
///
/// Two floors sit under it, because a z-score is happy to rank noise:
///
/// - **Mentions.** Fewer than a handful of Articles is an anecdote.
/// - **Share of the window.** Hot means a noticeable part of what the reader is
///   actually reading, not a curiosity in the corner of it.
///
@MainActor
enum HotTopics {

    /// The Cluster the rolling "what the world is doing right now" Concepts sit in.
    static let cluster = "Hot Topics"

    /// The window the lane describes.
    static let recentDays = 3
    /// What "normal" is measured over. Long enough that a busy week does not
    /// become the baseline it is being compared against.
    static let baselineDays = 17
    /// Recent Articles a term must appear in before it is a topic at all.
    static let mentionFloor = 3
    /// And how much of the recent window it has to occupy. A term in one
    /// Article of thirty is not what the reader is reading about.
    static let minimumShare = 0.05
    /// How far the shift has to clear its own uncertainty. Two standard errors
    /// is the usual reading of "more than noise".
    static let minimumScore = 2.0
    /// How many terms the lane holds. It is a lane, not a list.
    static let laneSize = 8

    /// The terms rising across these Articles, strongest first.
    ///
    /// Pure: it reads the Articles it is handed and nothing else — no store, no
    /// network, no clock but the one injected.
    static func rising(in articles: [Article], now: Date = .now,
                       calendar: Calendar = .current) -> [HotTerm] {
        let recentStart = calendar.date(byAdding: .day, value: -recentDays, to: now) ?? now
        let baselineStart = calendar.date(byAdding: .day, value: -(recentDays + baselineDays),
                                          to: now) ?? now

        // When the Article *arrived*, not when it was written. ADR-0003 keeps
        // Reddit's vote-sorted feeds as ordinary Sources and records that their
        // entries carry timestamps days old — judging those by publication
        // files the evidence of a rise in the baseline it is rising against.
        func observed(_ article: Article) -> Date { article.addedAt ?? article.publishedAt }

        let recent = articles.filter { observed($0) > recentStart }
        let baseline = articles.filter {
            observed($0) <= recentStart && observed($0) > baselineStart
        }
        // Nothing to compare against is not the same as everything being new.
        // A reader whose whole history is this week has no "normal" yet, and a
        // lane filled from three Articles would be noise wearing a flame.
        guard recent.count >= mentionFloor, !baseline.isEmpty else { return [] }

        let recentCounts = documentCounts(recent)
        let baselineCounts = documentCounts(baseline)
        let recentTotal = Double(recent.count)
        let baselineTotal = Double(baseline.count)

        var scored: [HotTerm] = []
        for (term, count) in recentCounts {
            guard count >= mentionFloor, Double(count) / recentTotal >= minimumShare else { continue }
            let was = Double(baselineCounts[term] ?? 0)
            let now = Double(count)

            // Laplace-smoothed log-odds in each window, so a term absent from
            // one of them is a number rather than an infinity.
            let recentOdds = log((now + 1) / (recentTotal - now + 1))
            let baselineOdds = log((was + 1) / (baselineTotal - was + 1))
            let variance = 1 / (now + 1) + 1 / (recentTotal - now + 1)
                + 1 / (was + 1) + 1 / (baselineTotal - was + 1)
            let score = (recentOdds - baselineOdds) / variance.squareRoot()

            guard score >= minimumScore else { continue }
            scored.append(HotTerm(text: term, articles: count, rise: score))
        }

        // A story says itself several ways — "world model", "world model
        // research", "another world model" — and each is a real phrase that
        // really rose. One of them is the topic and the rest are the same news
        // again, so the best-scoring one takes the slot and anything sharing
        // its words steps aside. Ordering is total, down to the term itself, so
        // the same corpus always ranks the same way.
        return scored
            .sorted { left, right in
                if left.rise != right.rise { return left.rise > right.rise }
                let leftWords = left.text.split(separator: " ").count
                let rightWords = right.text.split(separator: " ").count
                if leftWords != rightWords { return leftWords > rightWords }
                if left.articles != right.articles { return left.articles > right.articles }
                return left.text < right.text
            }
            .reduce(into: [HotTerm]()) { kept, term in
                guard kept.count < laneSize,
                      !kept.contains(where: { $0.shares(words: term) }) else { return }
                kept.append(term)
            }
    }

    /// How many of these Articles mention each term — documents, not mentions,
    /// so one article repeating a phrase six times counts once.
    private static func documentCounts(_ articles: [Article]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for article in articles {
            for term in Set(terms(in: "\(article.title). \(article.summary ?? "")")) {
                counts[term, default: 0] += 1
            }
        }
        return counts
    }

    /// Words and short phrases worth counting: everything a reader would say
    /// out loud as a topic, and nothing that is only grammar.
    ///
    /// Phrases up to three words, because the terms this lane exists to catch
    /// are mostly phrases — "world model", "small language model" — and a
    /// single word rarely names what is new.
    ///
    /// Bare numbers are dropped, which costs the version in "Llama 4" and
    /// "GPT-5" — those read as "llama" and "gpt". Keeping them was tried and
    /// was worse: a number carries no signal that separates a version from an
    /// index, so the lane filled with "long documents 0". A term that names the
    /// model without its version is still the right topic, one release late.
    private static func terms(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = text[range].lowercased()
            if word.count > 1, !word.allSatisfy(\.isNumber) { words.append(String(word)) }
            return true
        }

        var found: [String] = []
        for length in 1...3 {
            guard words.count >= length else { break }
            for start in 0...(words.count - length) {
                let phrase = words[start..<(start + length)]
                // A phrase that starts or ends on a joining word is a fragment
                // of a sentence, not a thing anyone is talking about.
                // A phrase that starts or ends on a joining word is a fragment
                // of a sentence, not a thing anyone is talking about.
                guard let first = phrase.first, let last = phrase.last,
                      !stopWords.contains(first), !stopWords.contains(last) else { continue }
                found.append(phrase.joined(separator: " "))
            }
        }
        return found
    }

    /// English's own scaffolding, and the handful of words every tech headline
    /// carries. Not domain vocabulary: nothing here is about any field, which
    /// is what lets the same rule work for a Pack about sourdough.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "then", "than", "as", "at",
        "by", "for", "from", "in", "into", "of", "on", "onto", "to", "with",
        "is", "are", "was", "were", "be", "been", "being", "has", "have", "had",
        "do", "does", "did", "will", "would", "can", "could", "should", "may",
        "might", "must", "it", "its", "this", "that", "these", "those", "there",
        "here", "what", "which", "who", "whom", "when", "where", "why", "how",
        "all", "any", "both", "each", "few", "more", "most", "other", "some",
        "such", "no", "nor", "not", "only", "own", "same", "so", "too", "very",
        "just", "now", "new", "one", "two", "up", "out", "about", "over",
        "after", "before", "again", "still", "also", "you", "your", "we", "our",
        "they", "their", "he", "she", "his", "her", "i", "my", "me", "us",
    ]
}
