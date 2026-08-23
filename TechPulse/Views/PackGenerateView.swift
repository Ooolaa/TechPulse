import SwiftUI
import SwiftData

/// Generating a Pack: name a field, watch it being built, look at what came
/// back, and install it — or don't.
///
/// The review step is not decoration. A Pack is data the app then navigates by,
/// and `PackGenerator.sanitize` can only mend what `PackValidator` would refuse
/// — it cannot tell a Concept that belongs in this field from one the model
/// invented. So the last check is the reader's, and it is made before anything
/// touches their map rather than afterwards on a map they have to unpick.
///
/// Installing is deliberately *not* done here. The draft goes back to
/// `PackLibraryView`, which is where every Pack this app installs goes in, so a
/// generated Pack gets the offer of its suggested Sources and the widget
/// refresh on exactly the same path as an imported one.
struct PackGenerateView: View {

    /// Handed the finished draft. The caller installs it.
    let onFinished: (PackDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Where the reader is. One value rather than four flags: "generating and
    /// failed" and "reviewing and still working" are states this screen must
    /// not be able to reach.
    private enum Phase {
        case asking
        case working(String)
        case reviewing(PackDraft)
        /// Something to read, always. A generation that ends in a blank screen
        /// is indistinguishable from one still running.
        case failed(String)
    }

    @State private var field = ""
    @State private var phase: Phase = .asking
    /// The Concept a rename is open on, and what it would become.
    @State private var renaming: String?
    @State private var renamed = ""

    private let tier = PackGenerator.tier

    var body: some View {
        NavigationStack {
            List {
                switch phase {
                case .asking: askingSection
                case .working(let message): workingSection(message)
                case .reviewing(let draft): reviewSections(draft)
                case .failed(let reason): failureSection(reason)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Generate a Pack")
            .navigationBarTitleDisplayMode(.inline)
            // Cancel is refused while a generation is in flight, and a swipe
            // must not be the way around it: the sheet is the only thing
            // holding the progress the reader is watching.
            .interactiveDismissDisabled(isWorking)
            .toolbar { toolbar }
            .alert("Rename concept", isPresented: Binding(get: { renaming != nil },
                                                          set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renamed)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("renameConceptField")
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") { applyRename() }
            } message: {
                Text("A name another concept already answers to leaves the map as it is — two spellings of one idea would land on one dot.")
            }
        }
    }

    // MARK: - Naming the field

    @ViewBuilder
    private var askingSection: some View {
        Section {
            TextField("Field — “Marine Biology”, “Site Reliability”", text: $field)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { generate() }
                .accessibilityIdentifier("generateField")
        } header: {
            SettingsHeader("What should the map cover?")
        } footer: {
            Text(tierFooter)
        }

        Section {
            Button {
                generate()
            } label: {
                Text("Generate")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canGenerate ? Theme.stateLearning : Theme.textTertiary)
            }
            .disabled(!canGenerate)
            .accessibilityIdentifier("generatePack")
        } footer: {
            Text("A generated map is a first draft, not an authority. You get to look at it — and drop or rename anything that does not belong — before it becomes your map.")
        }
    }

    private var canGenerate: Bool {
        tier != .unavailable && !PackGenerator.normalize(field).isEmpty
    }

    /// What this device will do, said before the reader asks rather than after.
    /// These three sentences are the Egress claim `PRIVACY.md` makes about
    /// generation; if one changes, that file changes with it.
    private var tierFooter: String {
        switch tier {
        case .onDevice:
            "Your iPhone designs this map itself, cluster by cluster. Nothing is sent anywhere."
        case .optIn:
            "Your own Claude key designs this map. The field name you type is the whole of what is sent — nothing about your reading, your map or your Sources goes with it."
        case .unavailable:
            PackGenerator.GenerationError.unavailable.localizedDescription
        }
    }

    // MARK: - Working

    private func workingSection(_ message: String) -> some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("generationProgress")
            }
            .padding(.vertical, 6)
        } footer: {
            Text("Designing a field takes a moment — the map is built a cluster at a time.")
        }
    }

    // MARK: - Reviewing what came back

    @ViewBuilder
    private func reviewSections(_ draft: PackDraft) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.file.field)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(draft.file.concepts.count) concepts · \(draft.file.clusterOrder.count) clusters · \(draft.origin.label)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 2)
            .accessibilityIdentifier("generatedPack")
        } header: {
            SettingsHeader("Your draft")
        } footer: {
            Text("Swipe a concept away to drop it, or tap it to rename — dependencies and stages follow. Nothing is installed until you tap Install.")
        }

        ForEach(draft.conceptsByCluster, id: \.cluster) { group in
            Section {
                ForEach(group.concepts, id: \.name) { concept in
                    Button {
                        renaming = concept.name
                        renamed = concept.name
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(concept.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(concept.definition)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("generatedConcept")
                    .swipeActions {
                        Button("Drop", role: .destructive) { remove(concept.name) }
                    }
                }
            } header: {
                SettingsHeader(group.cluster
                               + (group.cluster == draft.file.specialtyCluster ? " · side quest" : ""))
            }
        }
    }

    // MARK: - Saying why nothing came back

    private func failureSection(_ reason: String) -> some View {
        Section {
            Text(reason)
                .font(.system(size: 14))
                .foregroundStyle(Theme.danger)
                .accessibilityIdentifier("generationFailure")
            Button {
                phase = .asking
            } label: {
                Text("Try again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.stateLearning)
            }
            .accessibilityIdentifier("generateAgain")
        } header: {
            SettingsHeader("Nothing was installed")
        } footer: {
            Text("Your map is exactly as it was — a Pack that does not pass the same checks an imported one gets is never partly applied.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(isWorking)
                .accessibilityIdentifier("cancelGeneration")
        }
        if case .reviewing(let draft) = phase {
            ToolbarItem(placement: .confirmationAction) {
                Button("Install") { onFinished(draft) }
                    .accessibilityIdentifier("installGenerated")
            }
        }
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    // MARK: - Doing it

    private func generate() {
        guard canGenerate else { return }
        phase = .working("Starting…")
        Task {
            do {
                let draft = try await PackGenerator.generate(field: field) { message in
                    phase = .working(message)
                }
                phase = .reviewing(draft)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func remove(_ name: String) {
        guard case .reviewing(var draft) = phase else { return }
        draft.removeConcept(named: name)
        phase = .reviewing(draft)
    }

    private func applyRename() {
        defer { renaming = nil }
        guard let oldName = renaming, case .reviewing(var draft) = phase else { return }
        draft.renameConcept(oldName, to: renamed)
        phase = .reviewing(draft)
    }
}

#Preview {
    PackGenerateView { _ in }
}
