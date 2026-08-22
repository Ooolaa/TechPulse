import SwiftData
import Foundation

/// What a store holds before the reader has done anything: the Sources their
/// Pack suggests, and the knowledge their resume already proves.
enum SeedData {
    private static let retiredSourceURLs: Set<String> = [
        "https://medium.com/feed/kaggle-blog",
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        seedResumeKnowledgeIfNeeded(context: context)
        // After the resume: the built-in Pack installs over the top, so
        // anything already known (Fine-Tuning, PyTorch) stays green and
        // everything joins its Cluster. The map now comes from a Pack file.
        PackMigration.ensureBuiltinInstalled(context: context)
        // After the Pack, not before it: which Sources this reader should be
        // offered comes from the Pack they are on, and which Pack that is is
        // only settled by the line above (#47).
        acquireSourcesIfNeeded(context: context)
        // Both kinds of derived edge are settled at launch, so a store written
        // before either existed opens on the same map a fresh install would.
        PackMigration.ensureSemanticLinks(context: context)
        KnowledgeEngine.rebuildCoreadLinks(context: context)
    }

    /// What the app may do to a reader's Sources unprompted, which is almost
    /// nothing: retire the ones that turned out dead, and — on a store that
    /// had none at all — subscribe what the Active Pack suggests.
    @MainActor
    static func acquireSourcesIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<FeedSource>())) ?? []
        retireDeadSources(among: existing, context: context)
        // Measured before the retirement, deliberately. A store that held
        // Sources has had its first launch, whatever retiring one leaves
        // behind — re-seeding it would hand back Sources the reader was never
        // offered, which is the thing this whole path exists to stop.
        guard existing.isEmpty else { return }
        subscribeToTheActivePacksSuggestions(context: context)
    }

    /// Removes Sources that were once shipped and have since gone quiet.
    /// (Kaggle's Medium blog stopped posting in 2020.)
    @MainActor
    private static func retireDeadSources(among existing: [FeedSource],
                                          context: ModelContext) {
        let dead = existing.filter { retiredSourceURLs.contains($0.url.absoluteString) }
        guard !dead.isEmpty else { return }
        dead.forEach(context.delete)
        try? context.save()
    }

    /// The one moment the app subscribes on the reader's behalf: a store with
    /// nothing to read at all.
    ///
    /// An offer needs a Feed to be weighed against, and an empty app is a worse
    /// first impression than a Source too many — the reader can turn any of them
    /// off in Settings, which is where an offer would have sent them.
    ///
    /// Every launch after this subscribes to nothing. A Source added to a Pack
    /// in a new version of the app is *offered* instead, and waits in Settings
    /// until the reader answers. Subscribing it here would deliver a Source
    /// nobody chose and then suppress the offer for it permanently, because
    /// `PackSourceOffer.pending` filters out what is already subscribed — the
    /// reader could never be asked, because they already had it (#47, ADR-0011).
    ///
    /// Reading the Active Pack rather than a compiled list is the other half: a
    /// reader on Security Engineering is asked about Security Engineering's
    /// Sources, and stops being handed the flagship's.
    @MainActor
    private static func subscribeToTheActivePacksSuggestions(context: ModelContext) {
        PackSourceOffer.subscribe(ActivePack.inUse.suggestedSources, context: context)
    }

    /// The resume's projects as co-read groups: Concepts used on the same
    /// project were met together, the same way an article's Concepts were.
    static var resumeCoreadGroups: [[String]] {
        resumeProjects.map { $0.concepts.map(\.name) }
    }

    // MARK: Resume-based knowledge base
    // John's completed projects seed the graph: each concept starts fully
    // mastered (green), and concepts used in the same project get linked —
    // the same co-occurrence rule articles use.

    private struct ResumeConcept {
        let name: String
        let category: String
        let definition: String
    }

    private static let resumeProjects: [(project: String, concepts: [ResumeConcept])] = [
        ("StreamSight", [
            .init(name: "Vision Language Models", category: "Vision",
                  definition: "Models that jointly understand images and text — e.g. analyzing traffic-camera frames."),
            .init(name: "Ollama", category: "Open Source",
                  definition: "A local runtime for serving open LLMs on your own hardware."),
            .init(name: "FastAPI", category: "Dev Tools",
                  definition: "An async Python web framework for building high-performance APIs."),
            .init(name: "Mirostat Sampling", category: "LLMs",
                  definition: "A decoding strategy that targets constant output perplexity to stop repetition loops."),
            .init(name: "REST APIs", category: "Dev Tools",
                  definition: "A convention for structuring HTTP endpoints around resources and verbs."),
            .init(name: "NVIDIA CUDA", category: "Hardware/Chips",
                  definition: "NVIDIA's GPU computing platform that accelerates model inference and training."),
            .init(name: "MySQL", category: "Dev Tools",
                  definition: "A widely used relational database."),
        ]),
        ("SeedSent", [
            .init(name: "DeBERTa", category: "LLMs",
                  definition: "A transformer encoder with disentangled attention, strong at text classification."),
            .init(name: "Aspect-Based Sentiment Analysis", category: "LLMs",
                  definition: "Classifying sentiment toward specific aspects mentioned in a sentence, not just overall tone."),
            .init(name: "Few-Shot Learning", category: "LLMs",
                  definition: "Getting a model to perform a task from only a handful of labelled examples."),
            .init(name: "Fine-Tuning", category: "LLMs",
                  definition: "Continuing training of a pretrained model on task-specific data."),
            .init(name: "Pseudo-Labelling", category: "LLMs",
                  definition: "Using model-generated labels to bootstrap training data cheaply."),
            .init(name: "Class Imbalance", category: "LLMs",
                  definition: "When some labels dominate a dataset, biasing what the model learns."),
            .init(name: "Docker", category: "Dev Tools",
                  definition: "Packages software into containers that run identically anywhere."),
            .init(name: "PyTorch", category: "Open Source",
                  definition: "The dominant deep-learning framework for research and production."),
        ]),
        ("Thesis: Dense vs Sparse Layers", [
            .init(name: "Explainable AI", category: "Policy/Safety",
                  definition: "Techniques that make model decisions understandable to humans."),
            .init(name: "Interpretability", category: "Policy/Safety",
                  definition: "Understanding which internal features drive a model's predictions."),
            .init(name: "ResNet", category: "Vision",
                  definition: "A deep CNN architecture whose residual connections enable very deep networks."),
            .init(name: "Sparse Neural Layers", category: "LLMs",
                  definition: "Layers with restricted connectivity that trade a little accuracy for traceable decision paths."),
            .init(name: "PyTorch", category: "Open Source",
                  definition: "The dominant deep-learning framework for research and production."),
        ]),
        ("Nomad", [
            .init(name: "SwiftUI", category: "Dev Tools",
                  definition: "Apple's declarative UI framework for building native apps."),
            .init(name: "WebSockets", category: "Dev Tools",
                  definition: "A persistent two-way connection for real-time streaming between client and server."),
            .init(name: "ngrok", category: "Dev Tools",
                  definition: "Tunnels a local server to a public URL without deploying."),
            .init(name: "REST APIs", category: "Dev Tools",
                  definition: "A convention for structuring HTTP endpoints around resources and verbs."),
        ]),
        ("MailSafe", [
            .init(name: "Flask", category: "Dev Tools",
                  definition: "A lightweight Python web framework."),
            .init(name: "Docker", category: "Dev Tools",
                  definition: "Packages software into containers that run identically anywhere."),
            .init(name: "AWS", category: "Dev Tools",
                  definition: "Amazon's cloud platform for hosting and infrastructure."),
            .init(name: "Terraform", category: "Dev Tools",
                  definition: "Infrastructure-as-code: declare cloud resources and rebuild them identically anywhere."),
        ]),
    ]

    @MainActor
    static func seedResumeKnowledgeIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: "resumeKnowledgeSeeded") else { return }

        let existing = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        var byLowerName = Dictionary(existing.map { ($0.name.lowercased(), $0) },
                                     uniquingKeysWith: { first, _ in first })

        // No links are written here. The projects are readings like any other,
        // and `rebuildCoreadLinks` scores them from `resumeCoreadGroups`
        // alongside the articles.
        for (_, resumeConcepts) in resumeProjects {
            for item in resumeConcepts {
                let concept: Concept
                if let found = byLowerName[item.name.lowercased()] {
                    concept = found
                } else {
                    concept = Concept(name: item.name, category: item.category,
                                      definition: item.definition)
                    context.insert(concept)
                    byLowerName[item.name.lowercased()] = concept
                }
                concept.isMarkedKnown = true
                concept.masteryLevel = 1.0
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: "resumeKnowledgeSeeded")
    }
}
