import Testing
import Foundation
@testable import TechPulse

/// ADR-0003: what is hot is inferred from the reader's own Sources, not typed
/// by anyone. The rule has to separate *rising* from *merely common*, work for
/// a field nobody anticipated, and say nothing at all when it has nothing to
/// go on (#12).
@MainActor
@Suite("Hot topics")
struct HotTopicsTests {

    private static let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 20
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    private func article(_ title: String, daysAgo: Int, summary: String = "",
                         publishedDaysAgo: Int? = nil) -> Article {
        let day = { (back: Int) in
            Calendar.current.date(byAdding: .day, value: -back, to: Self.now)!
        }
        let article = Article(guid: "\(title)-\(daysAgo)-\(UUID().uuidString)", title: title,
                              content: "body", publishedAt: day(publishedDaysAgo ?? daysAgo),
                              sourceName: "s")
        article.addedAt = day(daysAgo)
        article.summary = summary
        return article
    }

    private func terms(_ articles: [Article]) -> [String] {
        HotTopics.rising(in: articles, now: Self.now).map(\.text)
    }

    // MARK: Nothing to go on

    @Test("a fresh install has no hot topics, and does not pretend otherwise")
    func noArticles() {
        #expect(HotTopics.rising(in: [], now: Self.now).isEmpty)
    }

    @Test("two articles are not a trend")
    func tooFewArticles() {
        // One mention is an anecdote. A lane that fills up from a single
        // article is a lane that says something new every morning and means
        // nothing by it.
        let articles = [article("Vibe coding is everywhere", daysAgo: 0),
                        article("A quiet week in robotics", daysAgo: 1)]
        #expect(terms(articles).isEmpty)
    }

    // MARK: Rising, not merely common

    @Test("a term rising this week beats one that is always there")
    func risingBeatsCommon() {
        // "model" is in everything, all the time — the background hum of this
        // reader's Sources. "world model" arrives this week.
        var articles = (3...20).map { article("A model of something \($0)", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("World model research accelerates", daysAgo: day),
             article("Another world model result", daysAgo: day)]
        }
        let ranked = terms(articles)
        #expect(ranked.first == "world model")
        #expect(!ranked.contains("model"), "a term in every article all month is not news")
    }

    @Test("a term that is common in both windows is not rising")
    func steadyTermsAreNotHot() {
        let articles = (0...20).map { article("Agents everywhere \($0)", daysAgo: $0) }
        #expect(!terms(articles).contains("agents"))
    }

    @Test("a single mention does not become a topic")
    func oneMentionIsNoise() {
        var articles = (3...20).map { article("Routine coverage \($0)", daysAgo: $0) }
        articles.append(article("Zettelkasten changes everything", daysAgo: 0))
        #expect(!terms(articles).contains("zettelkasten"))
    }

    @Test("a term rising a lot beats a term rising from nothing")
    func magnitudeBeatsNovelty() {
        // The failure a ratio of shares has: a term appearing three times where
        // it never appeared scores infinitely well, and a term going from a
        // fifth of the feed to two thirds scores about three. The second is the
        // story; the first is a new Source saying hello.
        var articles: [Article] = []
        for day in 4...20 {
            articles += (0..<5).map { article("Gpt six ships again \($0)", daysAgo: day) }
            articles += (0..<20).map { article("Ordinary coverage \(day)-\($0)", daysAgo: day) }
        }
        for day in 0...2 {
            articles += (0..<16).map { article("Gpt six everywhere \(day)-\($0)", daysAgo: day) }
            articles += (0..<8).map { article("Ordinary coverage \(day)-\($0)", daysAgo: day) }
            articles.append(article("Show hn my weekend project \(day)", daysAgo: day))
        }
        let ranked = terms(articles)
        #expect(ranked.first?.contains("gpt six") == true,
                "the lane led with “\(ranked.first ?? "nothing")”")
        #expect(!ranked.contains(where: { $0.contains("weekend") }),
                "three mentions from one new Source is not a trend")
    }

    @Test("one story takes one slot, not five")
    func oneSlotPerStory() {
        var articles = (4...20).map { article("Background \($0)", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("World model research accelerates", daysAgo: day),
             article("Another world model result", daysAgo: day),
             article("World model work continues", daysAgo: day)]
        }
        let ranked = terms(articles)
        let aboutWorldModels = ranked.filter { $0.contains("world model") || $0 == "world" }
        #expect(aboutWorldModels.count == 1,
                "one story filled \(aboutWorldModels.count) slots: \(aboutWorldModels)")
    }

    @Test("the same corpus ranks the same way twice")
    func rankingIsDeterministic() {
        var articles = (4...20).map { article("Background coverage \($0)", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("Alpha beta gamma", daysAgo: day), article("Delta epsilon zeta", daysAgo: day)]
        }
        #expect(terms(articles) == terms(articles))
    }

    @Test("a release is named without its version, and a stray number is never a topic")
    func numbersAreNotTerms() {
        // The accepted narrowing: "Llama 4" surfaces as "llama". Allowing bare
        // numbers was tried and filled the lane with "long documents 0" — a
        // number carries nothing that separates a version from an index.
        var articles = (4...20).map { article("Model coverage", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("Llama 4 lands with weights", daysAgo: day),
             article("Everyone is running llama 4", daysAgo: day),
             article("Benchmarks for llama 4", daysAgo: day)]
        }
        let ranked = terms(articles)
        #expect(ranked.contains("llama"))
        #expect(!ranked.contains { $0.contains(where: \.isNumber) })
    }

    @Test("the window is when an Article arrived, not when it was written")
    func windowsFollowArrival() {
        // ADR-0003: a Reddit "top this week" entry arrives today carrying a
        // six-day-old timestamp. Judging it by publication buries the evidence
        // in the baseline it is supposed to be rising against.
        var articles = (4...20).map { article("Background \($0)", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("Sparse attention wins", daysAgo: day, publishedDaysAgo: day + 6),
             article("More sparse attention", daysAgo: day, publishedDaysAgo: day + 6),
             article("Sparse attention again", daysAgo: day, publishedDaysAgo: day + 6)]
        }
        #expect(terms(articles).contains { $0.contains("sparse attention") })
    }

    // MARK: What counts as a term

    @Test("a phrase is found as a phrase, not only as its words")
    func multiWordTerms() {
        var articles = (3...20).map { article("General coverage \($0)", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("Small language model beats the big one", daysAgo: day),
             article("Another small language model ships", daysAgo: day)]
        }
        #expect(terms(articles).contains("small language model"))
    }

    @Test("the words English uses everywhere are never topics")
    func stopWordsAreNeverTerms() {
        var articles = (3...20).map { article("Coverage of the thing \($0)", daysAgo: $0) }
        articles += (0...2).map { article("This is the one that with from have", daysAgo: $0) }
        let ranked = terms(articles)
        for word in ["the", "this", "that", "with", "from", "have", "is", "one"] {
            #expect(!ranked.contains(word), "“\(word)” is not a topic")
        }
    }

    // MARK: Any field, not this one

    @Test("the rule knows nothing about AI, and works on a field it never saw")
    func worksForAnyField() {
        // ADR-0003's point: nothing here is specific to the flagship Pack.
        var articles = (3...20).map { article("Weeknight dinners \($0)", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("Sourdough starter revival", daysAgo: day),
             article("A sourdough starter guide", daysAgo: day)]
        }
        #expect(terms(articles).contains("sourdough starter"))
    }

    @Test("the summary counts as well as the title, because the filter reads both")
    func summariesAreRead() {
        var articles = (3...20).map { article("Coverage \($0)", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("Untitled \(day)a", daysAgo: day, summary: "Retrieval augmentation, again."),
             article("Untitled \(day)b", daysAgo: day, summary: "More retrieval augmentation.")]
        }
        #expect(terms(articles).contains("retrieval augmentation"))
    }

    @Test("a shorter term is dropped only when it is a word of a longer one")
    func dedupeIsOnWordsNotSubstrings() {
        // "model" is inside "modelling" as characters and has nothing to do
        // with it as a word. Dropping one because the other was kept would
        // silently lose a real topic.
        var articles = (3...20).map { article("Background \($0)", daysAgo: $0) }
        articles += (0...2).flatMap { day in
            [article("Modelling workflows change", daysAgo: day),
             article("More modelling workflows", daysAgo: day),
             article("Agent model routing", daysAgo: day),
             article("Better agent model routing", daysAgo: day)]
        }
        let ranked = terms(articles)
        #expect(ranked.contains("modelling workflows"))
        #expect(ranked.contains("agent model routing"))
    }

    @Test("a word is not swallowed by a longer word it happens to sit inside")
    func dedupeDoesNotEatUnrelatedWords() {
        // "modelling" contains "model" as characters and not as a word. The
        // surrounding words differ every time, so each is only ever a term on
        // its own — and both are genuinely rising.
        var articles = (3...20).map { article("Background \($0)", daysAgo: $0) }
        let around = ["alpha", "beta", "gamma", "delta"]
        articles += around.enumerated().map { index, word in
            article("Modelling \(word)", daysAgo: index % 3)
        }
        articles += around.enumerated().map { index, word in
            article("\(word.capitalized) model", daysAgo: index % 3)
        }
        let ranked = terms(articles)
        #expect(ranked.contains("modelling"))
        #expect(ranked.contains("model"), "“model” was dropped because “modelling” contains it")
    }

    @Test("a full intake window does not hold the Feed up")
    func realisticCorpusIsPrompt() {
        // The intake cap is 30 Articles a day, and the rule looks back three
        // weeks — so this is what a reader who has been here a month hands it.
        // It runs whenever the Feed's Article count changes, which is why the
        // shape of the work is worth a guard.
        let headlines = [
            "Retrieval augmentation improves grounding on long documents",
            "A small language model matches a larger one on reasoning",
            "World model research accelerates across three labs",
            "Agents ship to production at last, with caveats",
            "Open weights arrive for a frontier-class release",
        ]
        // Real headlines, with nothing in them that a real feed would not
        // carry — an index in the title would invent terms of its own.
        var articles = (3..<20).flatMap { day in
            (0..<30).map { index in
                article(headlines[index % headlines.count], daysAgo: day,
                        summary: "A summary repeating the point about \(headlines[index % headlines.count].lowercased()).")
            }
        }
        // And one story that really did arrive this week.
        articles += (0...2).flatMap { day in
            (0..<20).map { _ in article("Sparse attention changes the economics", daysAgo: day) }
        }
        articles += (0...2).flatMap { day in
            (0..<10).map { index in
                article(headlines[index % headlines.count], daysAgo: day)
            }
        }

        let started = Date.now
        let ranked = HotTopics.rising(in: articles, now: Self.now)
        let elapsed = Date.now.timeIntervalSince(started)

        // Generous against a debug simulator build: a guard on the shape of the
        // work, not a benchmark.
        #expect(elapsed < 3, "ranking \(articles.count) Articles took \(elapsed)s")
        // Bounded *and* non-empty: a lane of nothing would satisfy the bound
        // while proving the ranking never ran.
        #expect(!ranked.isEmpty)
        #expect(ranked.count <= HotTopics.laneSize)
    }

    @Test("the lane is bounded, so it stays a lane and not a list")
    func rankingIsBounded() {
        var articles = (3...30).map { article("Background \($0)", daysAgo: $0) }
        for index in 0...9 {
            articles += (0...2).flatMap { day in
                [article("Topic\(index) surges now", daysAgo: day),
                 article("More on topic\(index) today", daysAgo: day)]
            }
        }
        #expect(terms(articles).count <= HotTopics.laneSize)
    }
}
