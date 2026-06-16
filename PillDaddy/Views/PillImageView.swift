import SwiftUI

struct PillImageView: View {
    let imageUrlString: String?
    let defaultColorHex: String?
    let shapeName: String?
    let size: CGFloat
    
    var body: some View {
        if let urlString = imageUrlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure(_):
                    fallbackView
                case .empty:
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.05))
                        ProgressView()
                            .tint(.white.opacity(0.3))
                    }
                @unknown default:
                    fallbackView
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        } else {
            fallbackView
        }
    }
    
    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: size, height: size)
            
            PillShapeView(shapeName: shapeName, colorHex: defaultColorHex, size: size)
                .shadow(color: Color(hex: defaultColorHex ?? "#94A3B8").opacity(0.35), radius: size * 0.1)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
