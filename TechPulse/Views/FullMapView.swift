import SwiftUI
import SwiftData

struct FullMapRoute: Hashable {}

/// The whole net in one view: every concept connected across all clusters —
/// co-occurrence links plus dependency edges, no topic walls.
struct FullMapView: View {
    @Query(sort: \Concept.masteryLevel, order: .reverse) private var concepts: [Concept]
    @Query private var links: [ConceptLink]
    @Query private var semanticLinks: [SemanticLink]
    @Query private var dependencies: [ConceptDependency]
    @State private var selectedConcept: Concept?   // drives the glossary strip
    @State private var detailConcept: Concept?     // drives the full sheet
    @State private var graphReset = UUID()

    private var frontierNames: Set<String> {
        KnowledgePathEngine.frontier(concepts: concepts, dependencies: dependencies)
    }

    /// Dots that arrived in the last 24 h — reading visibly grows the net.
    /// The initial seeding batch is excluded (on a fresh install everything
    /// is "new", and 73 pulsing rings mean nothing).
    private var recentNames: Set<String> {
        guard let epoch = concepts.map(\.firstSeen).min() else { return [] }
        let cutoff = Date.now.addingTimeInterval(-86_400)
        return Set(concepts
            .filter { $0.firstSeen > cutoff && $0.firstSeen > epoch.addingTimeInterval(3_600) }
            .map(\.name))
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
                           semanticLinks: semanticLinks,
                           dependencies: dependencies,
                           frontier: frontierNames,
                           recent: recentNames,
                           clusterAnchored: true) { name in
                selectedConcept = concepts.first { $0.name == name }
            }
            .id(graphReset)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            if let selectedConcept {
                glossaryStrip(selectedConcept)
            } else {
                legend
            }
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
        .sheet(item: $detailConcept) { concept in
            ConceptSheetView(concept: concept)
        }
    }

    /// Tap a dot → brief review of what the keyword means, right under the map.
    private func glossaryStrip(_ concept: Concept) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(stripColor(concept)).frame(width: 9, height: 9)
                    Text(concept.name)
                        .font(.system(size: 14.5, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    ConceptChip(concept: concept, detailed: true)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selectedConcept = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 26, height: 26)
                            .background(Theme.newTint, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Text(concept.conceptDefinition.isEmpty
                     ? "No definition yet — reading tagged articles fills this in."
                     : concept.conceptDefinition)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(2)
                Button { detailConcept = concept } label: {
                    Text("Details ›")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Theme.stateLearning)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("glossaryDetails")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.learningBorder, lineWidth: 1))
            .shadow(color: Theme.shadow.opacity(0.08), radius: 10, y: 5)
            .padding(12)
        }
        .accessibilityIdentifier("glossaryStrip")
    }

    private func stripColor(_ concept: Concept) -> Color {
        switch concept.masteryState {
        case .new: Theme.stateNew
        case .learning: Theme.stateLearning
        case .known: Theme.stateKnown
        }
    }

    private var legend: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    legendDot(Theme.stateNew, "New")
                    legendDot(Theme.stateLearning, "Learning")
                    legendDot(Theme.stateKnown, "Known")
                    Spacer()
                    Text("pinch to zoom")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                // Three kinds of connection (ADR-0002), keyed so the map can
                // actually be read rather than merely looked at.
                HStack(spacing: 12) {
                    legendEdge(.dependency, "Learn first")
                    legendEdge(.semantic, "Related")
                    legendEdge(.coread, "Read together")
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .padding(12)
        }
        .accessibilityIdentifier("mapLegend")
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// A sample of the real line, drawn from the same colour the map uses —
    /// the key and the map cannot drift apart.
    private func legendEdge(_ kind: GraphSimulation.Edge.Kind, _ label: String) -> some View {
        let color = ForceGraphView.edgeColor(kind)
        return HStack(spacing: 5) {
            HStack(spacing: kind == .semantic ? 2 : 0) {
                if kind == .semantic {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(color).frame(width: 4, height: 2)
                    }
                } else {
                    Capsule().fill(color).frame(width: 16, height: 2)
                }
                if kind == .dependency {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Theme.graphArrow)
                }
            }
            .frame(width: 22, alignment: .leading)
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
                        .foregroundStyle(Theme.textLabel)
                        .frame(width: 42, height: 42)
                        .background(Theme.card.opacity(0.94), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
                        .shadow(color: Theme.shadow.opacity(0.1), radius: 7, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
                .padding(.bottom, 64)
            }
        }
    }
}
