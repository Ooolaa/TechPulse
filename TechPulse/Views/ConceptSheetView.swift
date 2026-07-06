import SwiftUI
import SwiftData

/// Concept detail sheet, per mockup 1d: name + cluster, mastery ring,
/// definition card, related articles, "I know this" / "Quiz me".
struct ConceptSheetView: View {
    @Bindable var concept: Concept
    @Environment(\.modelContext) private var modelContext

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
            .padding(.top, 16)

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

            Text("Appears in \(concept.articles.count) article\(concept.articles.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .kerning(0.6)
                .padding(.top, 18)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(recentArticles.prefix(4)) { article in
                        articleRow(article)
                    }
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
            actionButtons
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 22)
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

            Button {} label: {
                Text("Quiz me")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 18)
                    .background(Theme.newTint, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(true)      // quiz mode ships in M6
        }
    }
}
