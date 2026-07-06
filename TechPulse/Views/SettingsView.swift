import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: \FeedSource.name) private var sources: [FeedSource]

    private var grouped: [(category: String, sources: [FeedSource])] {
        Dictionary(grouping: sources, by: \.category)
            .sorted { $0.key < $1.key }
            .map { (category: $0.key, sources: $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.sources) { source in
                            Toggle(isOn: Bindable(source).isEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                        .font(.system(size: 15, weight: .medium))
                                    Text(source.url.host() ?? source.url.absoluteString)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .tint(Theme.stateKnown)
                        }
                    }
                }
                Section {
                    LabeledContent("Version", value: "0.1 (M1)")
                    LabeledContent("Intelligence", value: "On-device only")
                } header: {
                    Text("About")
                } footer: {
                    Text("All analysis happens on-device. No analytics; nothing leaves your iPhone.")
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
