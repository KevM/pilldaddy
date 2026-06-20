import SwiftUI
import SwiftData

/// Capture for Weight and Water. Number + live cue color; Water adds quick-add
/// chips, a custom-amount entry, and a running daily total; Weight shows Δ vs prior.
struct ScalarCaptureView: View {
    let kind: MetricKind
    let writer: HealthKitWriting
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    @State private var value: Double = 0
    @State private var customAmount: Double = 0
    @State private var note = ""
    @State private var ctx: CueContext = .empty

    private var def: MetricDefinition { MetricRegistry.definition(for: kind) }
    private var cue: MetricCue { def.cue(value, nil, ctx) }
    private var canSave: Bool { def.plausibleRange.contains(value) && (kind != .water || value > 0) }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MetricFormatter.string(value, unit: def.unit))
                        .font(.system(size: 40, weight: .medium))
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
                .accessibilityLabel("\(MetricFormatter.string(value, unit: def.unit)) - status: \(cue.label)")

                if kind == .weight, let prev = ctx.previousValue {
                    Text(deltaText(from: prev)).font(.footnote).foregroundStyle(cue.color)
                }
                if kind == .water, let total = ctx.todayTotal {
                    Text("\(Int(total + value)) oz today")
                        .font(.footnote).foregroundStyle(cue.color)
                }
            }

            if let chips = def.quickAdd {
                Section("Quick add") {
                    HStack {
                        ForEach(chips, id: \.self) { amt in
                            Button("+\(Int(amt))") { value += amt }
                                .buttonStyle(.bordered)
                        }
                    }
                    if def.customAddDefault != nil {
                        HStack {
                            Image(systemName: "pencil")
                            TextField("Custom", value: $customAmount, format: .number)
                                .keyboardType(.numberPad)
                            Text(def.unit).foregroundStyle(.secondary)
                            Button("Add") { value += customAmount }.buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                Section {
                    TextField("Value", value: $value, format: .number)
                        .keyboardType(.decimalPad)
                }
            }

            Section("Note") { TextField("Add a note", text: $note, axis: .vertical) }
        }
        .navigationTitle(def.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onClose() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!canSave)
            }
        }
        .onAppear {
            ctx = HealthMetricService.cueContext(for: kind, in: context)
            customAmount = def.customAddDefault ?? 0
        }
    }

    private func deltaText(from prev: Double) -> String {
        let d = value - prev
        let arrow = d >= 0 ? "▲" : "▼"
        return "\(arrow) \(MetricFormatter.string(abs(d), unit: def.unit)) since last"
    }

    private func save() {
        let v = value, n = note
        Task {
            try? await HealthMetricService.recordScalar(kind: kind, value: v, note: n,
                                                        writer: writer, in: context)
        }
        onClose()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ScalarCaptureView(kind: .water, writer: LiveHealthKitWriter(), onClose: {})
            .modelContainer(PreviewSupport.seededContainer())
    }
}
#endif
