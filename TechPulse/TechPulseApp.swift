import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct TechPulseApp: App {
    static let refreshTaskID = "com.johnchen.TechPulse.refresh"

    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: FeedSource.self, Article.self, Concept.self,
                LearningEvent.self, ConceptLink.self, ConceptDependency.self,
                SemanticLink.self, InstalledPack.self
            )
            SeedData.seedIfNeeded(context: container.mainContext)
            KnowledgeEngine.applyTimeDecay(context: container.mainContext)
            // Seed the widget on first launch, and let decay/day-rollover land
            // in it without waiting for the next read.
            WidgetRefresh.refresh(context: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        let container = self.container
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            Self.scheduleAppRefresh()
            let syncTask = Task { @MainActor in
                await FeedSyncService.syncAll(context: container.mainContext)
                // Spec §5: batch analysis in BackgroundTasks windows to save battery.
                await IntelligenceService.analyzePending(context: container.mainContext)
                // New articles can change "your next dot"; keep the widget honest.
                WidgetRefresh.refresh(context: container.mainContext)
                refresh.setTaskCompleted(success: true)
            }
            refresh.expirationHandler = { syncTask.cancel() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Self.scheduleAppRefresh() }
        }
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(3600)   // ≥1 h; iOS decides exact timing
        try? BGTaskScheduler.shared.submit(request)
    }
}
