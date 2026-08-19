import WidgetKit
import SwiftUI

// MARK: Timeline

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// Two entries: now, and the moment the day rolls over — so the ring
    /// resets and the "streak at risk" cue appears at midnight even if the app
    /// hasn't run. `.after` schedules the next refresh at that same boundary.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1,
                                     to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)

        let timeline = Timeline(entries: [entry(at: now), entry(at: midnight)],
                                policy: .after(midnight))
        completion(timeline)
    }

    private func entry(at date: Date) -> StreakEntry {
        let stored = WidgetSnapshot.load() ?? .placeholder
        return StreakEntry(date: date, snapshot: stored.rolledForward(to: date))
    }
}

// MARK: Widget

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TechPulseStreak", provider: StreakProvider()) { entry in
            StreakWidgetView(snapshot: entry.snapshot)
                .containerBackground(Theme.background, for: .widget)
        }
        .configurationDisplayName("Streak & next dot")
        .description("Your reading streak, today's goal, and the concept you're ready to learn.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .systemSmall:       smallView
        case .systemMedium:      mediumView
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        default:                 inlineView
        }
    }

    // MARK: Home screen

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            GoalRing(snapshot: snapshot).frame(width: 46, height: 46)
            Spacer(minLength: 0)
            Text(headline)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(subhead)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "techpulse://feed"))
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                GoalRing(snapshot: snapshot).frame(width: 42, height: 42)
                Text(headline)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(subhead)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let next = snapshot.nextDotName {
                VStack(alignment: .leading, spacing: 4) {
                    Label("NEXT DOT", systemImage: "smallcircle.filled.circle")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Theme.stateLearning)
                    Text(next)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let cluster = snapshot.nextDotCluster {
                        Text(cluster)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text("\(snapshot.conceptsLit) of \(snapshot.conceptsTotal) lit")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: snapshot.nextDotName == nil ? "techpulse://feed" : "techpulse://knowledge"))
    }

    // MARK: Lock screen

    private var circularView: some View {
        // Tinted rendering mode flattens color, so the ring carries the meaning.
        Gauge(value: Double(min(snapshot.readToday, snapshot.dailyGoal)),
              in: 0...Double(max(1, snapshot.dailyGoal))) {
            Image(systemName: "book.fill")
        } currentValueLabel: {
            Text(snapshot.goalMet ? "✓" : "\(snapshot.readToday)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetURL(URL(string: "techpulse://feed"))
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headline)
                .font(.system(size: 13, weight: .heavy))
            if let next = snapshot.nextDotName {
                Text("Next: \(next)")
                    .font(.system(size: 12))
                    .lineLimit(1)
            } else {
                Text(subhead).font(.system(size: 12)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: snapshot.nextDotName == nil ? "techpulse://feed" : "techpulse://knowledge"))
    }

    private var inlineView: some View {
        Text(snapshot.isEmpty ? "Start your streak"
             : "\(snapshot.streakDays)d streak · \(snapshot.readToday)/\(snapshot.dailyGoal)")
    }

    // MARK: Copy
    //
    // Never a bare zero: before the first read the widget invites, and a live
    // Streak that today hasn't extended reads as a cue, not a failure.

    private var headline: String {
        if snapshot.isEmpty { return "Start today" }
        if snapshot.goalMet { return "Goal met 🎉" }
        return "\(snapshot.streakDays)-day streak"
    }

    private var subhead: String {
        if snapshot.isEmpty { return "Read one article to start your streak." }
        if snapshot.goalMet { return "Come back tomorrow — don't break the chain." }
        if snapshot.streakAtRisk { return "Read one article to keep it alive." }
        return "\(snapshot.dailyGoal - snapshot.readToday) to go. You've already shown up."
    }
}

// MARK: Ring

/// The daily-goal ring from the feed's goal card, sized for a widget.
private struct GoalRing: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let met = snapshot.goalMet
        let progress = min(1, Double(snapshot.readToday) / Double(max(1, snapshot.dailyGoal)))
        ZStack {
            Circle().stroke(met ? Theme.knownTint : Theme.learningTint, lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(met ? Theme.stateKnown : Theme.stateLearning,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if met {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.stateKnown)
            } else {
                Text("\(snapshot.readToday)/\(snapshot.dailyGoal)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.stateLearning)
            }
        }
    }
}
