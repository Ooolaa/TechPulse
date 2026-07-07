import SwiftUI
import SwiftData
import Charts

/// Progress (mockup 1e): stat tiles, cumulative concept growth,
/// reading bars, weekly quiz banner (quiz itself ships in M6).
struct ProgressTabView: View {
    @Query private var concepts: [Concept]
    @Query private var articles: [Article]
    @Environment(\.modelContext) private var modelContext
    @State private var quizRequest: QuizRequest?

    struct QuizRequest: Identifiable {
        let id = UUID()
        let concepts: [Concept]
    }

    private var masteredCount: Int {
        concepts.filter { $0.masteryState == .known }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    HStack {
                        Text("Progress")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)

                    HStack(spacing: 10) {
                        statTile("\(concepts.count)", "concepts on map", Theme.textPrimary)
                        statTile("\(masteredCount)", "mastered", Theme.stateKnown)
                        statTile("\(readingStreakDays)d", "reading streak", Theme.stateLearning)
                    }

                    learningPathCard
                    sideQuestCard
                    growthCard
                    readingCard
                    quizBanner
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $quizRequest) { request in
                QuizView(concepts: request.concepts)
            }
        }
    }

    // MARK: Stats

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

    // MARK: AI engineer path (design 4d)

    private var learningPathCard: some View {
        let stages = KnowledgePathEngine.stageProgress(concepts: concepts)
        let currentIndex = stages.firstIndex { !$0.isComplete } ?? stages.count - 1
        return VStack(alignment: .leading, spacing: 2) {
            Text("AI engineer path")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Dependency-ordered · from the knowledge pack")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(stages.indices, id: \.self) { index in
                    stageRow(stages[index], number: index + 1,
                             isCurrent: index == currentIndex,
                             isLast: index == stages.count - 1)
                }
            }
            .padding(.top, 14)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .techPulseCard()
        .accessibilityIdentifier("learningPath")
    }

    private func stageRow(_ stage: KnowledgePathEngine.StageProgress, number: Int,
                          isCurrent: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    if stage.isComplete {
                        Circle().fill(Theme.stateKnown)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    } else {
                        Circle().fill(isCurrent ? Theme.card : Theme.newTint)
                            .overlay(Circle().strokeBorder(
                                isCurrent ? Theme.stateLearning : Theme.cardBorder,
                                lineWidth: isCurrent ? 2.5 : 1.5))
                        Text("\(number)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(isCurrent ? Theme.stateLearning : Theme.textTertiary)
                    }
                }
                .frame(width: 26, height: 26)
                if !isLast {
                    Rectangle()
                        .fill(stage.isComplete ? Theme.stateKnown : Theme.cardBorder)
                        .frame(width: 2.5)
                        .frame(minHeight: 18)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(stage.isComplete ? Theme.textPrimary
                                     : (isCurrent ? Theme.stateLearning : Theme.textSecondary))
                Text(isCurrent ? "You are here — \(stage.subtitle)" : stage.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                if isCurrent {
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: 0xEDF0F3)).frame(width: 110, height: 6)
                            Capsule().fill(Theme.stateLearning)
                                .frame(width: max(5, 110 * Double(stage.lit) / Double(max(1, stage.total))),
                                       height: 6)
                        }
                        Text("\(stage.lit) of \(stage.total) dots")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.stateLearning)
                    }
                    .padding(.top, 5)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }

    private var sideQuestCard: some View {
        let progress = KnowledgePathEngine.sideQuestProgress(concepts: concepts)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Side quest: On-Device AI")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(progress.lit) of \(progress.total) lit · your specialty lane runs in parallel")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
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

    // MARK: Concepts learned (cumulative)

    private struct GrowthPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let count: Int
    }

    private var growthData: [GrowthPoint] {
        let dates = concepts.map(\.firstSeen).sorted()
        return dates.enumerated().map { GrowthPoint(date: $0.element, count: $0.offset + 1) }
    }

    private var growthCard: some View {
        chartCard(title: "Concepts learned", caption: "cumulative") {
            Chart(growthData) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Concepts", point.count))
                    .foregroundStyle(Theme.learningTint)
                LineMark(x: .value("Date", point.date), y: .value("Concepts", point.count))
                    .foregroundStyle(Theme.stateLearning)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
            .chartYAxis { AxisMarks(position: .trailing) }
            .frame(height: 130)
        }
    }

    // MARK: Articles read (last 14 days)

    private struct DayCount: Identifiable {
        var id: Date { day }
        let day: Date
        let count: Int
    }

    private var readingData: [DayCount] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let counts = Dictionary(grouping: articles.compactMap(\.readAt),
                                by: { calendar.startOfDay(for: $0) })
        return (0..<14).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return DayCount(day: day, count: counts[day]?.count ?? 0)
        }
    }

    private var readingCard: some View {
        chartCard(title: "Articles read", caption: "last 14 days") {
            Chart(readingData) { point in
                BarMark(x: .value("Day", point.day, unit: .day),
                        y: .value("Read", point.count))
                    .foregroundStyle(Theme.stateLearning)
                    .cornerRadius(4)
            }
            .chartYAxis { AxisMarks(position: .trailing) }
            .frame(height: 90)
        }
    }

    private func chartCard(title: String, caption: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .techPulseCard()
    }

    private var quizBanner: some View {
        let candidates = QuizEngine.quizCandidates(context: modelContext)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly quiz \(candidates.isEmpty ? "" : "ready")")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(candidates.isEmpty
                     ? "Read a few articles first — questions come from your reading"
                     : "\(candidates.count) concepts from your reading · generated on-device")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                quizRequest = QuizRequest(concepts: candidates)
            } label: {
                Text("Start")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(candidates.isEmpty ? Theme.stateNew : Theme.stateLearning, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(candidates.isEmpty)
            .accessibilityIdentifier("startQuiz")
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

#Preview {
    ProgressTabView()
        .modelContainer(PreviewData.container)
}
