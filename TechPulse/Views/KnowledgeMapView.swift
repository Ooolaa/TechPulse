import SwiftUI
import SwiftData

/// Milestone 5 delivers the force-directed graph (TimelineView + Canvas).
/// M1 shows the live concept/link counts over the same layout skeleton.
struct KnowledgeMapView: View {
    @Query private var concepts: [Concept]
    @Query private var links: [ConceptLink]

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
                    legend
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
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
