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

    /// What this sheet is still asking about: every suggestion at first, and
    /// after a partial answer only the ones that were turned away.
    ///
    /// Narrowing it is not cosmetic. `PackSourceOffer.accept` reads its
    /// pre-ticked rule off the list it is handed and treats an unticked entry
    /// as a decline — so handing it the *original* list a second time would
    /// record everything already subscribed, and every Source the app itself
    /// turned away, as suggestions the reader refused. That is exactly what
    /// ADR-0011's rule forbids, arrived at by a second tap on Add.
    @State private var remaining: [PackFile.PackSource]

    /// Whether what is left in `remaining` is there because the app turned it
    /// away. One flag rather than a set: after a partial answer the list *is*
    /// the refusals, since everything else was taken and is gone from it.
    @State private var wasRefused = false

    /// Set while the ticked suggestions are being asked whether they are feeds.
    @State private var isChecking = false

    init(offer: SourceOffer) {
        self.offer = offer
        // Ticked or not by the same rule `PackSourceOffer.accept` reads when it
        // decides whether silence was an answer — one policy, not two.
        _accepted = State(initialValue: PackSourceOffer.preChecked(offer.sources))
        _remaining = State(initialValue: offer.sources)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(remaining, id: \.url) { source in
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
                                    if wasRefused {
                                        Text("Didn't answer as a feed — not added")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.danger)
                                            .accessibilityIdentifier("refusedSource")
                                    } else {
                                        Text(source.category)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: accepted.contains(source.url)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19))
                                    .foregroundStyle(wasRefused ? Theme.danger
                                                     : accepted.contains(source.url)
                                                       ? Theme.stateKnown : Theme.stateNew)
                            }
                        }
                        .accessibilityIdentifier("offeredSource")
                    }
                } header: {
                    SettingsHeader("Suggested by \(offer.field)")
                } footer: {
                    Text(wasRefused
                         ? "Each Source is asked whether it really is one before it is added, and these answered with something else. Nothing was recorded against them — try again, or install this Pack from the library whenever you want to be asked about them again."
                         : "Nothing is subscribed until you say so, and you can turn any Source off later in Settings.")
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
                        //
                        // `remaining`, so a reader who took some and then said
                        // "not now" to what was left declines what was left,
                        // rather than the Sources they just subscribed to.
                        PackSourceOffer.recordDeclined(remaining)
                        dismiss()
                    }
                    .accessibilityIdentifier("declineSources")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChecking ? "Checking…" : "Add \(accepted.count)") {
                        Task { await add() }
                    }
                    .disabled(accepted.isEmpty || isChecking)
                    .accessibilityIdentifier("acceptSources")
                }
            }
        }
    }

    /// Answers the offer, and keeps the sheet open only when there is something
    /// to say.
    ///
    /// Asking the hosts takes a moment, which is why the button says so. The
    /// alternative — subscribe instantly and let the reader discover the dud on
    /// its Settings row — is what #14 already does, and it leaves a Source in
    /// their list that never belonged there. A generated Pack's suggestions are
    /// model output (#27), which is the case that makes asking first worth the
    /// wait.
    private func add() async {
        isChecking = true
        let result = await PackSourceOffer.accept(accepted, of: remaining,
                                                  context: modelContext)
        isChecking = false

        // Sources are only synced by themselves when the Feed is half an hour
        // stale, and the point of taking these was having something to read now.
        if result.subscribed > 0 {
            Task {
                await FeedSyncService.syncAll(context: modelContext)
                await IntelligenceService.analyzePending(context: modelContext)
            }
        }
        guard !result.refused.isEmpty else {
            dismiss()
            return
        }
        // Something the reader asked for could not be used. Dismissing would
        // leave them to work out from a shorter Settings list which one it was.
        //
        // What is left is exactly the refusals, still ticked: the reader said
        // yes and nothing has happened to change that, so a second tap on Add
        // asks the same hosts again rather than reading their silence as a
        // decline.
        remaining = result.refused
        accepted = Set(result.refused.map(\.url))
        wasRefused = true
    }
}

#Preview {
    NavigationStack {
        PackLibraryView()
    }
    .modelContainer(PreviewData.container)
}
