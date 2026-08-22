import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: \FeedSource.name) private var sources: [FeedSource]
    @Query(filter: #Predicate<InstalledPack> { $0.isActive }) private var activePacks: [InstalledPack]
    @Environment(\.modelContext) private var modelContext
    @State private var isSyncing = false
    @AppStorage("articleTextSize") private var textSize = "Medium"
    @AppStorage("dailyReadingGoal") private var dailyGoal = 3
    @State private var keyInput = ""
    @State private var hasKey = KeychainStore.hasAnthropicKey
    @State private var intention = ReminderScheduler.intention
    @State private var notificationsRefused = false
    /// Set when the reader opens the standing offer. A Source is chosen, so
    /// this screen shows what is suggested and subscribes to none of it.
    @State private var offer: SourceOffer?

    private var lastSynced: Date? {
        sources.compactMap(\.lastFetched).max()
    }

    /// The Pack the map is of, named here so the reader can see it without
    /// opening the chooser.
    private var activePack: InstalledPack? { activePacks.first }

    /// The Active Pack's suggestions the reader has neither taken nor turned
    /// down. This is where a Source added to a Pack in a new version of the app
    /// arrives — launch subscribes to nothing after the first one, so without a
    /// row here it would reach nobody (#47).
    ///
    /// Read off the `@Query` above rather than fetched: this body redraws on
    /// every toggle in the list below it.
    private var suggested: [PackFile.PackSource] {
        PackSourceOffer.standing(ActivePack.inUse.suggestedSources,
                                 subscribedTo: Set(sources.map(\.url.absoluteString)))
    }

    /// SwiftData store size on disk (design 2f "Storage used").
    private var storageUsed: String {
        ByteCountFormatter.string(fromByteCount: StoreSize.onDisk(StoreSize.appStoreURL),
                                  countStyle: .file)
    }

    /// Re-arms the reminder from the current intention. Separate from storing
    /// it, because storing is a `UserDefaults` write and arming walks the store.
    private func rearmReminder() {
        ReminderScheduler.intention = intention
        WidgetRefresh.refresh(context: modelContext)
    }

    private var grouped: [(category: String, sources: [FeedSource])] {
        Dictionary(grouping: sources, by: \.category)
            .sorted { $0.key < $1.key }
            .map { (category: $0.key, sources: $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PackLibraryView()
                    } label: {
                        LabeledContent("Pack", value: activePack?.field ?? "None")
                    }
                    .accessibilityIdentifier("packRow")
                } header: {
                    SettingsHeader("Map")
                } footer: {
                    Text("The Pack is the field your map covers. Switch to another built-in Pack, or import one you were given — what you have learned comes with you.")
                }
                if !suggested.isEmpty {
                    Section {
                        Button {
                            offer = SourceOffer(field: activePack?.field ?? ActivePack.inUse.field,
                                                sources: suggested)
                        } label: {
                            LabeledContent {
                                Text("\(suggested.count)")
                            } label: {
                                Text(suggested.count == 1
                                     ? "1 new Source suggested"
                                     : "\(suggested.count) new Sources suggested")
                                    .foregroundStyle(Theme.stateLearning)
                            }
                        }
                        .accessibilityIdentifier("suggestedSourcesRow")
                    } header: {
                        SettingsHeader("Suggested")
                    } footer: {
                        Text("Your Pack suggests these and you are not subscribed to them. Nothing is subscribed until you say so.")
                    }
                }
                ForEach(grouped, id: \.category) { group in
                    Section {
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
                    } header: {
                        SettingsHeader(group.category)
                    }
                }
                Section {
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
                } header: {
                    SettingsHeader("Sync & Storage")
                }
                Section {
                    Toggle("Remind me to read", isOn: Binding(
                        get: { intention.isOn },
                        set: { isOn in
                            intention.isOn = isOn
                            ReminderScheduler.intention = intention
                            if isOn {
                                Task {
                                    // The system asks once. After a refusal
                                    // this returns false having shown nothing,
                                    // so the only honest thing is to say where
                                    // the switch actually lives.
                                    await ReminderScheduler.requestPermission()
                                    notificationsRefused = await ReminderScheduler.permissionRefused()
                                    WidgetRefresh.refresh(context: modelContext)
                                }
                            } else {
                                notificationsRefused = false
                                ReminderScheduler.cancel()
                            }
                        }
                    ))
                    .accessibilityIdentifier("reminderToggle")
                    if intention.isOn {
                        ReadingIntentionStep(intention: $intention, showsHeading: false)
                            // Stored on every edit, which is cheap; re-armed
                            // only when the *time* moves or the section is
                            // left, so typing a routine does not re-run a store
                            // fetch and a widget reload per keystroke.
                            .onChange(of: intention) { ReminderScheduler.intention = intention }
                            .onChange(of: intention.hour) { rearmReminder() }
                            .onChange(of: intention.minute) { rearmReminder() }
                            .onDisappear { rearmReminder() }
                        if notificationsRefused {
                            Link("Notifications are off for TechPulse — turn them on in Settings",
                                 destination: URL(string: UIApplication.openSettingsURLString)!)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.stateLearning)
                        }
                    }
                } header: {
                    SettingsHeader("Reading Intention")
                } footer: {
                    Text("The reminder is a local notification, scheduled on this device. It stays quiet on days you have already read.")
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
                    // The widget's ring is drawn against this goal.
                    .onChange(of: dailyGoal) { WidgetRefresh.refresh(context: modelContext) }
                } header: {
                    SettingsHeader("Reading")
                } footer: {
                    Text("Start tiny — a goal you hit daily beats one you abandon. The feed caps at 30 fresh articles a day so it never becomes a chore.")
                }
                Section {
                    LabeledContent("On-device model",
                                   value: IntelligenceService.isModelAvailable ? "Available" : "Not available")
                    if hasKey {
                        LabeledContent("Claude API key", value: "Connected ••••")
                        Button(role: .destructive) { KeychainStore.delete(); hasKey = false } label: {
                            Text("Remove key")
                        }
                    } else {
                        SecureField("Claude API key (sk-ant-…)", text: $keyInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button {
                            if KeychainStore.save(keyInput.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                hasKey = true; keyInput = ""
                            }
                        } label: { Text("Save key").foregroundStyle(Theme.stateLearning) }
                        .disabled(keyInput.isEmpty)
                    }
                } header: {
                    SettingsHeader("AI engine")
                } footer: {
                    Text("Optional: add your own Claude API key to unlock AI features on devices without Apple Intelligence. Stored only in your iPhone's Keychain; used directly with Anthropic, never sent through any server.")
                }
                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Intelligence", value: IntelligenceService.isModelAvailable
                                   ? "Apple Intelligence" : "On-device fallback")
                } header: {
                    SettingsHeader("About")
                } footer: {
                    Text("Analysis happens on-device. No analytics; nothing leaves your iPhone unless you add your own API key above. Read articles older than 60 days are pruned automatically.")
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .sheet(item: $offer) { offer in
                PackSourceOfferView(offer: offer)
            }
        }
    }
}

/// Legible section header — the default List header gray disappears against
/// the light background.
struct SettingsHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13.5, weight: .heavy))
            .kerning(0.5)
            .foregroundStyle(Theme.textPrimary)
            .textCase(.uppercase)
            .padding(.bottom, 2)
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
