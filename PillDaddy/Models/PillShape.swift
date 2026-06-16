import Foundation

enum PillShape: String, CaseIterable, Identifiable {
    case round = "Round"
    case capsule = "Capsule"
    case oval = "Oval"
    case tablet = "Tablet"
    case diamond = "Diamond"
    case triangle = "Triangle"
    
    var id: String { self.rawValue }
    
    init(from string: String?) {
        guard let s = string?.lowercased() else {
            self = .round
            return
        }
        if s.contains("capsule") {
            self = .capsule
        } else if s.contains("oval") {
            self = .oval
        } else if s.contains("diamond") {
            self = .diamond
        } else if s.contains("triangle") {
            self = .triangle
        } else if s.contains("rectangle") || s.contains("tablet") {
            self = .tablet
        } else {
            self = .round
        }
    }
}
