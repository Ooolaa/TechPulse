import SwiftUI
import SwiftData

/// Concept detail sheet, per mockup 1d: name + cluster, mastery ring,
/// definition card, related articles, "I know this" / "Quiz me".
struct ConceptSheetView: View {
    @Bindable var concept: Concept
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allLinks: [ConceptLink]
    @Query private var allConcepts: [Concept]
    @State private var quizzing = false
    @State private var deepening = false
    @State private var deepenedNames: [String] = []

    /// Concepts linked to this one, heaviest edges first (design 2d).
    private var relatedConcepts: [Concept] {
        let neighborWeights = allLinks.reduce(into: [String: Int]()) { acc, link in
            if link.conceptA == concept.name { acc[link.conceptB, default: 0] += link.weight }
            if link.conceptB == concept.name { acc[link.conceptA, default: 0] += link.weight }
        }
        return allConcepts
            .filter { neighborWeights[$0.name] != nil }
            .sorted { neighborWeights[$0.name, default: 0] > neighborWeights[$1.name, default: 0] }
    }

    private var stateColor: Color {
        switch concept.masteryState {
        case .new: Theme.stateNew
        case .learning: Theme.stateLearning
        case .known: Theme.stateKnown
        }
    }

    private var recentArticles: [Article] {
        concept.articles.sorted { $0.publishedAt > $1.publishedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text("✕")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.newTint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("closeSheet")
            }
            .padding(.top, 12)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(concept.name)
                        .font(.system(size: 23, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(concept.category) cluster · first seen \(concept.firstSeen.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                masteryRing
            }
            .padding(.top, 2)

            if !concept.conceptDefinition.isEmpty {
                Text(concept.conceptDefinition)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x374151))
                    .lineSpacing(5)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 14)
            }

            if !relatedConcepts.isEmpty {
                Text("Related concepts")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .padding(.top, 16)
                FlowLayout(spacing: 7) {
                    ForEach(relatedConcepts.prefix(6)) { related in
                        ConceptChip(concept: related, detailed: true)
                    }
                }
                .padding(.top, 8)
            }

            Text("Appears in \(concept.articles.count) article\(concept.articles.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .kerning(0.6)
                .padding(.top, 16)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(recentArticles.prefix(4)) { article in
                        articleRow(article)
                    }
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
            goDeeperButton
                .padding(.top, 12)
            actionButtons
                .padding(.top, 10)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 22)
        .sensoryFeedback(.success, trigger: concept.isMarkedKnown)
        .presentationDetents([.fraction(0.67), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private var masteryRing: some View {
        ZStack {
            Circle()
                .stroke(stateColor.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: concept.masteryLevel)
                .stroke(stateColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(concept.masteryLevel * 100))%")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(stateColor)
        }
        .frame(width: 56, height: 56)
    }

    private func articleRow(_ article: Article) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(article.sourceName) · \(article.publishedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    /// The pull direction of learning: expand this concept into 3–5 related
    /// sub-concepts on the map, instead of waiting for the feed to bring them.
    private var goDeeperButton: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                deepening = true
                Task {
                    let added = await IntelligenceService.deepen(concept, context: modelContext)
                    deepenedNames = added.map(\.name)
                    deepening = false
                }
            } label: {
                HStack(spacing: 8) {
                    if deepening {
                        ProgressView().controlSize(.small)
                        Text("Growing the map…")
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text(deepenedNames.isEmpty ? "Go deeper — grow related dots"
                                                   : "Added \(deepenedNames.count) dots ✓")
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(IntelligenceService.isModelAvailable ? Theme.stateLearning : Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.learningTint.opacity(IntelligenceService.isModelAvailable ? 1 : 0.4),
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(deepening || !IntelligenceService.isModelAvailable || !deepenedNames.isEmpty)
            .accessibilityIdentifier("goDeeper")
            .sensoryFeedback(.success, trigger: deepenedNames.count)

            if !IntelligenceService.isModelAvailable {
                Text("Needs Apple Intelligence for on-device generation.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            } else if !deepenedNames.isEmpty {
                Text(deepenedNames.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.stateLearning)
                    .lineLimit(2)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                KnowledgeEngine.markKnown(concept, context: modelContext)
            } label: {
                Text(concept.isMarkedKnown ? "Known ✓" : "✓ I know this")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(concept.isMarkedKnown ? Theme.stateKnown.opacity(0.5) : Theme.stateKnown,
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(concept.isMarkedKnown)
            .accessibilityIdentifier("knowButton")

            Button { quizzing = true } label: {
                Text("Quiz me")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(concept.conceptDefinition.isEmpty ? Theme.textTertiary : Color(hex: 0x4B5563))
                    .padding(.vertical, 15)
                    .padding(.horizontal, 18)
                    .background(Theme.newTint, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(concept.conceptDefinition.isEmpty)   // template questions need a definition
            .fullScreenCover(isPresented: $quizzing) {
                QuizView(concepts: [concept])
            }
        }
    }
}
