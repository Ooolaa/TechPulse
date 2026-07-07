import SwiftUI
import SwiftData

/// Knowledge tab (design 4a): the map of a professional AI engineer as
/// cluster cards — lit vs dim — with a GAP badge and the specialty lane.
struct KnowledgeMapView: View {
    @Query private var concepts: [Concept]
    @State private var searchText = ""
    @State private var selectedConcept: Concept?

    private var searchResults: [Concept] {
        guard !searchText.isEmpty else { return [] }
        return concepts
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.masteryLevel > $1.masteryLevel }
    }

    private var stats: [KnowledgePathEngine.ClusterStats] {
        KnowledgePathEngine.clusterStats(concepts: concepts)
    }

    private var gapCluster: String? {
        KnowledgePathEngine.gapCluster(concepts: concepts)
    }

    private var totalLit: (lit: Int, total: Int) {
        (concepts.filter(KnowledgePathEngine.isLit).count, concepts.count)
    }

    private var gridStats: [KnowledgePathEngine.ClusterStats] {
        stats.filter { $0.name != KnowledgePack.specialtyCluster }
    }

    private var specialty: KnowledgePathEngine.ClusterStats? {
        stats.first { $0.name == KnowledgePack.specialtyCluster }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Knowledge")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(totalLit.lit) of \(totalLit.total) lit")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
                    }
                    Text("The map of a professional AI engineer. Light it up.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)

                    if !searchText.isEmpty {
                        searchResultsList
                    } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                              spacing: 10) {
                        ForEach(gridStats, id: \.name) { cluster in
                            NavigationLink(value: cluster.name) {
                                ClusterCard(stats: cluster, isGap: cluster.name == gapCluster)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("clusterCard")
                        }
                    }
                    .padding(.top, 12)

                    if let specialty {
                        NavigationLink(value: specialty.name) {
                            specialtyBanner(specialty)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("clusterCard")
                        .padding(.top, 10)
                    }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { clusterName in
                ClusterDetailView(clusterName: clusterName)
            }
            .searchable(text: $searchText, prompt: "Search concepts")
            .sheet(item: $selectedConcept) { concept in
                ConceptSheetView(concept: concept)
            }
        }
    }

    /// Design 2c/4a: search across every concept, tap → detail sheet.
    private var searchResultsList: some View {
        VStack(spacing: 8) {
            ForEach(searchResults.prefix(12)) { concept in
                Button { selectedConcept = concept } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(concept.name)
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(concept.category)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        ConceptChip(concept: concept, detailed: true)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .techPulseCard()
                }
                .buttonStyle(.plain)
            }
            if searchResults.isEmpty {
                Text("No concepts match “\(searchText)”")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 30)
            }
        }
        .padding(.top, 12)
    }

    private func specialtyBanner(_ stats: KnowledgePathEngine.ClusterStats) -> some View {
        HStack {
            HStack(spacing: 11) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.stateLearning)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(stats.name) — your specialty lane")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(stats.lit) of \(stats.total) lit")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.stateLearning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [Color(hex: 0xF3F7FE), .white],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: Theme.cardRadius)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(Color(hex: 0xDCE7F8), lineWidth: 1))
    }
}

/// One cluster tile: mini-net preview, "N of M lit", progress bar, GAP badge.
struct ClusterCard: View {
    let stats: KnowledgePathEngine.ClusterStats
    let isGap: Bool

    private var barColor: Color {
        if stats.lit == 0 { return Theme.stateNew }
        return stats.ratio >= 0.7 ? Theme.stateKnown : Theme.stateLearning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                miniNet
                Spacer()
                if isGap {
                    Text("GAP")
                        .font(.system(size: 9.5, weight: .bold))
                        .kerning(0.3)
                        .foregroundStyle(Theme.stateLearning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.learningTint, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.name)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(stats.lit) of \(stats.total) lit")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xEDF0F3))
                    Capsule().fill(barColor)
                        .frame(width: max(4, geo.size.width * stats.ratio))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(isGap ? Color(hex: 0xD6E4FA) : Theme.cardBorder,
                          lineWidth: isGap ? 1.5 : 1))
    }

    /// Tiny abstract net whose dot colors reflect the cluster's completion.
    private var miniNet: some View {
        let dotColors: [Color] = (0..<4).map { index in
            Double(index) / 4 < stats.ratio ? (stats.ratio >= 0.7 ? Theme.stateKnown : Theme.stateLearning) : Theme.stateNew
        }
        return Canvas { ctx, _ in
            let points = [CGPoint(x: 8, y: 9), CGPoint(x: 24, y: 6),
                          CGPoint(x: 22, y: 21), CGPoint(x: 37, y: 10)]
            for (a, b) in [(0, 1), (0, 2), (2, 3)] {
                var path = Path()
                path.move(to: points[a])
                path.addLine(to: points[b])
                ctx.stroke(path, with: .color(Color(hex: 0xDDE3EA)), lineWidth: 1.2)
            }
            for (index, point) in points.enumerated() {
                let radius: CGFloat = [4.5, 3.5, 4, 3][index]
                ctx.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(dotColors[index]))
            }
        }
        .frame(width: 44, height: 28)
    }
}

#Preview {
    KnowledgeMapView()
        .modelContainer(PreviewData.container)
}
