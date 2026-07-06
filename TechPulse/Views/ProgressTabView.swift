import SwiftUI
import SwiftData

/// M1: live stat tiles from SwiftData. Swift Charts (growth timeline,
/// reading streak) arrive in Milestone 5.
struct ProgressTabView: View {
    @Query private var concepts: [Concept]
    @Query private var articles: [Article]

    private var masteredCount: Int {
        concepts.filter { $0.masteryState == .known }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                HStack(spacing: 10) {
                    statTile("\(concepts.count)", "concepts on map", Theme.textPrimary)
                    statTile("\(masteredCount)", "mastered", Theme.stateKnown)
                    statTile("\(readingStreakDays)d", "reading streak", Theme.stateLearning)
                }
                .padding(.horizontal, 16)

                Spacer()
                Text("Growth timeline and streak charts arrive in Milestone 5.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Consecutive days (ending today) with at least one article read.
    private var readingStreakDays: Int {
        let calendar = Calendar.current
        let readDays = Set(articles.compactMap(\.readAt)
            .map { calendar.startOfDay(for: $0) })
        var streak = 0
        var day = calendar.startOfDay(for: .now)
        while readDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private func statTile(_ value: String, _ label: String, _ valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

#Preview {
    ProgressTabView()
        .modelContainer(PreviewData.container)
}
