import SwiftUI
import SwiftData

/// Cluster detail (design 4b): the cluster's dependency graph with dashed
/// "ready to learn" frontier rings and a NEXT ON THE FRONTIER card.
struct ClusterDetailView: View {
    let clusterName: String
    @Query private var concepts: [Concept]
    @Query private var dependencies: [ConceptDependency]
    @State private var selectedConcept: Concept?

    private var clusterConcepts: [Concept] {
        concepts.filter { $0.category == clusterName }
    }

    private var clusterDependencies: [ConceptDependency] {
        let names = Set(clusterConcepts.map(\.name))
        return dependencies.filter { names.contains($0.prerequisite) && names.contains($0.dependent) }
    }

    /// Frontier is computed over ALL concepts (cross-cluster prerequisites
    /// count), then shown for this cluster's dots.
    private var frontierNames: Set<String> {
        KnowledgePathEngine.frontier(concepts: concepts, dependencies: dependencies)
    }

    private var litCount: Int {
        clusterConcepts.filter(KnowledgePathEngine.isLit).count
    }

    private var nextConcept: Concept? {
        let pathOrder = KnowledgePack.stages.flatMap(\.conceptNames) + KnowledgePack.sideQuestConcepts
        let localFrontier = frontierNames.intersection(clusterConcepts.map(\.name))
        guard !localFrontier.isEmpty else { return nil }
        let name = pathOrder.first(where: localFrontier.contains) ?? localFrontier.sorted()[0]
        return clusterConcepts.first { $0.name == name }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.cardBorder, lineWidth: 1))
                ForceGraphView(concepts: clusterConcepts, links: [],
                               dependencies: clusterDependencies,
                               frontier: frontierNames) { name in
                    selectedConcept = clusterConcepts.first { $0.name == name }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                legend
                if let nextConcept {
                    frontierCard(nextConcept)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(clusterName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(litCount) / \(clusterConcepts.count)")
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
            HStack(spacing: 12) {
                legendDot(label: "Known") { Circle().fill(Theme.stateKnown) }
                legendDot(label: "Learning") { Circle().fill(Theme.stateLearning) }
                legendDot(label: "Ready to learn") {
                    Circle().strokeBorder(Theme.stateLearning,
                                          style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                }
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Theme.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
            .padding(12)
            Spacer()
        }
    }

    private func legendDot(label: String, @ViewBuilder _ dot: () -> some View) -> some View {
        HStack(spacing: 5) {
            dot().frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func frontierCard(_ concept: Concept) -> some View {
        let litPrereqs = dependencies.filter { $0.dependent == concept.name }
            .map(\.prerequisite)
            .filter { name in concepts.first { $0.name == name }.map(KnowledgePathEngine.isLit) ?? false }
        return VStack {
            Spacer()
            Button { selectedConcept = concept } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next on the frontier")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(Theme.stateLearning)
                            .textCase(.uppercase)
                        Text(concept.name)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text(litPrereqs.isEmpty
                             ? "No prerequisites — start anytime"
                             : "Prerequisites lit — \(litPrereqs.map { "\($0) ✓" }.joined(separator: ", "))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(concept.articles.count) article\(concept.articles.count == 1 ? "" : "s")")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.stateLearning, in: Capsule())
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(Theme.card.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: 0xDCE7F8), lineWidth: 1))
                .shadow(color: Color(hex: 0x17181A).opacity(0.1), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("frontierCard")
            .padding(12)
        }
    }
}
