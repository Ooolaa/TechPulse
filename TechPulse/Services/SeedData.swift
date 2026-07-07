import SwiftData
import Foundation

/// Default AI feed sources (user-editable in Settings), per build spec §8.
enum SeedData {
    static let defaultSources: [(name: String, url: String, category: String)] = [
        ("arXiv cs.AI", "https://export.arxiv.org/rss/cs.AI", "Research"),
        ("arXiv cs.LG", "https://export.arxiv.org/rss/cs.LG", "Research"),
        ("arXiv cs.CL", "https://export.arxiv.org/rss/cs.CL", "Research"),
        ("Hugging Face Blog", "https://huggingface.co/blog/feed.xml", "Open Source"),
        ("OpenAI News", "https://openai.com/news/rss.xml", "Frontier Labs"),
        ("Google DeepMind Blog", "https://deepmind.google/blog/rss.xml", "Frontier Labs"),
        ("MIT Technology Review — AI", "https://www.technologyreview.com/topic/artificial-intelligence/feed", "Industry"),
        ("The Verge — AI", "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", "Industry"),
        ("VentureBeat — AI", "https://venturebeat.com/category/ai/feed/", "Industry"),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<FeedSource>())) ?? 0
        if count == 0 {
            for source in defaultSources {
                guard let url = URL(string: source.url) else { continue }
                context.insert(FeedSource(name: source.name, url: url, category: source.category))
            }
            try? context.save()
        }
        seedResumeKnowledgeIfNeeded(context: context)
        // After the resume: pack concepts merge with anything already known
        // (Fine-Tuning, PyTorch stay green) and everything joins its cluster.
        KnowledgePack.seedIfNeeded(context: context)
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

        for (_, resumeConcepts) in resumeProjects {
            var projectConcepts: [Concept] = []
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
                projectConcepts.append(concept)
            }
            KnowledgeEngine.linkCooccurring(projectConcepts, context: context)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: "resumeKnowledgeSeeded")
    }
}
