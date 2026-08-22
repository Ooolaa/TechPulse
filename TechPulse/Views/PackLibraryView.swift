import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Choosing what the map covers: which Pack is active, the Packs that ship in
/// the app, and a Pack file the reader was given.
///
/// Installing is the only thing this screen does to the store, and it does it
/// through `PackInstaller`, so a Pack that fails validation is rejected with
/// the validator's own words and changes nothing.
struct PackLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<InstalledPack> { $0.isActive }) private var activeRecords: [InstalledPack]

    @State private var isImporting = false
    /// The validator's reason, shown verbatim — the reader has to be able to
    /// go and fix the file.
    @State private var rejection: String?
    /// Set after a Pack installs, when it suggests Sources the reader has not
    /// got. A Source is chosen, so this is an offer, never a subscription.
    @State private var offer: SourceOffer?

    private var active: InstalledPack? { activeRecords.first }

    var body: some View {
        List {
            activeSection
            builtinSection
            importSection
        }
        .navigationTitle("Pack")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        // Any file may be picked, not only ones the system calls JSON: a Pack
        // the reader was handed may carry any extension, and being told why it
        // is not a Pack beats finding it greyed out with nothing to read.
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url): importPack(at: url)
            case .failure(let error): rejection = error.localizedDescription
            }
        }
        .alert("This Pack was not installed",
               isPresented: Binding(get: { rejection != nil },
                                    set: { if !$0 { rejection = nil } }),
               presenting: rejection) { _ in
            Button("OK", role: .cancel) {}
        } message: { reason in
            Text(reason)
        }
        .sheet(item: $offer) { offer in
            PackSourceOfferView(offer: offer)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var activeSection: some View {
        Section {
            if let active {
                VStack(alignment: .leading, spacing: 4) {
                    Text(active.field)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(summary(concepts: active.conceptNames.count,
                                 clusters: active.clusterOrder.count,
                                 origin: active.packOrigin))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("activePack")
            } else {
                Text("No Pack installed")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            SettingsHeader("Active Pack")
        } footer: {
            Text("A Pack is the field your map covers. Switching to another keeps everything you have learned — Concepts in both Packs keep their mastery and history.")
        }
    }

    private var builtinSection: some View {
        Section {
            ForEach(BuiltinPacks.all, id: \.fileName) { builtin in
                Button {
                    install(builtin)
                } label: {
                    packRow(field: builtin.pack.field,
                            detail: summary(concepts: builtin.pack.concepts.count,
                                            clusters: builtin.pack.clusterOrder.count,
                                            origin: nil),
                            isActive: isActive(builtin))
                }
                .accessibilityIdentifier("builtinPack")
            }
        } header: {
            SettingsHeader("Built-in Packs")
        }
    }

    private var importSection: some View {
        Section {
            Button { isImporting = true } label: {
                Text("Import a Pack file…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.stateLearning)
            }
            .accessibilityIdentifier("importPack")
        } header: {
            SettingsHeader("From a file")
        } footer: {
            Text("A Pack file is JSON someone authored or exported. It is checked before anything is installed; if it does not pass, nothing about your map changes.")
        }
    }

    private func packRow(field: String, detail: String, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(field)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.stateKnown)
                    .accessibilityLabel("Active")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Installing

    /// Which row carries the tick. An imported Pack covering the same field is
    /// not this row's Pack however it is named, and a built-in stays this row's
    /// Pack however its field is renamed — both are `BuiltinPacks.matching`.
    private func isActive(_ builtin: BuiltinPacks.Builtin) -> Bool {
        active.flatMap(BuiltinPacks.matching)?.fileName == builtin.fileName
    }

    private func summary(concepts: Int, clusters: Int, origin: PackOrigin?) -> String {
        let parts = ["\(concepts) concepts", "\(clusters) clusters"]
            + (origin.map { [$0.label] } ?? [])
        return parts.joined(separator: " · ")
    }

    /// A built-in goes in through `PackMigration`, never straight to
    /// `PackInstaller`: that is what records the Pack file's version, and a
    /// version left unrecorded has the next launch reinstall the Pack the
    /// reader just chose (#19).
    private func install(_ builtin: BuiltinPacks.Builtin) {
        installing(builtin.pack) {
            try PackMigration.installBuiltin(builtin, context: modelContext)
        }
    }

    private func install(imported pack: PackFile) {
        installing(pack) {
            try PackInstaller.install(pack, origin: .imported, context: modelContext)
        }
    }

    /// What both of those do around the install itself: refresh what the reader
    /// sees, or say why nothing changed. The Pack is here for what it suggests,
    /// not to be installed — `perform` is what installs it.
    private func installing(_ pack: PackFile, _ perform: () throws -> Void) {
        do {
            try perform()
            // The map changed, so what the widget says about it is stale.
            WidgetRefresh.refresh(context: modelContext)
            let pending = PackSourceOffer.pending(pack.suggestedSources, context: modelContext)
            if !pending.isEmpty {
                offer = SourceOffer(field: pack.field, sources: pending)
            }
        } catch {
            // The validator's own words where there are any; a store failure
            // has none worth showing, and the map is unchanged either way.
            rejection = (error as? PackValidationError)?.localizedDescription
                ?? "The Pack could not be installed, so nothing about your map changed."
        }
    }

    private func importPack(at url: URL) {
        // A file picked outside the app's container is only readable inside
        // this pair of calls.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let pack = try PackValidator.decodeAndValidate(try Data(contentsOf: url))
            install(imported: pack)
        } catch let error as PackValidationError {
            rejection = error.localizedDescription
        } catch {
            rejection = PackValidationError.unreadable("the file could not be opened")
                .localizedDescription
        }
    }
}

// MARK: - Offering the Pack's suggested Sources

/// A Pack's suggestions, waiting on the reader's answer.
struct SourceOffer: Identifiable {
    let field: String
    let sources: [PackFile.PackSource]
    var id: String { field }
}

/// The offer itself: every suggestion listed, none of them subscribed to until
/// the reader says so.
struct PackSourceOfferView: View {
    let offer: SourceOffer

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var accepted: Set<String>

    init(offer: SourceOffer) {
        self.offer = offer
        // Pre-checked: these are the author's suggestions for the map the
        // reader just chose, and having nothing to read is a worse first
        // impression than one Source too many.
        _accepted = State(initialValue: Set(offer.sources.map(\.url)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(offer.sources, id: \.url) { source in
                        Button {
                            if accepted.contains(source.url) {
                                accepted.remove(source.url)
                            } else {
                                accepted.insert(source.url)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(source.category)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Image(systemName: accepted.contains(source.url)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19))
                                    .foregroundStyle(accepted.contains(source.url)
                                                     ? Theme.stateKnown : Theme.stateNew)
                            }
                        }
                        .accessibilityIdentifier("offeredSource")
                    }
                } header: {
                    SettingsHeader("Suggested by \(offer.field)")
                } footer: {
                    Text("Nothing is subscribed until you say so, and you can turn any Source off later in Settings.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Something to read")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        // Answered, not postponed: Settings would otherwise
                        // raise the same suggestions at every launch. Choosing
                        // this Pack from the library asks again — see
                        // `PackSourceOffer.recordDeclined`.
                        PackSourceOffer.recordDeclined(offer.sources)
                        dismiss()
                    }
                    .accessibilityIdentifier("declineSources")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(accepted.count)") {
                        // The ones left unchecked were put to the reader and
                        // turned down as surely as "Not now" turns down all of
                        // them, so the standing offer stops raising those too.
                        PackSourceOffer.recordDeclined(
                            offer.sources.filter { !accepted.contains($0.url) })
                        let added = PackSourceOffer.subscribe(
                            offer.sources.filter { accepted.contains($0.url) },
                            context: modelContext)
                        dismiss()
                        // Sources are only synced by themselves when the Feed
                        // is half an hour stale, and the point of taking these
                        // was having something to read now.
                        if added > 0 {
                            Task {
                                await FeedSyncService.syncAll(context: modelContext)
                                await IntelligenceService.analyzePending(context: modelContext)
                            }
                        }
                    }
                    .disabled(accepted.isEmpty)
                    .accessibilityIdentifier("acceptSources")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PackLibraryView()
    }
    .modelContainer(PreviewData.container)
}
