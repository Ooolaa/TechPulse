import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: \FeedSource.name) private var sources: [FeedSource]
    @Environment(\.modelContext) private var modelContext
    @State private var isSyncing = false
    @AppStorage("articleTextSize") private var textSize = "Medium"
    @AppStorage("dailyReadingGoal") private var dailyGoal = 3

    private var lastSynced: Date? {
        sources.compactMap(\.lastFetched).max()
    }

    /// SwiftData store size on disk (design 2f "Storage used").
    private var storageUsed: String {
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        let size = (try? FileManager.default.attributesOfItem(atPath: storeURL.path)[.size] as? Int64) ?? 0
        return ByteCountFormatter.string(fromByteCount: size ?? 0, countStyle: .file)
    }

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
                Section("Sync & Storage") {
                    Button {
                        Task {
                            isSyncing = true
                            await FeedSyncService.syncAll(context: modelContext)
                            await IntelligenceService.analyzePending(context: modelContext)
                            isSyncing = false
                        }
                    } label: {
                        LabeledContent {
                            Text(isSyncing ? "Syncing…"
                                 : lastSynced?.formatted(.relative(presentation: .named)) ?? "never")
                        } label: {
                            Text("Sync now")
                                .foregroundStyle(Theme.stateLearning)
                        }
                    }
                    .disabled(isSyncing)
                    LabeledContent("Storage used", value: storageUsed)
                }
                Section {
                    Picker("Text size", selection: $textSize) {
                        Text("Small").tag("Small")
                        Text("Medium").tag("Medium")
                        Text("Large").tag("Large")
                    }
                    Picker("Daily reading goal", selection: $dailyGoal) {
                        Text("1 article").tag(1)
                        Text("3 articles").tag(3)
                        Text("5 articles").tag(5)
                        Text("10 articles").tag(10)
                    }
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Start tiny — a goal you hit daily beats one you abandon. The feed caps at 30 fresh articles a day so it never becomes a chore.")
                }
                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Intelligence", value: IntelligenceService.isModelAvailable
                                   ? "Apple Intelligence" : "On-device fallback")
                } header: {
                    Text("About")
                } footer: {
                    Text("All analysis happens on-device. No analytics; nothing leaves your iPhone. Read articles older than 60 days are pruned automatically.")
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
