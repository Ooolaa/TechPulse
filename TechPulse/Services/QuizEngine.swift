import Foundation
import FoundationModels
import SwiftData

struct QuizQuestion: Identifiable {
    let id = UUID()
    let conceptName: String
    let question: String
    let options: [String]
    let correctIndex: Int
}

@Generable
struct GeneratedQuizQuestion {
    @Guide(description: "A multiple-choice question testing understanding of the concept")
    var question: String
    @Guide(description: "Exactly 4 plausible answer options")
    var options: [String]
    @Guide(description: "Index (0-3) of the correct option")
    var correctIndex: Int
}

/// Builds the weekly quiz on-device (spec M6). Foundation Models writes real
/// questions; without Apple Intelligence, questions are templated from stored
/// concept definitions so the quiz still works offline everywhere.
@MainActor
enum QuizEngine {
    /// Concepts worth quizzing: not yet mastered, recently seen, definition known.
    /// When everything qualifying is already mastered, fall back to a review
    /// quiz over mastered concepts so the feature is never a dead end.
    static func quizCandidates(context: ModelContext, limit: Int = 8) -> [Concept] {
        let all = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        let withDefinition = all.filter { !$0.conceptDefinition.isEmpty }
            .sorted { ($0.lastReviewed ?? $0.firstSeen) > ($1.lastReviewed ?? $1.firstSeen) }
        let learning = withDefinition.filter { !$0.isMarkedKnown }
        return Array((learning.isEmpty ? withDefinition : learning).prefix(limit))
    }

    static func makeQuiz(for concepts: [Concept], context: ModelContext) async -> [QuizQuestion] {
        let all = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        var questions: [QuizQuestion] = []
        for concept in concepts {
            if IntelligenceService.isModelAvailable,
               let generated = await generateQuestion(for: concept) {
                questions.append(generated)
            } else if let templated = templateQuestion(for: concept, all: all) {
                questions.append(templated)
            }
        }
        return questions
    }

    private static func generateQuestion(for concept: Concept) async -> QuizQuestion? {
        let session = LanguageModelSession(
            instructions: "You write one clear multiple-choice question testing a technical concept. Distractors must be plausible but wrong."
        )
        let context = concept.articles
            .prefix(2)
            .compactMap { $0.summary ?? String($0.content.strippingHTML.prefix(300)) }
            .joined(separator: "\n")
        let prompt = "Concept: \(concept.name)\nDefinition: \(concept.conceptDefinition)\nRecent reading:\n\(context)"
        guard let response = try? await session.respond(to: prompt, generating: GeneratedQuizQuestion.self),
              response.content.options.count == 4,
              (0..<4).contains(response.content.correctIndex) else { return nil }
        return QuizQuestion(conceptName: concept.name,
                            question: response.content.question,
                            options: response.content.options,
                            correctIndex: response.content.correctIndex)
    }

    /// Offline fallback: "which concept matches this definition". Distractors
    /// come from the same cluster first (plausible), then other pack concepts —
    /// never from stray article extractions.
    private static func templateQuestion(for concept: Concept, all: [Concept]) -> QuizQuestion? {
        let packNames = Set(KnowledgePack.concepts.map(\.name))
        let pool = all.filter { $0.name != concept.name && !$0.conceptDefinition.isEmpty }
        let sameCluster = pool.filter { $0.category == concept.category }.map(\.name).shuffled()
        let otherPack = pool.filter { $0.category != concept.category && packNames.contains($0.name) }
            .map(\.name).shuffled()
        let anyOther = pool.map(\.name).shuffled()

        var distractors: [String] = []
        for candidate in sameCluster + otherPack + anyOther where distractors.count < 3 {
            if candidate != concept.name, !distractors.contains(candidate) {
                distractors.append(candidate)
            }
        }
        guard distractors.count == 3 else { return nil }
        let correctIndex = Int.random(in: 0...3)
        var options = distractors
        options.insert(concept.name, at: correctIndex)
        return QuizQuestion(conceptName: concept.name,
                            question: "Which concept does this describe: “\(concept.conceptDefinition)”",
                            options: options,
                            correctIndex: correctIndex)
    }
}
