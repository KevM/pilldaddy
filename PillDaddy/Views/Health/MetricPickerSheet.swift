import SwiftUI

/// The "+" chooser: Water, Weight, or Vitals. Water/Weight route to Scalar; Vitals to Vitals.
enum MetricCaptureRoute: Identifiable {
    case scalar(MetricKind)
    case vitals
    var id: String { switch self { case .scalar(let k): k.rawValue; case .vitals: "vitals" } }
}

struct MetricPickerSheet: View {
    let onPick: (MetricCaptureRoute) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row("Water", "drop", .scalar(.water))
                row("Weight", "scalemass", .scalar(.weight))
                row("Vitals", "heart", .vitals, subtitle: "BP · pulse · SpO₂")
            }
            .navigationTitle("New reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func row(_ title: String, _ symbol: String, _ route: MetricCaptureRoute,
                     subtitle: String? = nil) -> some View {
        Button { dismiss(); onPick(route) } label: {
            HStack {
                Image(systemName: symbol).frame(width: 28)
                VStack(alignment: .leading) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }
}
