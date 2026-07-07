import SwiftUI
import SwiftData

/// Article detail, per mockup 1b: source/date caps, title,
/// on-device summary card (M3), concept chips (M3), body text.
struct ArticleView: View {
    @Bindable var article: Article
    @Environment(\.modelContext) private var modelContext
    @State private var selectedConcept: Concept?
    @State private var readProgress: CGFloat = 0
    @AppStorage("articleTextSize") private var textSize = "Medium"

    private var bodyFontSize: CGFloat {
        switch textSize {
        case "Small": 14
        case "Large": 17.5
        default: 15
        }
    }

    var body: some View {
        articleScroll
            .safeAreaInset(edge: .top, spacing: 0) { progressBar }
            .background(Theme.card)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                KnowledgeEngine.recordRead(article, context: modelContext)
            }
            .sheet(item: $selectedConcept) { concept in
                ConceptSheetView(concept: concept)
            }
    }

    /// Design 2b: thin bar under the nav showing how far you've read.
    private var progressBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Theme.stateLearning)
                .frame(width: max(0, geo.size.width * readProgress))
        }
        .frame(height: 3)
        .background(Color(hex: 0xEDF0F3))
    }

    private var articleScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(article.sourceName.uppercased()) · \(article.publishedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .kerning(0.6)

                Text(article.title)
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(3)
                    .padding(.top, 8)

                if let summary = article.summary, !summary.isEmpty {
                    summaryCard(summary)
                        .padding(.top, 16)
                }

                if !article.concepts.isEmpty {
                    conceptSection
                        .padding(.top, 18)
                }

                Text(article.content.strippingHTML)
                    .font(.system(size: bodyFontSize))
                    .foregroundStyle(Color(hex: 0x2B2F36))
                    .lineSpacing(6)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            let scrollable = geo.contentSize.height - geo.containerSize.height
            guard scrollable > 0 else { return 1 }
            return min(1, max(0, geo.contentOffset.y / scrollable))
        } action: { _, newValue in
            readProgress = newValue
        }
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 12))
                Text("Summary · generated on-device")
                    .kerning(0.5)
            }
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(Theme.stateLearning)
            .textCase(.uppercase)

            Text(summary)
                .font(.system(size: 13.5))
                .foregroundStyle(Color(hex: 0x374151))
                .lineSpacing(5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0xF3F7FE), Color(hex: 0xF7F9FC)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: 0xDCE7F8), lineWidth: 1))
    }

    private var conceptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Concepts in this article")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("tap to mark what you know")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            FlowLayout(spacing: 7) {
                ForEach(article.concepts) { concept in
                    Button { selectedConcept = concept } label: {
                        ConceptChip(concept: concept, detailed: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("conceptChip")
                }
            }
        }
    }
}

/// Minimal wrapping layout for chip rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, position) in zip(subviews, arrange(proposal: proposal, subviews: subviews).positions) {
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight), positions)
    }
}
