import SwiftUI
import SwiftData

/// First-run onboarding (design 3a): pick ≥3 topics and toggle suggested
/// sources. Topics are stored for feed personalization; source toggles bind
/// directly to the seeded FeedSources.
struct OnboardingView: View {
    @Query(sort: \FeedSource.name) private var sources: [FeedSource]
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("selectedTopics") private var selectedTopicsData = "LLMs,Agents,On-device AI"

    static let allTopics = ["LLMs", "Agents", "Vision", "Interpretability", "Robotics",
                            "Chips & hardware", "Open source", "Policy & safety",
                            "Dev tools", "On-device AI"]

    private var selectedTopics: Set<String> {
        Set(selectedTopicsData.split(separator: ",").map(String.init))
    }

    private func toggleTopic(_ topic: String) {
        var topics = selectedTopics
        if topics.contains(topic) { topics.remove(topic) } else { topics.insert(topic) }
        selectedTopicsData = topics.sorted().joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Capsule().fill(Theme.stateLearning).frame(height: 4)
                Capsule().fill(Theme.stateLearning).frame(height: 4)
                Capsule().fill(Theme.cardBorder).frame(height: 4)
            }
            .padding(.top, 14)

            Text("What do you want to keep up with?")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
                .padding(.top, 22)
            Text("Articles sync while you're online and read fully offline. Pick at least 3 topics.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FlowLayout(spacing: 9) {
                        ForEach(Self.allTopics, id: \.self) { topic in
                            topicChip(topic)
                        }
                    }
                    .padding(.top, 18)

                    Text("Suggested sources")
                        .font(.system(size: 12, weight: .bold))
                        .kerning(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 26)

                    VStack(spacing: 0) {
                        ForEach(Array(sources.prefix(5).enumerated()), id: \.element.name) { index, source in
                            if index > 0 { Divider().padding(.leading, 15) }
                            Toggle(isOn: Bindable(source).isEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(source.category)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .tint(Theme.stateKnown)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder, lineWidth: 1))
                    .padding(.top, 10)
                }
            }

            Button {
                hasOnboarded = true
            } label: {
                Text("Continue · \(selectedTopics.count) topic\(selectedTopics.count == 1 ? "" : "s")")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(selectedTopics.count >= 3 ? Theme.stateLearning : Theme.stateNew,
                                in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(selectedTopics.count < 3)
            .accessibilityIdentifier("onboardingContinue")
            .padding(.top, 14)

            Text("Everything is analyzed on your device — nothing leaves it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .background(Theme.background)
    }

    private func topicChip(_ topic: String) -> some View {
        let isSelected = selectedTopics.contains(topic)
        return Button { toggleTopic(topic) } label: {
            Text(isSelected ? "✓ \(topic)" : topic)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color(hex: 0x4B5563))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(isSelected ? Color(hex: 0x17181A) : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .modelContainer(PreviewData.container)
}
