import Testing
import Foundation
@testable import TechPulse

@Suite("Word selection")
struct WordSelectionTests {

    // MARK: Accepted

    @Test("a single word passes through")
    func singleWord() {
        #expect(WordSelection.normalize("transformer") == "transformer")
    }

    @Test("surrounding punctuation and quotes are stripped")
    func stripsPunctuation() {
        #expect(WordSelection.normalize("(\"transformer\"),") == "transformer")
        #expect(WordSelection.normalize("  quantization.  ") == "quantization")
        #expect(WordSelection.normalize("“RAG”") == "RAG")
    }

    @Test("a short phrase is a legitimate term")
    func shortPhrase() {
        #expect(WordSelection.normalize("mixture of experts") == "mixture of experts")
    }

    @Test("internal whitespace runs collapse")
    func collapsesWhitespace() {
        #expect(WordSelection.normalize("mixture   of  experts") == "mixture of experts")
    }

    @Test("hyphenated and dotted terms survive")
    func internalPunctuation() {
        #expect(WordSelection.normalize("fine-tuning") == "fine-tuning")
        #expect(WordSelection.normalize("GPT-4o") == "GPT-4o")
    }

    @Test("terms ending in a trailing symbol survive, since the symbol is part of the name")
    func trailingSymbolIsPartOfTheTerm() {
        #expect(WordSelection.normalize("C++") == "C++")
        #expect(WordSelection.normalize("C#") == "C#")
        #expect(WordSelection.normalize("F#") == "F#")
        // Still strips a genuine wrapping quote/punctuation around such a term.
        #expect(WordSelection.normalize("(\"C++\"),") == "C++")
    }

    // MARK: Rejected — these must never reach a model call

    @Test("a paragraph drag is rejected on the newline")
    func rejectsNewlines() {
        #expect(WordSelection.normalize("first block\n\nsecond block") == nil)
    }

    @Test("prose longer than the word cap is rejected")
    func rejectsTooManyWords() {
        #expect(WordSelection.normalize("one two three four five six") != nil)   // exactly at cap
        #expect(WordSelection.normalize("one two three four five six seven") == nil)
    }

    @Test("a long single run is rejected on the character cap")
    func rejectsTooLong() {
        #expect(WordSelection.normalize(String(repeating: "a", count: 61)) == nil)
    }

    @Test("empty, whitespace, and punctuation-only selections are rejected")
    func rejectsEmpty() {
        #expect(WordSelection.normalize("") == nil)
        #expect(WordSelection.normalize("   ") == nil)
        #expect(WordSelection.normalize("—") == nil)
        #expect(WordSelection.normalize("()") == nil)
    }

    @Test("a selection with no letters is rejected")
    func rejectsNonLetters() {
        #expect(WordSelection.normalize("42") == nil)
        #expect(WordSelection.normalize("3.14") == nil)
    }

    @Test("a single character is too little to explain")
    func rejectsSingleCharacter() {
        #expect(WordSelection.normalize("a") == nil)
    }

    // MARK: Disambiguation context

    @Test("context window surrounds the selection and trims partial words")
    func contextWindow() {
        let text = "The transformer architecture replaced recurrent networks in most tasks."
        let range = text.range(of: "transformer")!
        let excerpt = WordSelection.context(in: text, around: range, radius: 12)

        #expect(excerpt.contains("transformer"))
        // Radius clips mid-word at both edges; those partials must be dropped.
        #expect(!excerpt.hasPrefix("he "))
        #expect(excerpt == excerpt.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("context at the very start and end of the text doesn't crash or over-trim")
    func contextAtBoundaries() {
        let text = "Quantization shrinks a model."
        let first = text.range(of: "Quantization")!
        #expect(WordSelection.context(in: text, around: first, radius: 500) == text)

        let last = text.range(of: "model")!
        #expect(WordSelection.context(in: text, around: last, radius: 500) == text)
    }

    @Test("vocabulary cluster stays outside the curated pack")
    func vocabularyClusterIsSeparate() {
        // Otherwise looked-up words would inflate pack progress ("2 of 13 lit").
        #expect(!KnowledgePack.clusterOrder.contains(WordSelection.cluster))
    }
}
