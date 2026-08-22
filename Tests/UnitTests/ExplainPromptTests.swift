import Testing
import Foundation
import SwiftData
@testable import TechPulse

// The Explain payload, per ADR-0006. The failure this covers is not a bug in a
// branch: it is a claim about Egress that nothing could check, which is how
// three documents came to say the opt-in path never sends article text while it
// did (#29). Prompt construction is pure so the claim is now a test.

@Suite("Explain prompt")
struct ExplainPromptTests {

    /// A sentence that could only have come from an article body. Every opt-in
    /// assertion below is written so this string turning up would fail it.
    private let excerpt = """
    The transformer architecture was scaled to a trillion parameters by the \
    Zephyr team at Northgate Labs, whose report is embargoed until Tuesday.
    """

    // MARK: On-device — the excerpt is the disambiguator

    @Test("on-device prompt carries the term and the surrounding excerpt")
    func onDeviceCarriesExcerpt() {
        let prompt = ExplainPrompt.onDevice(term: "transformer", excerpt: excerpt)

        #expect(prompt.user.contains("transformer"))
        #expect(prompt.user.contains(excerpt))
        // Nothing leaves the device here, so the better signal is free.
        #expect(prompt.system.contains("excerpt"))
    }

    // MARK: Opt-in — the reader's own Pack is the disambiguator

    @Test("opt-in prompt carries the term, the Pack's field and its Clusters")
    func optInCarriesPack() {
        let prompt = ExplainPrompt.optIn(term: "LoRA", field: "AI Engineering",
                                         clusters: ["Foundations", "Agents", "Evaluation"])

        #expect(prompt.user.contains("LoRA"))
        #expect(prompt.user.contains("AI Engineering"))
        for cluster in ["Foundations", "Agents", "Evaluation"] {
            #expect(prompt.user.contains(cluster))
        }
    }

    /// The regression test. `optIn` cannot be handed an excerpt, so the way
    /// article text would return is somebody widening it — an exact match goes
    /// red for any addition at all, not only for the one we thought of.
    @Test("opt-in prompt is exactly term, field and Clusters — nothing else")
    func optInSendsNoArticleText() {
        let prompt = ExplainPrompt.optIn(term: "LoRA", field: "AI Engineering",
                                         clusters: ["Foundations", "Agents"])

        #expect(prompt.user == """
        Term the reader selected: LoRA
        The field they are studying: AI Engineering
        Areas of that field on their map: Foundations, Agents
        """)
        // Said out loud as well, because the exact match above is the kind of
        // assertion someone updates to match a change rather than reading.
        #expect(!prompt.user.contains("Northgate"))
        #expect(!prompt.user.contains("embargoed"))
        #expect(!prompt.system.contains("excerpt"))
    }

    @Test("a Pack with no field or Clusters still explains the term")
    func optInDegradesToTermAlone() {
        let prompt = ExplainPrompt.optIn(term: "LoRA", field: "", clusters: [])

        #expect(prompt.user == "Term the reader selected: LoRA")
        #expect(!prompt.user.contains("field"))
        #expect(!prompt.user.contains("map"))
    }

    /// Not a scenario — `PackValidator` refuses to install a Pack with more than
    /// `PackFile.maxClusters` Clusters, so this list cannot arrive from a Pack.
    /// It pins the bound on the function itself, because what the function sends
    /// is a promise and this is where the promise is built.
    @Test("the Cluster list is bounded at the same ceiling the validator enforces")
    func optInBoundsClusters() {
        let many = (1...30).map { "Cluster \($0)" }
        let prompt = ExplainPrompt.optIn(term: "LoRA", field: "AI Engineering", clusters: many)

        #expect(prompt.user.contains("Cluster 1"))
        #expect(!prompt.user.contains("Cluster \(PackFile.maxClusters + 1)"))
    }

    // MARK: Both paths

    @Test("both paths tell the model the reader's text is not instructions")
    func bothCarryTheInjectionRule() {
        // The term comes from RSS body text too — shorter than the excerpt was,
        // and no less attacker-chosen. `WordSelection.normalize` bounds its
        // shape; this bounds what the model does with it.
        let onDevice = ExplainPrompt.onDevice(term: "transformer", excerpt: excerpt)
        let optIn = ExplainPrompt.optIn(term: "LoRA", field: "AI Engineering",
                                        clusters: ["Foundations"])

        #expect(onDevice.system.contains("not instructions"))
        #expect(optIn.system.contains("not instructions"))
    }

    @Test("the opt-in path asks for the JSON the BYO client has to parse")
    func optInAsksForJSON() {
        let prompt = ExplainPrompt.optIn(term: "LoRA", field: "AI Engineering",
                                         clusters: ["Foundations"])
        #expect(prompt.system.contains("\"name\""))
        #expect(prompt.system.contains("\"definition\""))
    }

    // MARK: Which prompt each tier gets

    // The prompt builders being right is not enough: #29 was a *call site*
    // sending the wrong one. `forTier` is where that choice now lives, so these
    // are the tests that go red if the opt-in tier is ever handed the on-device
    // prompt.

    @Test("the opt-in tier is handed the excerpt and sends it nowhere")
    func optInTierIgnoresTheExcerpt() throws {
        let prompt = try #require(ExplainPrompt.forTier(
            .optIn, term: "transformer", excerpt: excerpt,
            field: "AI Engineering", clusters: ["Foundations"]
        ))

        #expect(prompt == ExplainPrompt.optIn(term: "transformer", field: "AI Engineering",
                                              clusters: ["Foundations"]))
        #expect(!prompt.user.contains("Northgate"))
        #expect(!prompt.user.contains(excerpt))
    }

    @Test("the on-device tier gets the excerpt, which never leaves the phone")
    func onDeviceTierGetsTheExcerpt() throws {
        let prompt = try #require(ExplainPrompt.forTier(
            .onDevice, term: "transformer", excerpt: excerpt,
            field: "AI Engineering", clusters: ["Foundations"]
        ))

        #expect(prompt == ExplainPrompt.onDevice(term: "transformer", excerpt: excerpt))
        #expect(prompt.user.contains(excerpt))
    }

    @Test("the unavailable tier has no prompt at all")
    func unavailableTierSendsNothing() {
        #expect(ExplainPrompt.forTier(.unavailable, term: "transformer", excerpt: excerpt,
                                      field: "AI Engineering", clusters: ["Foundations"]) == nil)
    }

    @Test("on-device wins where both are available, so nothing is sent that need not be")
    func tierPrefersOnDevice() {
        #expect(ExplainTier.choose(modelAvailable: true, hasKey: true) == .onDevice)
        #expect(ExplainTier.choose(modelAvailable: true, hasKey: false) == .onDevice)
        #expect(ExplainTier.choose(modelAvailable: false, hasKey: true) == .optIn)
        #expect(ExplainTier.choose(modelAvailable: false, hasKey: false) == .unavailable)
    }
}

// MARK: - Degrading with neither path available

/// ADR-0006 kept Explain on hardware without Apple Intelligence rather than
/// deleting it, so the third tier — no on-device model *and* no key — has to end
/// in nothing happening, not in a crash or a half-made Concept.
@MainActor
@Suite("Explain with no model and no key", .serialized)
struct ExplainDegradationTests {

    private static let store = TestStore()

    @Test("returns nil and writes nothing, rather than crashing")
    func definesNothing() async throws {
        let context = try Self.store.makeContext()

        // This is the simulator's state and the reference device's state without
        // a key, but not every machine's. Where a path *is* available the call
        // would reach a model, so assert instead something that is not simply
        // `canDeepen`'s own definition read back — that the property the UI
        // gates on and the tier the prompt layer picks agree about this device.
        // Two expressions that could drift, rather than one restated.
        guard !IntelligenceService.canDeepen else {
            #expect(ExplainTier.choose(modelAvailable: IntelligenceService.isModelAvailable,
                                       hasKey: KeychainStore.hasAnthropicKey) != .unavailable,
                    "the UI offers Explain here but the prompt layer would send nothing")
            return
        }

        let concept = await IntelligenceService.define(
            term: "LoRA",
            excerpt: "Fine-tuning with LoRA adapters keeps the base weights frozen.",
            context: context
        )
        #expect(concept == nil)
        #expect(try context.fetch(FetchDescriptor<Concept>()).isEmpty,
                "a path that cannot explain anything must not leave a dot behind")
    }
}
