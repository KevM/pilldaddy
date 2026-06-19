import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            PlaceholderTab(title: "Today", systemImage: "checklist")
                .tabItem { Label("Today", systemImage: "checklist") }
            MedsView()
                .tabItem { Label("Meds", systemImage: "pills") }
            PlaceholderTab(title: "Reports", systemImage: "chart.bar")
                .tabItem { Label("Reports", systemImage: "chart.bar") }
            PlaceholderTab(title: "Health", systemImage: "heart")
                .tabItem { Label("Health", systemImage: "heart") }
            PlaceholderTab(title: "Settings", systemImage: "gear")
                .tabItem { Label("Settings", systemImage: "gear") }
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
}
