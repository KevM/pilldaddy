import SwiftUI
import SwiftData

/// One screen for BP + Pulse + SpO₂. Every field optional; only present values are
/// written. BP is both-or-neither. Each value carries its live cue color.
struct VitalsCaptureView: View {
    let writer: HealthKitWriting
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    @State private var systolic: Double?
    @State private var diastolic: Double?
    @State private var pulse: Double?
    @State private var spo2: Double?
    @State private var note = ""

    private var bpIncomplete: Bool { (systolic == nil) != (diastolic == nil) }
    private var hasAny: Bool { systolic != nil || diastolic != nil || pulse != nil || spo2 != nil }
    private var canSave: Bool { hasAny && !bpIncomplete }

    var body: some View {
        Form {
            Section("Blood pressure (mmHg)") {
                HStack {
                    numberField("Systolic", $systolic)
                    Text("/").foregroundStyle(.secondary)
                    numberField("Diastolic", $diastolic)
                }
                if let s = systolic, let d = diastolic {
                    let cue = MetricRegistry.definition(for: .bloodPressure).cue(s, d, .empty)
                    HStack(spacing: 8) {
                        Text(MetricFormatter.bloodPressure(s, d))
                            .foregroundStyle(cue.color)
                        Text(cue.label)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(cue.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(cue.color.opacity(0.1), in: Capsule())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Blood pressure status: \(cue.label)")
                }
                if bpIncomplete {
                    Text("Enter both systolic and diastolic.")
                        .font(.footnote).foregroundStyle(.red)
                }
                HealthPermissionNotice(kind: .bloodPressure, writer: writer)
            }
            Section("Pulse (bpm)") {
                cuedField("Pulse", $pulse, kind: .pulse)
                HealthPermissionNotice(kind: .pulse, writer: writer)
            }
            Section("Oxygen (SpO₂ %)") {
                cuedField("SpO₂", $spo2, kind: .oxygenSaturation)
                HealthPermissionNotice(kind: .oxygenSaturation, writer: writer)
            }
            Section("Note") { TextField("Add a note", text: $note, axis: .vertical) }
        }
        .navigationTitle("Vitals")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onClose() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!canSave)
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
                let cue = MetricRegistry.definition(for: kind).cue(v, nil, .empty)
                HStack(spacing: 4) {
                    Circle()
                        .fill(cue.color)
                        .frame(width: 10, height: 10)
                    Text(cue.label)
                        .font(.caption)
                        .foregroundStyle(cue.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label) status: \(cue.label)")
            }
        }
    }

    private func save() {
        let s = systolic, d = diastolic, p = pulse, o = spo2, n = note
        Task {
            try? await HealthMetricService.recordVitals(systolic: s, diastolic: d, pulse: p,
                                                        spo2: o, note: n, writer: writer, in: context)
            await MainActor.run {
                onClose()
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VitalsCaptureView(writer: LiveHealthKitWriter(), onClose: {})
            .modelContainer(PreviewSupport.seededContainer())
    }
}
#endif
