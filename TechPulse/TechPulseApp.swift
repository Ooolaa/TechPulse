import SwiftUI
import SwiftData

@main
struct TechPulseApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: FeedSource.self, Article.self, Concept.self,
                LearningEvent.self, ConceptLink.self
            )
            SeedData.seedIfNeeded(context: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
