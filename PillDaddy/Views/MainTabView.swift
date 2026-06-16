import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    init() {
        // Translucent background configuration for the tab bar
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(Color(hex: "#0F172A").opacity(0.92))
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.06)
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            RegimeView()
                .tabItem {
                    Label("Regime", systemImage: "clock.badge.checkmark.fill")
                }
                .tag(0)
            
            PillManagerView()
                .tabItem {
                    Label("Cabinet", systemImage: "pills.fill")
                }
                .tag(1)
            
            ReportsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }
                .tag(2)
        }
        .tint(Color(hex: "#38BDF8")) // Cyan active tab tint
    }
}
