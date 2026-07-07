import SwiftUI
import SwiftData

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.publishedAt, order: .reverse) private var articles: [Article]
    @Query private var sources: [FeedSource]
    @State private var selectedCategory: String?
    @State private var isSyncing = false
    @State private var searchText = ""

    private var categories: [String] {
        Array(Set(sources.map(\.category))).sorted()
    }

    /// source name → category, for chip filtering
    private var sourceCategory: [String: String] {
        Dictionary(sources.map { ($0.name, $0.category) }, uniquingKeysWith: { first, _ in first })
    }

    private var filteredArticles: [Article] {
        var result = articles
        if let selectedCategory {
            result = result.filter { sourceCategory[$0.sourceName] == selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || ($0.summary ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    /// Day sections (design 2a): TODAY / YESTERDAY / explicit date.
    private var dayGroups: [(label: String, articles: [Article])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredArticles) { calendar.startOfDay(for: $0.publishedAt) }
        return grouped.keys.sorted(by: >).map { day in
            let label = calendar.isDateInToday(day) ? "Today"
                : calendar.isDateInYesterday(day) ? "Yesterday"
                : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            return (label, grouped[day]!.sorted { $0.publishedAt > $1.publishedAt })
        }
    }

    private var lastSynced: Date? {
        sources.compactMap(\.lastFetched).max()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header
                categoryChips
                if filteredArticles.isEmpty {
                    emptyState
                } else {
                    articleList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Article.self) { article in
                ArticleView(article: article)
            }
            .searchable(text: $searchText, prompt: "Search articles")
        }
        .task {
            // Sync on launch when cache is empty or stale (>30 min); never blocks reading.
            let stale = lastSynced.map { Date.now.timeIntervalSince($0) > 1800 } ?? true
            if stale { await sync() }
            // Catch up on any articles still awaiting on-device analysis.
            await IntelligenceService.analyzePending(context: modelContext)
        }
    }

    private func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        await FeedSyncService.syncAll(context: modelContext)
        isSyncing = false
        await IntelligenceService.analyzePending(context: modelContext)
    }

    private var header: some View {
        HStack {
            Text("TechPulse")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(isSyncing ? Theme.stateLearning : (lastSynced == nil ? Theme.stateNew : Theme.stateKnown))
                    .frame(width: 6, height: 6)
                if isSyncing {
                    Text("Syncing…")
                } else if let lastSynced {
                    Text("Synced \(lastSynced.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Not synced yet")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textSecondary)
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
                ForEach(dayGroups, id: \.label) { group in
                    Text(group.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                        .kerning(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    ForEach(group.articles) { article in
                        NavigationLink(value: article) {
                            ArticleCard(article: article)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("articleCard")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .refreshable { await sync() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            if isSyncing {
                Text("Fetching your feeds…")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.stateNew)
                Text("No articles yet")
                    .font(.system(size: 16.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Connect to the internet and pull to refresh.\nEverything fetched stays readable offline.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Sync now") { Task { await sync() } }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.stateLearning)
                    .padding(.top, 4)
            }
            Spacer()
        }
    }
}

struct ArticleCard: View {
    let article: Article

    private var preview: String {
        if let summary = article.summary, !summary.isEmpty {
            return "On-device summary — \(summary)"
        }
        return article.content.strippingHTML
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 7) {
                    if !article.isRead {
                        Circle().fill(Theme.stateLearning).frame(width: 7, height: 7)
                    }
                    Text(article.sourceName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(article.isRead ? Theme.textTertiary : Theme.textSecondary)
                }
                Spacer()
                if article.isRead {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Read")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.stateKnown)
                } else {
                    Text(article.publishedAt, format: .relative(presentation: .named))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text(article.title)
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(article.isRead ? Theme.textSecondary : Theme.textPrimary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            if !article.concepts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(article.concepts.prefix(3)) { concept in
                        ConceptChip(concept: concept)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .techPulseCard()
    }
}

struct ConceptChip: View {
    let concept: Concept
    /// Design 2b unified chip states: "+ Name" new · "Name 62%" learning · "✓ Name" known.
    var detailed = false

    private var label: String {
        guard detailed else { return concept.name }
        switch concept.masteryState {
        case .new: return "+ \(concept.name)"
        case .learning: return "\(concept.name) \(Int(concept.masteryLevel * 100))%"
        case .known: return "✓ \(concept.name)"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: detailed ? 13 : 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, detailed ? 14 : 9)
            .padding(.vertical, detailed ? 9 : 4)
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
