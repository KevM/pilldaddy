import SwiftUI

extension MetricCue {
    var color: Color {
        switch self {
        case .normal: .green
        case .caution: .orange
        case .alert: .red
        }
    }
}
