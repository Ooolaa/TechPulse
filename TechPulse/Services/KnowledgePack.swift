import Foundation
import SwiftData

/// The AI Engineer map as compiled Swift.
///
/// No longer what the app runs on: since #6 the map is installed from
/// `Resources/Packs/ai-engineer.json`. This survives as the fixture
/// `BuiltinPacksTests` compares that file against, so the conversion cannot
/// silently drop content, and as `ActivePack.compiled`'s source. Delete it and
/// you delete the only proof the two agree.
enum KnowledgePack {
    /// Cluster display order (matches the pack's reading order).
    static let clusterOrder = [
        "Foundations", "Hot Topics", "Data Science", "LLM Engineering", "Evaluation", "Agents",
        "Inference & Infra", "Safety & Production", "On-Device AI",
    ]



    /// Historical. The live lever is `PackMigration.builtinPackVersion`; this
    /// remains only so `seedIfNeeded` still compiles for the tests that
    /// simulate a pre-Pack install.
    static let packVersion = 3

    /// The app's specialty lane, shown as a full-width card.
    static let specialtyCluster = "On-Device AI"

    /// The flagship's suggested Sources, as compiled Swift.
    ///
    /// A fixture, like `concepts` and `stages` above it, and nothing reads it
    /// at runtime: `ai-engineer.json` is what reaches a reader, and
    /// `BuiltinPacksTests` compares the two so the conversion cannot silently
    /// drop one. It used to be `SeedData.defaultSources`, which both pinned the
    /// file *and* delivered Sources on every launch — one list that a Pack file
    /// and a compiled array both claimed to own, which is what made #46 subtle
    /// (#47).
    static let suggestedSources: [(name: String, url: String, category: String)] = [
        ("arXiv cs.AI", "https://export.arxiv.org/rss/cs.AI", "Research"),
        ("arXiv cs.LG", "https://export.arxiv.org/rss/cs.LG", "Research"),
        ("arXiv cs.CL", "https://export.arxiv.org/rss/cs.CL", "Research"),
        ("Apple ML Research", "https://machinelearning.apple.com/rss.xml", "Research"),
        ("Hugging Face Blog", "https://huggingface.co/blog/feed.xml", "Open Source"),
        // Vote-ranked, which is the whole point of it: what a Source is ordered
        // by is part of what you subscribed to, so community attention reaches
        // the 🔥 lane without the app ever learning that popularity exists
        // (ADR-0003, #46). One such Source, not several — they share a host,
        // so they would share a queue (#44).
        ("r/MachineLearning (top this week)", "https://www.reddit.com/r/MachineLearning/top/.rss?t=week", "LLMs"),
        ("OpenAI News", "https://openai.com/news/rss.xml", "Frontier Labs"),
        ("Google DeepMind Blog", "https://deepmind.google/blog/rss.xml", "Frontier Labs"),
        ("MIT Technology Review — AI", "https://www.technologyreview.com/topic/artificial-intelligence/feed", "Industry"),
        ("The Verge — AI", "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", "Industry"),
        ("VentureBeat — AI", "https://venturebeat.com/category/ai/feed/", "Industry"),
        ("TechCrunch — AI", "https://techcrunch.com/category/artificial-intelligence/feed/", "Industry"),
        ("Kaggle (r/kaggle)", "https://www.reddit.com/r/kaggle/.rss", "Data Science"),
        ("KDnuggets", "https://www.kdnuggets.com/feed", "Data Science"),
    ]

    struct PackConcept {
        let name: String
        let cluster: String
        let definition: String
        let prerequisites: [String]
    }

    static let concepts: [PackConcept] = [
        // 🧱 Foundations
        .init(name: "PyTorch", cluster: "Foundations",
              definition: "The lingua franca of ML — everything else is built on it.", prerequisites: []),
        .init(name: "Linear Algebra", cluster: "Foundations",
              definition: "Matrices ARE the model: weights and embeddings are linear algebra.", prerequisites: []),
        .init(name: "Probability & Statistics", cluster: "Foundations",
              definition: "Sampling, temperature and loss functions are applied probability.", prerequisites: []),
        .init(name: "Gradient Descent", cluster: "Foundations",
              definition: "How every model learns: follow the loss downhill via backprop.", prerequisites: ["Linear Algebra"]),
        .init(name: "Tokenization", cluster: "Foundations",
              definition: "How text becomes numbers (BPE, tiktoken).", prerequisites: []),
        .init(name: "Embeddings", cluster: "Foundations",
              definition: "Meaning as vectors; powers RAG and semantic search.", prerequisites: ["Linear Algebra"]),
        .init(name: "Attention", cluster: "Foundations",
              definition: "The core operation of transformers: weigh which inputs matter for each output.", prerequisites: ["Embeddings"]),
        .init(name: "Transformer Architecture", cluster: "Foundations",
              definition: "The blueprint of every modern LLM.", prerequisites: ["Attention", "Tokenization"]),
        .init(name: "Positional Encoding", cluster: "Foundations",
              definition: "How transformers know word order (RoPE).", prerequisites: ["Transformer Architecture"]),
        .init(name: "Pretraining", cluster: "Foundations",
              definition: "Base knowledge learned from raw text at scale.", prerequisites: ["Transformer Architecture"]),
        .init(name: "Fine-Tuning", cluster: "Foundations",
              definition: "Continuing training of a pretrained model on task-specific data.", prerequisites: ["Pretraining"]),
        .init(name: "LoRA / QLoRA", cluster: "Foundations",
              definition: "Fine-tune big models on small GPUs with low-rank adapters.", prerequisites: ["Fine-Tuning"]),
        .init(name: "RLHF / DPO", cluster: "Foundations",
              definition: "How models learn to be helpful and aligned from preference data.", prerequisites: ["Fine-Tuning"]),

        // 🔥 Hot Topics (the 2025-26 radar: what the world is talking about)
        .init(name: "Vision Language Models", cluster: "Hot Topics",
              definition: "Models that jointly understand images and text — e.g. analyzing traffic-camera frames.", prerequisites: ["Attention"]),
        .init(name: "Reasoning Models", cluster: "Hot Topics",
              definition: "Models that spend extra test-time compute thinking step-by-step before answering (o-series, R1).", prerequisites: ["Transformer Architecture"]),
        .init(name: "Vibe Coding", cluster: "Hot Topics",
              definition: "Building software by describing intent to an AI and iterating on results instead of hand-writing code.", prerequisites: ["Coding Agents"]),
        .init(name: "World Models", cluster: "Hot Topics",
              definition: "Models that learn an internal simulation of the world to predict what happens next — the bet behind embodied AI.", prerequisites: ["Pretraining"]),
        .init(name: "Synthetic Data", cluster: "Hot Topics",
              definition: "Model-generated training data that stretches or replaces scarce human data.", prerequisites: ["Pretraining"]),
        .init(name: "Open-Weights Models", cluster: "Hot Topics",
              definition: "Downloadable frontier-class models (Llama, DeepSeek) you can run and fine-tune yourself.", prerequisites: ["Fine-Tuning"]),
        .init(name: "Small Language Models", cluster: "Hot Topics",
              definition: "Sub-10B models that trade raw power for speed, cost, and on-device deployment.", prerequisites: ["Distillation"]),
        .init(name: "Diffusion Models", cluster: "Hot Topics",
              definition: "Generate images and video by learning to reverse noise — the engine of modern generative media.", prerequisites: ["Probability & Statistics"]),
        .init(name: "AI Video Generation", cluster: "Hot Topics",
              definition: "Text-to-video systems (Sora, Veo) — the current frontier of generative media.", prerequisites: ["Diffusion Models"]),
        .init(name: "Humanoid Robotics", cluster: "Hot Topics",
              definition: "Foundation models meeting hardware: general-purpose robots learning from demonstration.", prerequisites: ["World Models"]),

        // 📊 Data Science (the craft under every model — and the Kaggle feed's home)
        .init(name: "Exploratory Data Analysis", cluster: "Data Science",
              definition: "Look at the data before modeling: distributions, outliers, missing values.", prerequisites: ["Probability & Statistics"]),
        .init(name: "Feature Engineering", cluster: "Data Science",
              definition: "Turning raw columns into signals a model can learn from.", prerequisites: ["Exploratory Data Analysis"]),
        .init(name: "Cross-Validation", cluster: "Data Science",
              definition: "Estimate real-world performance by testing on held-out folds.", prerequisites: ["Probability & Statistics"]),
        .init(name: "Data Leakage", cluster: "Data Science",
              definition: "When training data secretly contains the answer — great scores, useless model.", prerequisites: ["Cross-Validation"]),
        .init(name: "Class Imbalance", cluster: "Data Science",
              definition: "When some labels dominate a dataset, biasing what the model learns.", prerequisites: ["Exploratory Data Analysis"]),
        .init(name: "Gradient-Boosted Trees", cluster: "Data Science",
              definition: "XGBoost/LightGBM — still the strongest baseline on tabular data.", prerequisites: ["Feature Engineering", "Cross-Validation"]),
        .init(name: "Model Ensembling", cluster: "Data Science",
              definition: "Combine diverse models to beat any single one.", prerequisites: ["Gradient-Boosted Trees"]),
        .init(name: "Kaggle Competitions", cluster: "Data Science",
              definition: "Practice arena: real datasets, leaderboards, and shared winning notebooks.", prerequisites: ["Feature Engineering", "Cross-Validation"]),

        // 🤖 LLM Engineering
        .init(name: "Prompt Engineering", cluster: "LLM Engineering",
              definition: "The cheapest lever for output quality.", prerequisites: []),
        .init(name: "Structured Outputs", cluster: "LLM Engineering",
              definition: "JSON/schema generation for reliable pipelines.", prerequisites: ["Prompt Engineering"]),
        .init(name: "Context Engineering", cluster: "LLM Engineering",
              definition: "Managing what goes in the window — the 2025-26 skill.", prerequisites: ["Prompt Engineering", "RAG"]),
        .init(name: "Vector Databases", cluster: "LLM Engineering",
              definition: "Store and search embeddings at scale.", prerequisites: ["Embeddings"]),
        .init(name: "RAG", cluster: "LLM Engineering",
              definition: "Ground answers in your data to reduce hallucination.", prerequisites: ["Vector Databases"]),
        .init(name: "Chunking", cluster: "LLM Engineering",
              definition: "Bad chunks = bad RAG; splitting is a modeling decision.", prerequisites: ["RAG"]),
        .init(name: "Hybrid Search", cluster: "LLM Engineering",
              definition: "Keyword (BM25) + semantic search beats either alone.", prerequisites: ["Vector Databases"]),
        .init(name: "Reranking", cluster: "LLM Engineering",
              definition: "Second-pass precision on retrieved results.", prerequisites: ["Hybrid Search"]),
        .init(name: "Long-Context Management", cluster: "LLM Engineering",
              definition: "1M-token windows still need curation.", prerequisites: ["Context Engineering"]),

        // 📏 Evaluation
        .init(name: "Benchmarks", cluster: "Evaluation",
              definition: "MMLU, SWE-bench and friends — know what scores mean and their limits.", prerequisites: []),
        .init(name: "Eval Suites", cluster: "Evaluation",
              definition: "Custom tests for YOUR use case; build before shipping.", prerequisites: ["Benchmarks", "Prompt Engineering"]),
        .init(name: "LLM-as-Judge", cluster: "Evaluation",
              definition: "Scale evaluation with models grading models.", prerequisites: ["Eval Suites"]),
        .init(name: "A/B & Regression Evals", cluster: "Evaluation",
              definition: "Catch quality drops on every change.", prerequisites: ["Eval Suites", "LLM-as-Judge"]),

        // 🕸️ Agents
        .init(name: "Tool Use", cluster: "Agents",
              definition: "Function calling: models acting, not just talking.", prerequisites: ["Structured Outputs"]),
        .init(name: "MCP", cluster: "Agents",
              definition: "Model Context Protocol — the standard for connecting models to tools and data.", prerequisites: ["Tool Use"]),
        .init(name: "Planning & Reasoning", cluster: "Agents",
              definition: "Task decomposition, chain-of-thought, test-time compute.", prerequisites: ["Prompt Engineering"]),
        .init(name: "Agent Memory", cluster: "Agents",
              definition: "Short-term scratchpads plus long-term recall.", prerequisites: ["RAG"]),
        .init(name: "Multi-Agent Orchestration", cluster: "Agents",
              definition: "Specialist agents collaborating on one task.", prerequisites: ["Planning & Reasoning", "Agent Memory", "MCP"]),
        .init(name: "Coding Agents", cluster: "Agents",
              definition: "Claude Code-style autonomous development workflows.", prerequisites: ["Tool Use"]),
        .init(name: "Computer-Use Agents", cluster: "Agents",
              definition: "Models operating GUIs directly.", prerequisites: ["Tool Use"]),

        // ⚡ Inference & Infra
        .init(name: "Quantization", cluster: "Inference & Infra",
              definition: "Shrink models 4–8× (GGUF, AWQ) with minor quality loss.", prerequisites: ["Transformer Architecture"]),
        .init(name: "Distillation", cluster: "Inference & Infra",
              definition: "Train small fast models from big ones.", prerequisites: ["Fine-Tuning"]),
        .init(name: "KV-Cache", cluster: "Inference & Infra",
              definition: "Why long chats get slow — the core serving concept.", prerequisites: ["Attention"]),
        .init(name: "Speculative Decoding", cluster: "Inference & Infra",
              definition: "2–3× faster generation by drafting with a small model.", prerequisites: ["KV-Cache"]),
        .init(name: "vLLM & Serving", cluster: "Inference & Infra",
              definition: "Production-grade throughput for model serving.", prerequisites: ["KV-Cache"]),
        .init(name: "Batching & Cost", cluster: "Inference & Infra",
              definition: "Latency/cost tradeoffs — the economics of AI products.", prerequisites: ["vLLM & Serving"]),

        // 📱 On-Device AI
        .init(name: "Apple Foundation Models", cluster: "On-Device AI",
              definition: "The on-device LLM API TechPulse itself uses.", prerequisites: ["Core ML", "MLX"]),
        .init(name: "Core ML", cluster: "On-Device AI",
              definition: "Apple's model deployment runtime.", prerequisites: ["Quantization"]),
        .init(name: "MLX", cluster: "On-Device AI",
              definition: "Apple-silicon ML framework for training and inference.", prerequisites: ["PyTorch"]),
        .init(name: "Guided Generation", cluster: "On-Device AI",
              definition: "@Generable structured outputs on-device.", prerequisites: ["Structured Outputs", "Apple Foundation Models"]),
        .init(name: "Privacy-Preserving AI", cluster: "On-Device AI",
              definition: "The selling point of on-device: nothing leaves the phone.", prerequisites: ["Apple Foundation Models"]),

        // 🛡️ Safety & Production
        .init(name: "Prompt Injection Defense", cluster: "Safety & Production",
              definition: "The #1 security risk for agents.", prerequisites: ["Tool Use"]),
        .init(name: "Jailbreak Awareness", cluster: "Safety & Production",
              definition: "Know the attack surface of deployed models.", prerequisites: ["Prompt Engineering"]),
        .init(name: "Hallucination Mitigation", cluster: "Safety & Production",
              definition: "Grounding, citations, calibrated uncertainty.", prerequisites: ["RAG"]),
        .init(name: "Guardrails", cluster: "Safety & Production",
              definition: "Input/output filtering layers.", prerequisites: ["Eval Suites"]),
        .init(name: "Red-Teaming", cluster: "Safety & Production",
              definition: "Attack your own system before others do.", prerequisites: ["Guardrails", "Prompt Injection Defense"]),
        .init(name: "Observability", cluster: "Safety & Production",
              definition: "Tracing, logging, cost monitoring in production.", prerequisites: ["vLLM & Serving"]),
    ]

    /// Learning path stages (pack §8), concept-level.
    static let stages: [(title: String, subtitle: String, conceptNames: [String])] = [
        ("Stage 1 · Foundations",
         "Python, math, tokenization, embeddings",
         ["PyTorch", "Linear Algebra", "Probability & Statistics", "Gradient Descent", "Tokenization", "Embeddings"]),
        ("Stage 2 · Data science craft",
         "EDA, features, validation — the Kaggle skill set",
         ["Exploratory Data Analysis", "Feature Engineering", "Cross-Validation", "Data Leakage", "Class Imbalance", "Gradient-Boosted Trees", "Model Ensembling", "Kaggle Competitions"]),
        ("Stage 3 · Transformers & training",
         "Attention → transformer → fine-tuning",
         ["Attention", "Transformer Architecture", "Positional Encoding", "Pretraining", "Fine-Tuning", "LoRA / QLoRA", "RLHF / DPO"]),
        ("Stage 4 · Prompting, structured outputs, RAG",
         "The LLM engineering core",
         ["Prompt Engineering", "Structured Outputs", "Context Engineering", "Vector Databases", "RAG", "Chunking", "Hybrid Search", "Reranking", "Long-Context Management"]),
        ("Stage 5 · Evals + inference",
         "What separates seniors from juniors",
         ["Benchmarks", "Eval Suites", "LLM-as-Judge", "A/B & Regression Evals", "Quantization", "Distillation", "KV-Cache", "Speculative Decoding", "vLLM & Serving", "Batching & Cost"]),
        ("Stage 6 · Agents",
         "Tool use, MCP, orchestration",
         ["Tool Use", "MCP", "Planning & Reasoning", "Agent Memory", "Multi-Agent Orchestration", "Coding Agents", "Computer-Use Agents"]),
        ("Stage 7 · Safety & production",
         "Guardrails, red-teaming, observability",
         ["Prompt Injection Defense", "Jailbreak Awareness", "Hallucination Mitigation", "Guardrails", "Red-Teaming", "Observability"]),
        ("Stage 8 · Staying current",
         "The hot-topic radar: reasoning, agents, video, robots",
         ["Vision Language Models", "Reasoning Models", "Vibe Coding", "World Models", "Synthetic Data", "Open-Weights Models", "Small Language Models", "Diffusion Models", "AI Video Generation", "Humanoid Robotics"]),
    ]

    static let sideQuestConcepts = ["Apple Foundation Models", "Core ML", "MLX", "Guided Generation", "Privacy-Preserving AI"]

    // MARK: Seeding

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        // Versioned, not one-shot: installs that seeded an older pack re-run
        // the merge (idempotent by name) and gain the new concepts/deps.
        guard UserDefaults.standard.integer(forKey: "knowledgePackVersion") < packVersion else { return }
        seed(concepts, context: context)
        UserDefaults.standard.set(packVersion, forKey: "knowledgePackVersion")
    }

    /// The merge itself, over whatever Pack Concepts it is handed.
    ///
    /// Takes its data as a parameter so the same merge can run against an
    /// installed Pack — #6 changes what is passed, not what this does.
    /// Idempotent by name: a Concept that already exists keeps its Mastery.
    @MainActor
    static func seed(_ packConcepts: [PackConcept], context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        var byLowerName = Dictionary(existing.map { ($0.name.lowercased(), $0) },
                                     uniquingKeysWith: { first, _ in first })

        for pack in packConcepts {
            let concept: Concept
            if let found = byLowerName[pack.name.lowercased()] {
                concept = found
                // The pack's cluster taxonomy organizes the whole app now;
                // matched concepts keep their mastery but join their cluster.
                concept.category = pack.cluster
                if concept.conceptDefinition.isEmpty {
                    concept.conceptDefinition = pack.definition
                }
            } else {
                concept = Concept(name: pack.name, category: pack.cluster,
                                  definition: pack.definition)
                concept.masteryLevel = 0.0     // dim dot until you read/learn it
                context.insert(concept)
                byLowerName[pack.name.lowercased()] = concept
            }
        }

        let existingDeps = (try? context.fetch(FetchDescriptor<ConceptDependency>())) ?? []
        var depKeys = Set(existingDeps.map { "\($0.prerequisite)→\($0.dependent)" })
        var legacyLinkKeys = Set(((try? context.fetch(FetchDescriptor<ConceptLink>())) ?? [])
            .map { "\($0.conceptA)|\($0.conceptB)" })
        for pack in packConcepts {
            for prerequisite in pack.prerequisites {
                let key = "\(prerequisite)→\(pack.name)"
                guard !depKeys.contains(key) else { continue }
                context.insert(ConceptDependency(prerequisite: prerequisite, dependent: pack.name))
                depKeys.insert(key)
                // Mirrored as an undirected link, which is what compiled
                // seeding used to do. ADR-0002 forbids it — installing is not
                // reading — and nothing in the app seeds this way any more.
                // It stays because `PackMigrationTests` uses this to build a
                // store as it existed *before* Packs were data, unscored
                // mirror links and all, which is exactly what the rebuild has
                // to clean up.
                if let a = byLowerName[prerequisite.lowercased()],
                   let b = byLowerName[pack.name.lowercased()] {
                    let pair = [a.name, b.name].sorted()
                    let key = "\(pair[0])|\(pair[1])"
                    if legacyLinkKeys.insert(key).inserted {
                        context.insert(ConceptLink(conceptA: pair[0], conceptB: pair[1]))
                    }
                }
            }
        }
        try? context.save()
    }
}

// MARK: - The compiled pack as Pack data

extension ActivePack {
    /// The compiled pack, described the way an installed one is.
    ///
    /// This is the whole point of the prefactor: the engines stop reaching into
    /// `KnowledgePack` and take an `ActivePack` instead, while call sites keep
    /// handing them this one. Behaviour is unchanged until #6 passes the Pack
    /// the reader actually installed — which becomes a change to what is
    /// passed, not a rewrite of nine files.
    ///
    /// The coupling to `KnowledgePack` lives here rather than in the engines,
    /// so deleting the compiled pack means deleting this property and its
    /// callers, not hunting reads through the engine logic.
    static var compiled: ActivePack {
        ActivePack(
            field: "AI Engineering",
            specialtyCluster: KnowledgePack.specialtyCluster,
            clusterOrder: KnowledgePack.clusterOrder,
            stages: KnowledgePack.stages.map {
                .init(title: $0.title, subtitle: $0.subtitle, concepts: $0.conceptNames)
            },
            suggestedSources: KnowledgePack.suggestedSources.map {
                .init(name: $0.name, url: $0.url, category: $0.category)
            },
            conceptNames: KnowledgePack.concepts.map(\.name),
            sideQuestConcepts: KnowledgePack.sideQuestConcepts,
            origin: .builtin
        )
    }
}
