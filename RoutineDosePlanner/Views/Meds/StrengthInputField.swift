import SwiftUI

/// A reusable row input for entering a medication's strength value and unit.
/// Displays a label on the left, and groups the value and unit inputs tightly on the right.
struct StrengthInputField: View {
    var title: String = "Strength"
    @Binding var value: Double
    @Binding var unit: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 4) {
                TextField("500", value: $value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                TextField("mg", text: $unit)
                    .multilineTextAlignment(.leading)
                    .frame(width: 50)
            }
        }
    }
}

#if DEBUG
#Preview {
    Form {
        StrengthInputField(value: .constant(500.0), unit: .constant("mg"))
    }
}
#endif
