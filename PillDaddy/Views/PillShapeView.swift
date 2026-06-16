import SwiftUI

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PillShapeView: View {
    let shapeName: String?
    let colorHex: String?
    let size: CGFloat
    
    var body: some View {
        let shape = PillShape(from: shapeName)
        let color = Color(hex: colorHex ?? "#94A3B8")
        
        ZStack {
            switch shape {
            case .round:
                Circle()
                    .fill(color)
                    .frame(width: size * 0.75, height: size * 0.75)
            case .capsule:
                Capsule()
                    .fill(color)
                    .frame(width: size * 0.4, height: size * 0.85)
            case .oval:
                Ellipse()
                    .fill(color)
                    .frame(width: size * 0.55, height: size * 0.85)
            case .tablet:
                RoundedRectangle(cornerRadius: size * 0.12)
                    .fill(color)
                    .frame(width: size * 0.7, height: size * 0.7)
            case .diamond:
                Rectangle()
                    .fill(color)
                    .rotationEffect(Angle(degrees: 45))
                    .frame(width: size * 0.5, height: size * 0.5)
            case .triangle:
                Triangle()
                    .fill(color)
                    .frame(width: size * 0.7, height: size * 0.7)
            }
        }
        .frame(width: size, height: size)
    }
}
