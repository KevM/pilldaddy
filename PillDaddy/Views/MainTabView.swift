import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }.tag(0)
            MedsView()
                .tabItem { Label("Meds", systemImage: "pills") }.tag(1)
            PlaceholderTab(title: "Reports", systemImage: "chart.bar")
                .tabItem { Label("Reports", systemImage: "chart.bar") }.tag(2)
            HealthView()
                .tabItem { Label("Health", systemImage: "heart") }.tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }.tag(4)
        }
        .onChange(of: router.pendingBatchUUID) { _, uuid in
            if uuid != nil { selection = 0 }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle)
            Text(title).font(.title2)
            Text("Coming soon").foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppRouter())
        .environment(ReminderSettings())
        .modelContainer(PreviewSupport.seededContainer())
}

