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

    @Test("the Cluster list is capped so a large Pack can't grow the payload")
    func optInCapsClusters() {
        let many = (1...30).map { "Cluster \($0)" }
        let prompt = ExplainPrompt.optIn(term: "LoRA", field: "AI Engineering", clusters: many)

        #expect(prompt.user.contains("Cluster 1"))
        #expect(!prompt.user.contains("Cluster 30"))
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
}

// MARK: - Degrading with neither path available

/// ADR-0006 kept Explain on hardware without Apple Intelligence rather than
/// deleting it, so the third tier — no on-device model *and* no key — has to end
/// in nothing happening, not in a crash or a half-made Concept.
@MainActor
@Suite("Explain with no model and no key", .serialized)
struct ExplainDegradationTests {

    private static let sharedContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: FeedSource.self, Article.self, Concept.self,
            LearningEvent.self, ConceptLink.self, ConceptDependency.self,
            SemanticLink.self, InstalledPack.self,
            configurations: config
        )
    }()

    @Test("returns nil and writes nothing, rather than crashing")
    func definesNothing() async throws {
        let context = Self.sharedContainer.mainContext
        for concept in try context.fetch(FetchDescriptor<Concept>()) { context.delete(concept) }

        // This is the simulator's state and the reference device's state without
        // a key, but not every machine's. Where a path *is* available the call
        // would reach a model, so assert instead the invariant that made us skip
        // — rather than returning early having checked nothing, which is the
        // failure mode #16 found next door in the XXE test.
        guard !IntelligenceService.canDeepen else {
            #expect(IntelligenceService.isModelAvailable || KeychainStore.hasAnthropicKey,
                    "canDeepen is true with neither a model nor a key behind it")
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
