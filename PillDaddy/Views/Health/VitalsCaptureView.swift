import SwiftUI
import SwiftData

/// One screen for BP + Pulse + SpO₂. Every field optional; only present values are
/// written. BP is both-or-neither. Each value carries its live cue color.
struct VitalsCaptureView: View {
    let writer: HealthKitWriting

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var systolic: Double?
    @State private var diastolic: Double?
    @State private var pulse: Double?
    @State private var spo2: Double?
    @State private var note = ""

    private var bpIncomplete: Bool { (systolic == nil) != (diastolic == nil) }
    private var hasAny: Bool { systolic != nil || diastolic != nil || pulse != nil || spo2 != nil }
    private var canSave: Bool { hasAny && !bpIncomplete }

    var body: some View {
        NavigationStack {
            Form {
                Section("Blood pressure (mmHg)") {
                    HStack {
                        numberField("Systolic", $systolic)
                        Text("/").foregroundStyle(.secondary)
                        numberField("Diastolic", $diastolic)
                    }
                    if let s = systolic, let d = diastolic {
                        Text(MetricFormatter.bloodPressure(s, d))
                            .foregroundStyle(MetricRegistry.definition(for: .bloodPressure).cue(s, d, .empty).color)
                    }
                    if bpIncomplete {
                        Text("Enter both systolic and diastolic.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("Pulse (bpm)") {
                    cuedField("Pulse", $pulse, kind: .pulse)
                }
                Section("Oxygen (SpO₂ %)") {
                    cuedField("SpO₂", $spo2, kind: .oxygenSaturation)
                }
                Section("Note") { TextField("Add a note", text: $note, axis: .vertical) }
            }
            .navigationTitle("Vitals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func numberField(_ label: String, _ binding: Binding<Double?>) -> some View {
        TextField(label, value: binding, format: .number).keyboardType(.numberPad)
    }

    @ViewBuilder
    private func cuedField(_ label: String, _ binding: Binding<Double?>, kind: MetricKind) -> some View {
        HStack {
            numberField(label, binding)
            if let v = binding.wrappedValue {
                Circle()
                    .fill(MetricRegistry.definition(for: kind).cue(v, nil, .empty).color)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func save() {
        let s = systolic, d = diastolic, p = pulse, o = spo2, n = note
        Task {
            try? await HealthMetricService.recordVitals(systolic: s, diastolic: d, pulse: p,
                                                        spo2: o, note: n, writer: writer, in: context)
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    VitalsCaptureView(writer: LiveHealthKitWriter())
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
