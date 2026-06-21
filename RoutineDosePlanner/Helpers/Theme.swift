import SwiftUI

struct Theme {
    static let backgroundGradient = LinearGradient(
        colors: [Color(hex: "#0F172A"), Color(hex: "#1E293B")], // Slate-900 to Slate-800
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "#38BDF8"), Color(hex: "#818CF8")], // Celestial cyan to violet
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let cardBackground = Color(hex: "#1E293B").opacity(0.75)
    static let cardBorder = Color.white.opacity(0.08)
    
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "#94A3B8")
    
    static let successColor = Color(hex: "#10B981") // Emerald Green
    static let dangerColor = Color(hex: "#EF4444") // Soft Red
    static let warningColor = Color(hex: "#F59E0B") // Amber
}

struct GlassmorphicCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func glassmorphicCard() -> some View {
        self.modifier(GlassmorphicCardModifier())
    }
}
