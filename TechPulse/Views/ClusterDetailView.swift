import SwiftUI
import SwiftData

/// Cluster detail (design 4b): the cluster's dependency graph with dashed
/// "ready to learn" frontier rings and a NEXT ON THE FRONTIER card.
struct ClusterDetailView: View {
    let clusterName: String
    @Query private var concepts: [Concept]
    @Query private var dependencies: [ConceptDependency]
    @State private var selectedConcept: Concept?
    @State private var graphReset = UUID()

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

    /// New-since-you-started dots only (initial seeding batch excluded).
    private var recentNames: Set<String> {
        guard let epoch = concepts.map(\.firstSeen).min() else { return [] }
        let cutoff = Date.now.addingTimeInterval(-86_400)
        return Set(clusterConcepts
            .filter { $0.firstSeen > cutoff && $0.firstSeen > epoch.addingTimeInterval(3_600) }
            .map(\.name))
    }

    private var nextConcept: Concept? {
        let pathOrder = ActivePack.inUse.pathOrder(dependencies: dependencies)
        let localFrontier = frontierNames.intersection(clusterConcepts.map(\.name))
        guard !localFrontier.isEmpty else { return nil }
        // ADR-0004: reading order, never alphabetical. pathOrder covers every
        // Pack Concept, and the Frontier holds only those, so a miss means the
        // Concept is not part of the active Pack — not a reason to guess.
        guard let name = pathOrder.first(where: localFrontier.contains) else { return nil }
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
                               frontier: frontierNames,
                               recent: recentNames) { name in
                    selectedConcept = clusterConcepts.first { $0.name == name }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .id(graphReset)
                legend
                recenterButton
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
                Text("pinch to zoom")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Theme.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
            .padding(12)
            Spacer()
        }
    }

    /// Resets zoom/pan by recreating the graph (same trick as the full map).
    private var recenterButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { graphReset = UUID() } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textLabel)
                        .frame(width: 40, height: 40)
                        .background(Theme.card.opacity(0.94), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
                        .shadow(color: Theme.shadow.opacity(0.1), radius: 7, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recenter")
                .padding(.trailing, 22)
                .padding(.top, 54)
            }
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
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.learningBorder, lineWidth: 1))
                .shadow(color: Theme.shadow.opacity(0.1), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("frontierCard")
            .padding(12)
        }
    }
}
