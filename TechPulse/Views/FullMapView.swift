import SwiftUI
import SwiftData

struct FullMapRoute: Hashable {}

/// The whole net in one view: every concept connected across all clusters —
/// co-occurrence links plus dependency edges, no topic walls.
struct FullMapView: View {
    @Query(sort: \Concept.masteryLevel, order: .reverse) private var concepts: [Concept]
    @Query private var links: [ConceptLink]
    @Query private var dependencies: [ConceptDependency]
    @State private var selectedConcept: Concept?
    @State private var graphReset = UUID()

    private var frontierNames: Set<String> {
        KnowledgePathEngine.frontier(concepts: concepts, dependencies: dependencies)
    }

    /// Dots that arrived in the last 24 h — reading visibly grows the net.
    private var recentNames: Set<String> {
        let cutoff = Date.now.addingTimeInterval(-86_400)
        return Set(concepts.filter { $0.firstSeen > cutoff }.map(\.name))
    }

    private var litCount: Int {
        concepts.filter(KnowledgePathEngine.isLit).count
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.cardBorder, lineWidth: 1))
            ForceGraphView(concepts: concepts, links: links,
                           frontier: frontierNames,
                           recent: recentNames,
                           clusterAnchored: true) { name in
                selectedConcept = concepts.first { $0.name == name }
            }
            .id(graphReset)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            legend
            recenterButton
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Full map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(litCount) of \(concepts.count) lit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .sheet(item: $selectedConcept) { concept in
            ConceptSheetView(concept: concept)
        }
    }

    private var legend: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                legendDot(Theme.stateNew, "New")
                legendDot(Theme.stateLearning, "Learning")
                legendDot(Theme.stateKnown, "Known")
                Spacer()
                Text("pinch to zoom")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .padding(12)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var recenterButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button { graphReset = UUID() } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x4B5563))
                        .frame(width: 42, height: 42)
                        .background(Theme.card.opacity(0.94), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
                        .shadow(color: Color(hex: 0x17181A).opacity(0.1), radius: 7, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
                .padding(.bottom, 64)
            }
        }
    }
}
