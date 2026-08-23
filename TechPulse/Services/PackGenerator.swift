import Foundation
import FoundationModels

// MARK: - Structured output for the on-device path

@Generable
struct GenClusterPlan {
    @Guide(description: "5 to 7 cluster names for this field, ordered from foundations to advanced")
    var clusters: [String]
    @Guide(description: "One cluster from the list that is the optional specialty lane")
    var specialty: String
}

@Generable
struct GenConcept {
    @Guide(description: "Short canonical concept name")
    var name: String
    @Guide(description: "One-line beginner definition, usable as a quiz question")
    var definition: String
    @Guide(description: "0-3 concepts to learn first, chosen ONLY from concepts listed earlier")
    var dependencies: [String]
}

@Generable
struct GenClusterConcepts {
    @Guide(description: "5 to 8 concepts for this cluster")
    var concepts: [GenConcept]
}

// MARK: - Generating a Pack

/// Builds a Pack from a field the reader typed.
///
/// Epic #2 promises a reader who picks a field *or generates one*, and this is
/// the second half. Ported from CareerPulse (`Services/PackGenerator.swift` at
/// `af8ab0c`) — ADR-0005 tracked it as the one part of the port that was
/// genuinely unfinished rather than deliberately narrowed.
///
/// **Model output is never trusted.** A Pack is data the app then navigates by,
/// and a model asked for fifty Concepts will hand back duplicates, Concepts that
/// depend on themselves, Dependencies on Concepts it never emitted, cycles, and
/// a specialty Cluster that is not in its own Cluster list. `sanitize` is what
/// makes such a reply installable, and `PackValidator` is what has the last
/// word: an import and a generation are checked by the same code, because a
/// Pack the app produced is not more trustworthy than one it was given.
///
/// **Sanitize rather than reject, where the choice exists.** A cycle loses one
/// Concept's Dependencies; a Concept naming a Cluster nobody declared brings the
/// Cluster with it. A flat Concept is a worse map than a staged one and a far
/// better outcome than "generation failed" over an edge the reader cannot see
/// and could not fix.
///
/// **Nothing here asks a host anything.** The model's suggested Sources are
/// model output too, and are exactly the case `FeedDiscovery` was built for —
/// but they are probed where every other suggestion is, at the moment the reader
/// accepts one (`PackSourceOffer.accept`). Probing here as the ported version
/// did would spend a host's patience on suggestions nobody has ticked yet, and
/// would be a second copy of a fetch this app answers once (#58).
@MainActor
enum PackGenerator {

    // MARK: What this device can do

    /// Which of the three tiers this device reaches.
    ///
    /// The same three-way `deepen` and Explain make, and deliberately not the
    /// same type. `ExplainTier.unavailable` is a reader who has not opted in and
    /// Explain says nothing at all; here the third tier is a reason on screen,
    /// because a reader who tapped Generate asked a question and must be
    /// answered. What must not drift is *which* tier a device reaches, and
    /// `PackGeneratorTests.generationAndExplainAgreeOnWhatADeviceCanReach`
    /// holds the two to the same answer rather than a comment asking the next
    /// reader to remember.
    enum Tier: Equatable {
        /// Apple Intelligence is present. Nothing leaves the device.
        case onDevice
        /// No on-device model, but the reader added their own Anthropic key.
        case optIn
        /// Neither, so there is nothing to ask and a reason to give.
        case unavailable

        /// On-device wins whenever it is available: it is both the better answer
        /// for a Pack this size and the one that sends nothing.
        static func choose(modelAvailable: Bool, hasKey: Bool) -> Tier {
            if modelAvailable { return .onDevice }
            return hasKey ? .optIn : .unavailable
        }
    }

    /// The tier this device reaches right now. Read by the view to say up front
    /// what will happen, and again by `generate` — a key can be added between.
    static var tier: Tier {
        #if DEBUG
        // A journey standing in a reply is standing in for the opt-in path,
        // because that is the shape of reply it substitutes. Saying so here
        // rather than in the view keeps the screen the reader's screen: the
        // footer it shows and the button it enables are the real ones.
        if UITestSupport.cannedGenerationReply != nil { return .optIn }
        #endif
        return Tier.choose(modelAvailable: IntelligenceService.isModelAvailable,
                           hasKey: KeychainStore.hasAnthropicKey)
    }

    /// Why a generation produced nothing. Every case is something to show the
    /// reader: a generation that fails silently is indistinguishable from one
    /// that is still running.
    enum GenerationError: LocalizedError, Equatable {
        case noField
        case unavailable
        case modelFailure(String)

        var errorDescription: String? {
            switch self {
            case .noField:
                "Name the field you want a map of."
            case .unavailable:
                "Generating a Pack needs Apple Intelligence, or your own Claude API key (Settings → AI engine)."
            case .modelFailure(let detail):
                "That didn't come back as a usable Pack: \(detail)"
            }
        }
    }

    /// The most of a typed field name that is used. Long enough for "Site
    /// Reliability Engineering", short enough that a paste cannot become the
    /// prompt.
    nonisolated static let maxFieldLength = 60

    // MARK: Generating

    /// Generates a Pack, reporting each step as it goes.
    ///
    /// Returns a `PackDraft` rather than a `PackFile`: what comes back is a Pack
    /// *and* where it came from, and the reader gets to look at it before it
    /// becomes their map.
    ///
    /// `progress` exists because this takes tens of seconds on the on-device
    /// path — it walks the Clusters one at a time, which is what the small model
    /// is good at — and a spinner that says nothing for that long reads as a
    /// hang.
    static func generate(field rawField: String,
                         progress: @escaping (String) -> Void) async throws -> PackDraft {
        let field = normalize(rawField)
        guard !field.isEmpty else { throw GenerationError.noField }

        var pack = try await askAModel(field: field, progress: progress)

        progress("Checking the map for loose ends…")
        pack = sanitize(pack)
        // A model is free to reword the field — "ai engineer" coming back as
        // "AI Engineering" is an improvement, and the Pack is named by its
        // author. Only a reply that named no field at all falls back on what
        // the reader typed, because a Pack with a blank field is one they
        // cannot tell apart from another in the library.
        if pack.field.isEmpty { pack.field = field }
        do {
            try PackValidator.validate(pack)
        } catch {
            // The validator's own words. It is the same check an imported Pack
            // gets, so the reader is told what is wrong with the file in the
            // vocabulary the rest of the app uses.
            throw GenerationError.modelFailure(error.localizedDescription)
        }
        return PackDraft(file: pack, origin: .generated)
    }

    /// The tier's own half of `generate`: everything up to and including a
    /// reply, and nothing after it.
    ///
    /// Split out for the one substitution a journey needs. The simulator has
    /// neither Apple Intelligence nor a Claude key, so a journey there can only
    /// ever photograph the third tier — worth one screenshot, and not the
    /// feature. What a journey stands in is the model's *reply*; everything
    /// downstream of this call is the real code, running over untrusted text
    /// exactly as it would over Anthropic's.
    private static func askAModel(field: String,
                                  progress: @escaping (String) -> Void) async throws -> PackFile {
        #if DEBUG
        if let canned = UITestSupport.cannedGenerationReply {
            progress("Asking Claude to design your map…")
            guard let pack = parseRemoteJSON(canned) else {
                throw GenerationError.modelFailure("the reply wasn't a pack")
            }
            return pack
        }
        #endif
        switch tier {
        case .onDevice:
            return try await generateOnDevice(field: field, progress: progress)
        case .optIn:
            return try await generateRemote(field: field, progress: progress)
        case .unavailable:
            throw GenerationError.unavailable
        }
    }

    /// The field as it is used: trimmed, and cut to `maxFieldLength`.
    nonisolated static func normalize(_ rawField: String) -> String {
        String(rawField.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxFieldLength))
    }

    // MARK: On-device — staged, because the small model does better in steps

    private static func generateOnDevice(field: String,
                                         progress: (String) -> Void) async throws -> PackFile {
        progress("Designing the clusters…")
        let planSession = LanguageModelSession(instructions: onDeviceInstructions.plan)
        guard let planResponse = try? await planSession.respond(
            to: "Field: \(field). Produce the cluster plan.",
            generating: GenClusterPlan.self
        ) else { throw GenerationError.modelFailure("the cluster plan didn't come back") }
        let plan = planResponse.content

        var concepts: [PackFile.PackConcept] = []
        var stages: [PackFile.PackStage] = []
        for (index, cluster) in plan.clusters.enumerated() {
            progress("Naming concepts: \(cluster)…")
            let session = LanguageModelSession(instructions: onDeviceInstructions.cluster)
            let earlier = concepts.map(\.name).joined(separator: ", ")
            // A Cluster the model declines to fill is skipped rather than
            // fatal: five good Clusters and a sixth it had nothing to say about
            // is a map, and `sanitize` drops the empty Cluster.
            guard let response = try? await session.respond(
                to: "Field: \(field)\nCluster: \(cluster)\nEarlier concepts: \(earlier)",
                generating: GenClusterConcepts.self
            ) else { continue }

            let clusterConcepts = response.content.concepts.map {
                PackFile.PackConcept(name: $0.name, cluster: cluster,
                                     definition: $0.definition,
                                     dependencies: $0.dependencies)
            }
            concepts.append(contentsOf: clusterConcepts)
            stages.append(PackFile.PackStage(title: "Stage \(index + 1) · \(cluster)",
                                             subtitle: "",
                                             concepts: clusterConcepts.map(\.name)))
        }

        return PackFile(field: field,
                        specialtyCluster: plan.specialty,
                        clusterOrder: plan.clusters,
                        concepts: concepts,
                        stages: stages,
                        // The on-device path suggests nothing. A small model
                        // asked for feed URLs invents plausible ones, and an
                        // invented URL costs the reader a Probe and a decision
                        // about a Source that never existed.
                        suggestedSources: [])
    }

    private static let onDeviceInstructions = (
        plan: "You design a field of study as a skill tree of named clusters.",
        cluster: """
        You list the key concepts of one cluster of a skill tree, each with a \
        one-line beginner definition. A concept's dependencies may only name \
        concepts provided as already covered.
        """
    )

    // MARK: Opt-in — the reader's own key, single shot

    /// What the opt-in path sends, built purely so that it is a unit test rather
    /// than a claim in a document (#29).
    ///
    /// The whole payload is the field name the reader typed. Not their Concepts,
    /// not their Mastery, not their Sources, and no passage of anything they
    /// have read — a Pack is generated *before* there is a map, and there is
    /// nothing about the reader in the question "what does a Site Reliability
    /// Engineer need to know". `PRIVACY.md` says exactly this, and
    /// `PackGeneratorTests` is what keeps the two in step.
    ///
    /// The shape is spelled out because a Pack is `Codable` and the reply is
    /// decoded strictly: Swift's synthesized decoding does not fall back on a
    /// property's default value, so a reply that omits `formatVersion` is not a
    /// Pack at all.
    nonisolated static func remotePrompt(field: String) -> (system: String, user: String) {
        (system: """
         You design a field of study as a skill tree. Reply with ONLY a JSON \
         object (no markdown fences, no commentary) with this exact shape:
         {"formatVersion":\(PackFile.currentFormatVersion),"field":str,\
         "specialtyCluster":str,"clusterOrder":[str],\
         "concepts":[{"name":str,"cluster":str,"definition":str,"dependencies":[str]}],\
         "stages":[{"title":str,"subtitle":str,"concepts":[str]}],\
         "suggestedSources":[{"name":str,"url":str,"category":str}]}
         Rules: 5-7 clusters, one of them an optional specialty lane placed last \
         in clusterOrder; 35-55 concepts in total, every one of them in a cluster \
         named by clusterOrder; definitions are one line and beginner-friendly; \
         a concept's dependencies name concepts to learn first, exist in this \
         same pack, never name the concept itself, number at most \
         \(PackFile.maxDependenciesPerConcept), and form no cycles; 4-6 stages in \
         dependency order; at most \(PackFile.maxSuggestedSources) suggestedSources, \
         each a real, well-known RSS or Atom feed at an https URL, categorised by \
         its own topic.
         """,
         user: "Field: \(field)")
    }

    private static func generateRemote(field: String,
                                       progress: (String) -> Void) async throws -> PackFile {
        guard let key = KeychainStore.read() else { throw GenerationError.unavailable }
        progress("Asking Claude to design your map…")
        let prompt = remotePrompt(field: field)
        let text: String
        do {
            text = try await AnthropicClient().complete(system: prompt.system,
                                                        user: prompt.user, apiKey: key)
        } catch {
            // The client's own `LocalizedError` — a rejected key, an API error,
            // a reply over the response limit. #29's finding was that these die
            // in a `try?` elsewhere; the reader asked for this one out loud.
            throw GenerationError.modelFailure(error.localizedDescription)
        }
        guard let pack = parseRemoteJSON(text) else {
            throw GenerationError.modelFailure("the reply wasn't a pack")
        }
        return pack
    }

    /// Reads a Pack out of a model's reply, tolerating ```json fences and stray
    /// prose either side of the object.
    ///
    /// Not `PackValidator.decodeAndValidate`: that reads bytes a *file* arrived
    /// as, where anything but JSON is the reader's problem to fix and the
    /// version is worth reporting on its own. This reads a reply, where "there
    /// is prose around it" is the normal case rather than a fault.
    nonisolated static func parseRemoteJSON(_ text: String) -> PackFile? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONDecoder().decode(PackFile.self,
                                         from: Data(String(text[start...end]).utf8))
    }

    // MARK: Sanitizer — make untrusted output installable, or fail with a reason

    /// Everything `PackValidator` would refuse, mended where mending is
    /// possible.
    ///
    /// Pure and `nonisolated`, so what the app will accept from a model is a
    /// unit test. Every clause below answers a specific `PackValidationError`,
    /// and the caps come from `PackFile` rather than from numbers repeated here
    /// — a bound the validator moves must move on this side too, which is the
    /// agreement #22 broke once already: it made the validator reject Concept
    /// names differing only in case, matching the case-folded dedupe this has
    /// always done, and nothing held the two together.
    ///
    /// The one thing it cannot mend is an empty Pack. A reply with no usable
    /// Concept in it stays empty, and `PackValidator.noConcepts` refuses it —
    /// which is right: there is no map to show, and the reader is told so.
    nonisolated static func sanitize(_ input: PackFile) -> PackFile {
        var pack = input
        pack.formatVersion = PackFile.currentFormatVersion
        pack.field = normalize(pack.field)

        // Concepts: trim, drop the unusable, fold duplicate names the way the
        // validator and the installer both read them, and cap the total.
        var seen: Set<String> = []
        var concepts: [PackFile.PackConcept] = []
        for var concept in pack.concepts {
            concept.name = concept.name.trimmingCharacters(in: .whitespacesAndNewlines)
            concept.definition = concept.definition.trimmingCharacters(in: .whitespacesAndNewlines)
            concept.cluster = concept.cluster.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !concept.name.isEmpty, !concept.definition.isEmpty,
                  !concept.cluster.isEmpty,
                  seen.insert(concept.name.lowercased()).inserted,
                  concepts.count < PackFile.maxConcepts
            else { continue }
            concepts.append(concept)
        }

        // Clusters: the author's order, minus the ones nothing is in, plus the
        // ones a Concept named without declaring. Deduped, because a repeated
        // Cluster draws two identical lanes and eats the cap twice.
        var clusterOrder: [String] = []
        var declared: Set<String> = []
        for cluster in pack.clusterOrder.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where concepts.contains(where: { $0.cluster == cluster }) {
            if declared.insert(cluster).inserted { clusterOrder.append(cluster) }
        }
        for concept in concepts where declared.insert(concept.cluster).inserted {
            clusterOrder.append(concept.cluster)
        }
        if clusterOrder.count > PackFile.maxClusters {
            let keep = Set(clusterOrder.prefix(PackFile.maxClusters))
            clusterOrder = Array(clusterOrder.prefix(PackFile.maxClusters))
            concepts.removeAll { !keep.contains($0.cluster) }
        }
        // A specialty lane naming a Cluster that does not exist becomes the last
        // one, which is where the prompt asks for it. Nothing is invented for a
        // Pack that named no specialty at all: a Pack need not have a Side Quest,
        // and a blank name is a Pack that named none rather than one whose lane
        // needs finding.
        let specialty = pack.specialtyCluster?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pack.specialtyCluster = specialty.isEmpty
            ? nil
            : (clusterOrder.contains(specialty) ? specialty : clusterOrder.last)

        // Dependencies: no self-reference, nothing the Pack does not contain,
        // no repeat, and no more than the validator allows.
        let names = Set(concepts.map(\.name))
        for index in concepts.indices {
            var kept: Set<String> = []
            concepts[index].dependencies = Array(
                concepts[index].dependencies
                    .filter {
                        names.contains($0) && $0 != concepts[index].name
                            && kept.insert($0).inserted
                    }
                    .prefix(PackFile.maxDependenciesPerConcept)
            )
        }
        concepts = breakingCycles(concepts)

        // Stages: drop names the Pack does not contain, then the Stages that
        // leaves empty. A Pack with no Stages still has a Frontier — it just has
        // no opinion about what to read first — but a model that emitted none at
        // all was asked for an opinion, so its Clusters stand in for one.
        var stages = pack.stages
        for index in stages.indices {
            var kept: Set<String> = []
            stages[index].concepts.removeAll { !names.contains($0) || !kept.insert($0).inserted }
        }
        stages.removeAll { $0.concepts.isEmpty }
        if stages.isEmpty {
            stages = clusterOrder.enumerated().map { index, cluster in
                PackFile.PackStage(title: "Stage \(index + 1) · \(cluster)", subtitle: "",
                                   concepts: concepts.filter { $0.cluster == cluster }.map(\.name))
            }
        }

        pack.concepts = concepts
        pack.clusterOrder = clusterOrder
        pack.stages = stages
        // The suggestions are capped, not checked: whether a URL is a Source is
        // a question for the host, and it is asked once, where every other
        // suggestion is asked (`PackSourceOffer.accept`).
        pack.suggestedSources = Array(pack.suggestedSources.prefix(PackFile.maxSuggestedSources))
        return pack
    }

    /// Kahn's algorithm run repeatedly: whatever it cannot settle is in a cycle,
    /// and the first such Concept loses its Dependencies until nothing is stuck.
    ///
    /// Flattening one Concept rather than refusing the Pack. A cycle is an edge
    /// the reader can neither see nor fix, and `PackValidator.dependencyCycle`
    /// is fatal because a Frontier has no starting point without a DAG — so the
    /// choice is one Concept that arrives ready to learn, or no map at all.
    private nonisolated static func breakingCycles(
        _ input: [PackFile.PackConcept]
    ) -> [PackFile.PackConcept] {
        var concepts = input
        while true {
            var remaining = Dictionary(uniqueKeysWithValues:
                concepts.map { ($0.name, $0.dependencies.count) })
            var dependents: [String: [String]] = [:]
            for concept in concepts {
                for dependency in concept.dependencies {
                    dependents[dependency, default: []].append(concept.name)
                }
            }
            var queue = remaining.filter { $0.value == 0 }.map(\.key)
            var settled: Set<String> = []
            while let name = queue.popLast() {
                settled.insert(name)
                for dependent in dependents[name] ?? [] {
                    remaining[dependent]? -= 1
                    if remaining[dependent] == 0 { queue.append(dependent) }
                }
            }
            guard let stuck = concepts.firstIndex(where: { !settled.contains($0.name) })
            else { return concepts }
            concepts[stuck].dependencies = []
        }
    }
}
