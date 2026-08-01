import SwiftUI
import SwiftData

struct RootTabView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Query(filter: #Predicate<Article> { !$0.isRead }) private var unreadArticles: [Article]
    /// Widget deep links land here; matches the `techpulse://` host.
    @State private var selectedTab = "feed"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Feed", systemImage: "list.bullet", value: "feed") {
                FeedView()
            }
            .badge(unreadArticles.isEmpty ? 0 : unreadArticles.count)
            Tab("Knowledge", systemImage: "point.3.connected.trianglepath.dotted", value: "knowledge") {
                KnowledgeMapView()
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: "progress") {
                ProgressTabView()
            }
            Tab("Settings", systemImage: "gearshape", value: "settings") {
                SettingsView()
            }
        }
        .tint(Theme.stateLearning)
        .onOpenURL { url in
            guard url.scheme == "techpulse", let host = url.host() else { return }
            if ["feed", "knowledge", "progress", "settings"].contains(host) {
                selectedTab = host
            }
        }
        .fullScreenCover(isPresented: .constant(!hasOnboarded)) {
            OnboardingView()
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
