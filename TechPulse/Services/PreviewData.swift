import SwiftData
import Foundation

/// In-memory container with sample content for SwiftUI previews only.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: FeedSource.self, Article.self, Concept.self,
            LearningEvent.self, ConceptLink.self, ConceptDependency.self,
            configurations: config
        )
        let context = container.mainContext
        SeedData.seedIfNeeded(context: context)

        let attention = Concept(name: "Attention", category: "LLMs",
                                definition: "How a model weighs which parts of its input matter for each output token.")
        attention.isMarkedKnown = true
        attention.masteryLevel = 1.0
        let interp = Concept(name: "Interpretability", category: "LLMs",
                             definition: "Techniques for understanding why a model produced an output.")
        interp.masteryLevel = 0.6
        let circuits = Concept(name: "Circuit tracing", category: "LLMs",
                               definition: "Mapping the internal pathways a model uses for a behavior.")
        context.insert(attention)
        context.insert(interp)
        context.insert(circuits)

        let article = Article(
            guid: "preview-1",
            title: "Interpretability at scale: tracing circuits in production models",
            content: "Interpretability research has long promised a microscope for neural networks…",
            publishedAt: .now.addingTimeInterval(-1680),
            sourceName: "Anthropic"
        )
        article.summary = "New tooling maps attention circuits across full model depth, making behavior audits practical for deployed systems."
        article.concepts = [interp, circuits, attention]
        context.insert(article)

        context.insert(ConceptLink(conceptA: "Attention", conceptB: "Interpretability"))
        context.insert(LearningEvent(kind: "read", conceptName: "Interpretability", masteryDelta: 0.1))
        try? context.save()
        return container
    }()
}
