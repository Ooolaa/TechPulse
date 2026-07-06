import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Feed", systemImage: "list.bullet") {
                FeedView()
            }
            Tab("Knowledge", systemImage: "point.3.connected.trianglepath.dotted") {
                KnowledgeMapView()
            }
            Tab("Progress", systemImage: "chart.bar.fill") {
                ProgressTabView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(Theme.stateLearning)
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
