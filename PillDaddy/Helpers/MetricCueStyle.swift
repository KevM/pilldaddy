import SwiftUI

extension MetricCue {
    var color: Color {
        switch self {
        case .normal: .green
        case .caution: .orange
        case .alert: .red
        }
    }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .caution: "Caution"
        case .alert: "Alert"
        }
    }
}
