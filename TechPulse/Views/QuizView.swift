import SwiftUI
import SwiftData

/// Weekly quiz flow (mockups 3b question card, 3c result screen).
struct QuizView: View {
    let concepts: [Concept]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var selected: Int?
    @State private var checked = false
    @State private var results: [(concept: Concept, passed: Bool, before: Concept.MasteryState)] = []
    @State private var finished = false
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                VStack(spacing: 10) {
                    Text("Preparing your quiz…")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("generated on-device · works offline")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            } else if finished || questions.isEmpty {
                QuizResultView(results: results) { dismiss() }
            } else {
                questionScreen
            }
        }
        .task {
            questions = await QuizEngine.makeQuiz(for: concepts, context: modelContext)
            loading = false
        }
    }

    // MARK: Question card (3b)

    private var questionScreen: some View {
        let question = questions[index]
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Text("✕")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Weekly quiz")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x4B5563))
                Spacer()
                Text("\(index + 1) / \(questions.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(minWidth: 38, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            ProgressView(value: Double(index + (checked ? 1 : 0)), total: Double(questions.count))
                .tint(Theme.stateLearning)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Cluster, not concept name — the name would spoil
                    // "which concept does this describe" questions.
                    Text(concepts.first { $0.name == question.conceptName }?.category ?? "Review")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.stateLearning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.learningTint, in: Capsule())

                    Text(question.question)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(4)
                        .padding(.top, 14)

                    VStack(spacing: 10) {
                        ForEach(question.options.indices, id: \.self) { optionIndex in
                            optionRow(question: question, optionIndex: optionIndex)
                        }
                    }
                    .padding(.top, 22)

                    HStack(spacing: 7) {
                        Image(systemName: "smallcircle.filled.circle")
                            .font(.system(size: 11))
                        Text("Generated on-device from your reading — works offline")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
            }

            Button {
                if checked { advance() } else { check() }
            } label: {
                Text(checked ? (index + 1 == questions.count ? "See results" : "Next question") : "Check answer")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(selected == nil ? Theme.stateNew : Theme.stateLearning,
                                in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(selected == nil)
            .accessibilityIdentifier("quizAction")
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Theme.background)
        .sensoryFeedback(trigger: checked) { _, isChecked in
            guard isChecked else { return nil }
            return selected == question.correctIndex ? .success : .error
        }
    }

    private func optionRow(question: QuizQuestion, optionIndex: Int) -> some View {
        let isSelected = selected == optionIndex
        let isCorrect = optionIndex == question.correctIndex
        let borderColor: Color = checked
            ? (isCorrect ? Theme.stateKnown : (isSelected ? Color(hex: 0xD9534F) : Theme.cardBorder))
            : (isSelected ? Theme.stateLearning : Theme.cardBorder)
        let background: Color = checked
            ? (isCorrect ? Theme.knownTint : (isSelected ? Color(hex: 0xFDF0EF) : Theme.card))
            : (isSelected ? Color(hex: 0xF3F7FE) : Theme.card)

        return Button {
            guard !checked else { return }
            selected = optionIndex
        } label: {
            HStack(spacing: 10) {
                Text(question.options[optionIndex])
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x374151))
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if (checked && isCorrect) || (!checked && isSelected) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(checked ? Theme.stateKnown : Theme.stateLearning, in: Circle())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(borderColor, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quizOption")
    }

    private func check() {
        guard let selected else { return }
        checked = true
        let question = questions[index]
        if let concept = concepts.first(where: { $0.name == question.conceptName }) {
            let passed = selected == question.correctIndex
            results.append((concept, passed, concept.masteryState))
            KnowledgeEngine.recordQuizResult(concept, passed: passed, context: modelContext)
        }
    }

    private func advance() {
        if index + 1 == questions.count {
            finished = true
        } else {
            index += 1
            selected = nil
            checked = false
        }
    }
}

// MARK: Result screen (3c)

struct QuizResultView: View {
    let results: [(concept: Concept, passed: Bool, before: Concept.MasteryState)]
    var onDone: () -> Void

    private var score: Int { results.filter(\.passed).count }

    private func stateName(_ state: Concept.MasteryState) -> String {
        switch state {
        case .new: "new"
        case .learning: "learning"
        case .known: "known"
        }
    }

    private func stateColor(_ state: Concept.MasteryState) -> Color {
        switch state {
        case .new: Theme.stateNew
        case .learning: Theme.stateLearning
        case .known: Theme.stateKnown
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(Theme.knownTint, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: results.isEmpty ? 0 : CGFloat(score) / CGFloat(results.count))
                    .stroke(Theme.stateKnown, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(score)/\(results.count)")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Theme.stateKnown)
                    Text("correct")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 110, height: 110)
            .padding(.top, 34)

            Text(score * 2 >= results.count ? "Strong week" : "Keep reading")
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 16)
            Text("Quiz results update your knowledge map.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 5)

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Mastery changes")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                        .kerning(0.8)
                        .padding(.horizontal, 4)
                    ForEach(results, id: \.concept.name) { result in
                        resultRow(result)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quizDone")
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Theme.background)
    }

    private func resultRow(_ result: (concept: Concept, passed: Bool, before: Concept.MasteryState)) -> some View {
        let after = result.concept.masteryState
        return HStack {
            HStack(spacing: 11) {
                Circle().fill(stateColor(after)).frame(width: 11, height: 11)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.concept.name)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(result.passed
                         ? (result.before == after ? "+0.3 mastery" : "\(stateName(result.before)) → \(stateName(after))")
                         : "missed — queued for next week")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            if result.passed {
                Text("+0.3")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(stateColor(after))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .techPulseCard()
    }
}
