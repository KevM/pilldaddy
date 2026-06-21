import SwiftUI

/// The "+" chooser route: Water/Weight → Scalar; Vitals → Vitals. Hashable so it
/// can drive a NavigationStack push (navigationDestination/NavigationLink).
enum MetricCaptureRoute: Hashable {
    case scalar(MetricKind)
    case vitals
}

/// The add-reading flow: one sheet whose root is the metric picker and which pushes
/// the capture screen on selection (list slides off-stage, capture slides in).
/// Selection is committal — the back button is hidden; Cancel/Save close the sheet.
struct AddMetricFlow: View {
    let writer: HealthKitWriting
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
            .navigationDestination(for: MetricCaptureRoute.self) { route in
                switch route {
                case .scalar(let kind):
                    ScalarCaptureView(kind: kind, writer: writer, onClose: { dismiss() })
                case .vitals:
                    VitalsCaptureView(writer: writer, onClose: { dismiss() })
                }
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ route: MetricCaptureRoute,
                     subtitle: String? = nil) -> some View {
        NavigationLink(value: route) {
            HStack {
                Image(systemName: symbol).frame(width: 28)
                VStack(alignment: .leading) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
