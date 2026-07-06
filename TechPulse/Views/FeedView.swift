import SwiftUI
import SwiftData

struct FeedView: View {
    @Query(sort: \Article.publishedAt, order: .reverse) private var articles: [Article]
    @State private var selectedCategory: String?

    private let categories = ["LLMs", "Agents", "Vision", "Chips"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header
                categoryChips
                if articles.isEmpty {
                    emptyState
                } else {
                    articleList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack {
            Text("TechPulse")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            // Offline-first: no spinners, just a "last synced" pill.
            HStack(spacing: 6) {
                Circle().fill(Theme.stateKnown).frame(width: 6, height: 6)
                Text("Not synced yet")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isSelected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(categories, id: \.self) { category in
                    chip(category, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Theme.textPrimary : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var articleList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(articles) { article in
                    ArticleCard(article: article)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 34))
                .foregroundStyle(Theme.stateNew)
            Text("No articles yet")
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Feed sync arrives in Milestone 2.\nYour reading list will cache here for offline use.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

struct ArticleCard: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(article.sourceName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(article.publishedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(article.title)
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(2)
            if let summary = article.summary {
                Text("On-device summary — \(summary)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
            }
            if !article.concepts.isEmpty {
                conceptTags
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .techPulseCard()
        .opacity(article.isRead ? 0.65 : 1)
    }

    private var conceptTags: some View {
        HStack(spacing: 6) {
            ForEach(article.concepts.prefix(3)) { concept in
                ConceptChip(concept: concept)
            }
        }
    }
}

struct ConceptChip: View {
    let concept: Concept

    var body: some View {
        Text(concept.name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch concept.masteryState {
        case .new: Theme.textSecondary
        case .learning: Theme.stateLearning
        case .known: Theme.stateKnown
        }
    }

    private var background: Color {
        switch concept.masteryState {
        case .new: Theme.newTint
        case .learning: Theme.learningTint
        case .known: Theme.knownTint
        }
    }
}

#Preview {
    FeedView()
        .modelContainer(PreviewData.container)
}
