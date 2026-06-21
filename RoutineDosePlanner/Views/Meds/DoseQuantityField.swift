import SwiftUI

/// Pure parsing for manual dose entry: a positive decimal or nil.
enum DoseQuantityParsing {
    static func value(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let v = Double(trimmed), v > 0 else { return nil }
        return v
    }
}

/// A dose-quantity input. Stepper by default (0.5 nudges) with an `Exact`
/// disclosure that swaps to a typed decimal field for arbitrary fractions.
/// `max`, when set, is a soft cap: typing above it shows a warning (the parent
/// owns whether Save is blocked).
struct DoseQuantityField: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0.5...20
    var step: Double = 0.5
    var max: Double? = nil

    @State private var manual = false
    @State private var text = ""

    private var exceedsCap: Bool {
        if let max { return value > max + 0.0001 }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if manual {
                    Text(title)
                    TextField("Amount", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: text) { _, new in
                            if let v = DoseQuantityParsing.value(from: new) { value = v }
                        }
                    Button { manual = false } label: {
                        Label("Steps", systemImage: "chevron.left")
                            .labelStyle(.titleOnly).font(.caption)
                    }
                } else {
                    Stepper(value: $value, in: range, step: step) {
                        Text("\(title): \(DoseFormat.qty(value))")
                    }
                    Button { text = DoseFormat.qty(value); manual = true } label: {
                        Label("Exact", systemImage: "chevron.right")
                            .labelStyle(.titleOnly).font(.caption)
                    }
                }
            }
            if exceedsCap, let max {
                Text("Exceeds daily dose (\(DoseFormat.qty(max)) available)")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }
}
