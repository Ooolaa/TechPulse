import Foundation
import NaturalLanguage
import SwiftData

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

    /// The Cluster the flagship Pack's rolling Concepts sit in. Pack data, and
    /// named here only because the Feed's own copy refers to it.
    static let cluster = "Hot Topics"

    /// Where a term the reader accepted lands.
    ///
    /// Deliberately *not* a Cluster any Pack names — "Hot Topics" is one of the
    /// flagship's own, and adopting into it would inflate that Pack's progress
    /// ("2 of 13 lit") with dots its author never wrote. `WordSelection.cluster`
    /// is kept outside `clusterOrder` for exactly this reason, and a term the
    /// reader accepted arrives the same way a looked-up word does.
    static let adoptedCluster = "Rising"

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

    // MARK: Terms with nowhere to go on the map

    /// How many candidates are offered at once. An invitation, not a backlog:
    /// a reader shown twenty things to add adds none of them.
    static let candidateLimit = 3

    /// Rising terms the reader's map has no room for yet.
    ///
    /// A term is already on the map if a Concept is named it, is spelled it
    /// once case, separators and plurals are folded away, contains it as words,
    /// or *means* it — "retrieval augmentation" against a map holding
    /// "RAG" is a duplicate the reader would have to notice was a duplicate.
    ///
    /// The fold and the distance are the two halves `ConceptIndex.match` uses,
    /// and they are here for the same reason they are there: an offer this
    /// suppresses is one the reader would have tapped to find that adopting it
    /// merged into a Concept they already had.
    ///
    /// Meaning is judged on vectors rather than by asking for a distance per
    /// pair, and the difference is not academic: `NLEmbedding.distance` embeds
    /// both of its arguments every call, so a full lane against the flagship
    /// Pack was 1,088 embeddings and two seconds inside a view update. Embedded
    /// once each, it is 76 and a few milliseconds. `vector` is injected for the
    /// same reason `SemanticLinker` injects it — so these rules can be tested
    /// against vectors a test chooses rather than whatever Apple's model
    /// believes about AI jargon.
    ///
    /// ## Why it is `async`
    ///
    /// Embedding each name once made the count small; it left the work where it
    /// was. A 600-Concept map is still two seconds of embedding, and both of
    /// the Feed's callers hold the main actor while this runs — `FeedView.task`,
    /// which reaches here directly on a launch with nothing pending to analyse,
    /// and `.onChange`, a view callback with nowhere to await at all. So the
    /// map's meanings come from `SemanticLinker.meanings`, which leaves the main
    /// actor to compute them, and the rules below read a table (#49). What stays
    /// here is the fold, and one distance per Concept per surviving term —
    /// arithmetic over vectors already in hand, bounded by
    /// `HotCandidateTests.candidatesDoNotBlockTheMainActor` at 600 Concepts.
    ///
    /// Nothing is embedded for a term the map already has by name, and nothing
    /// at all for a reader with nothing rising — the spelling pass runs first
    /// and can end the whole thing. What survives it is embedded in the same
    /// batch as the map, so there is one suspension however long the lane is.
    ///
    /// The map's size is not consulted anywhere here. Switching the meaning
    /// check off above some count is #11's ceiling, which refused to merge at
    /// exactly the map size a reader has most to gain from it.
    ///
    /// Offers only. Nothing here writes to the store: ADR-0001 keeps the map
    /// the reader's, and a Concept that appeared because an article mentioned
    /// something twice is not theirs.
    static func candidates(from terms: [HotTerm], concepts: [Concept],
                           vector: @escaping @Sendable (String) -> [Double]?
                               = SemanticLinker.embed)
    async -> [HotTerm] {
        let names = concepts.map { $0.name.lowercased() }
        // Folded once per name rather than once per pair. String work, unlike
        // the vectors below, so it is not worth making lazy.
        // Without the empty key, which is what an unnameable Concept folds to
        // and is not something a term should match.
        let foldedNames = Set(names.map(ConceptMatch.fold)).subtracting([""])

        // Carried as a pair, because the lowercased text is what the rules
        // below key on and folding it three times to save a word would be the
        // string work this pass exists to do once.
        let unnamed = terms.compactMap { term -> (term: HotTerm, text: String)? in
            let text = term.text.lowercased()
            // One direction only. A Concept named "World Model Research" already
            // covers "world model", so that term is a duplicate — but a map
            // holding "Attention" does *not* cover "attention sinks", and
            // suppressing that would silence the extensions this exists to
            // catch. `shares(words:)` is symmetric because collapsing a ranked
            // lane wants it to be; membership does not.
            let named = foldedNames.contains(ConceptMatch.fold(text))
                || names.contains { name in name == text || covers(name, text) }
            return named ? nil : (term, text)
        }
        guard !unnamed.isEmpty else { return [] }

        // The map and the terms left to weigh against it, in one batch and one
        // suspension. Terms past `candidateLimit` are embedded too: whether an
        // earlier one takes the slot is what the meaning check is about to
        // decide, and that is at most a lane's worth of names against a map's.
        let meanings = await SemanticLinker.meanings(of: names + unnamed.map(\.text),
                                                     using: vector)

        var offered: [HotTerm] = []
        for candidate in unnamed where offered.count < candidateLimit {
            // An empty vector is a name the embedding could not place, and
            // `distance` refuses it — so an unplaceable term is offered rather
            // than silently matched against everything.
            let termVector = meanings[candidate.text] ?? []
            let meant = names.contains { name in
                SemanticLinker.distance(between: termVector, and: meanings[name] ?? [])
                    .map { $0 < ConceptIndex.sameIdeaDistance } ?? false
            }
            if !meant { offered.append(candidate.term) }
        }
        return offered
    }

    /// Whether a Concept's name already says the whole of this term, as words.
    private static func covers(_ name: String, _ term: String) -> Bool {
        let haystack = name.split(separator: " ")
        let needle = term.split(separator: " ")
        guard needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { start in
            Array(haystack[start..<(start + needle.count)]) == needle
        }
    }

    /// Puts an accepted candidate on the map, or hands back the Concept that
    /// turned out to already be there.
    ///
    /// Title-cased, because every other Concept is: a Pack names "World Model",
    /// and a term lifted from a headline should not sit beside it in lower
    /// case. New and unlit, like any Concept a Pack brings — what the reader
    /// knows is theirs to earn, not something accepting an offer grants.
    ///
    /// It arrives with no definition, which is the one way it does not behave
    /// like a Pack's Concept: `QuizEngine` only asks about Concepts that have
    /// one, so an adopted term cannot be quizzed until something writes it.
    /// Writing one means asking a model, and `IntelligenceService.define`
    /// routes through `ExplainTier` — which can choose the opt-in path. Sending
    /// a term to Anthropic because it got hot, rather than because the reader
    /// asked what it means, would be egress ADR-0006 never enumerated. That is
    /// a decision to take deliberately, not a side effect of this button.
    ///
    /// `async` because accepting an offer is a de-duplication pass like any
    /// other, and building the index over a large map is work for another
    /// thread (#42) — not for the one the chip was tapped on.
    @discardableResult
    static func adopt(_ term: HotTerm, context: ModelContext) async -> Concept? {
        let prior = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        var index = await ConceptIndex.prepared(prior)

        // The map is read again on the other side of that suspension, because
        // it can move while this pass is embedding. The chip that started this
        // is still on screen for as long as the embedding takes — two seconds
        // on a large map — so a second tap is a window a thumb can hit rather
        // than a theoretical interleaving, and both passes would otherwise
        // match against a map neither had written to yet and create the
        // Concept twice. `insert` is the same seam a Concept created part way
        // through an analysis batch goes through.
        let settled = (try? context.fetch(FetchDescriptor<Concept>())) ?? prior
        for concept in settled where !prior.contains(where: { $0 === concept }) {
            index.insert(concept)
        }

        guard let concept = KnowledgeEngine.findOrCreateConcept(
            named: adoptedName(term), category: adoptedCluster, definition: "",
            context: context, index: &index
        ) else { return nil }

        // Unlit, the way `PackInstaller` starts a Pack's Concepts — accepting
        // an offer puts a dot on the map, it does not claim the reader knows
        // anything. Only for a Concept that was not already there: this may
        // have matched something they have been reading about for weeks, and
        // `isNewlyCreated` is the check that tells the two apart. Against the
        // settled map, not the one this pass started from: a Concept another
        // pass just created is not this one's to set back to unlit.
        if KnowledgeEngine.isNewlyCreated(concept, priorConcepts: settled) {
            concept.masteryLevel = 0
        }
        return concept
    }

    /// The name an accepted term will carry on the map — the offer says this,
    /// so the chip and the dot it makes read the same.
    static func adoptedName(_ term: HotTerm) -> String { titleCased(term.text) }

    private static func titleCased(_ text: String) -> String {
        text.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
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
