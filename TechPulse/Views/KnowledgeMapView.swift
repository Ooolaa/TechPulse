import SwiftUI
import SwiftData

/// Milestone 5 delivers the force-directed graph (TimelineView + Canvas).
/// M1 shows the live concept/link counts over the same layout skeleton.
struct KnowledgeMapView: View {
    @Query(sort: \Concept.masteryLevel, order: .reverse) private var concepts: [Concept]
    @Query private var links: [ConceptLink]
    @State private var selectedConcept: Concept?
    @State private var selectedCluster: String?
    @State private var graphReset = UUID()

    private var clusters: [String] {
        Array(Set(concepts.map(\.category))).sorted()
    }

    private var visibleConcepts: [Concept] {
        guard let selectedCluster else { return concepts }
        return concepts.filter { $0.category == selectedCluster }
    }

    private var visibleLinks: [ConceptLink] {
        guard selectedCluster != nil else { return links }
        let names = Set(visibleConcepts.map(\.name))
        return links.filter { names.contains($0.conceptA) && names.contains($0.conceptB) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    Text("Knowledge")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(concepts.count) concepts · \(links.count) links")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.cardBorder, lineWidth: 1))
                    if concepts.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.stateNew)
                            Text("Your map starts as a few lonely dots")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Concepts appear here as you read.\nForce-directed graph lands in Milestone 5.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        ForceGraphView(concepts: visibleConcepts, links: visibleLinks) { name in
                            selectedConcept = concepts.first { $0.name == name }
                        }
                        .id(graphReset)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        clusterChips
                        recenterButton
                    }
                    legend
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .sheet(item: $selectedConcept) { concept in
                    ConceptSheetView(concept: concept)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Cluster filter pills (design 2c).
    private var clusterChips: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    clusterChip("All clusters", isSelected: selectedCluster == nil) {
                        selectedCluster = nil
                    }
                    ForEach(clusters, id: \.self) { cluster in
                        clusterChip(cluster, isSelected: selectedCluster == cluster) {
                            selectedCluster = cluster
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            Spacer()
        }
    }

    private func clusterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color(hex: 0x17181A).opacity(0.9) : Theme.card.opacity(0.85),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Recenter control (design 2c): resets pan/zoom and re-runs the layout.
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
            .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
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
}

#Preview {
    KnowledgeMapView()
        .modelContainer(PreviewData.container)
}
