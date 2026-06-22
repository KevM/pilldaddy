import SwiftUI

/// Always shows the prescribed dose target for a scheduled med; appends an amber
/// caution line when the scheduled allocation does not match the target. Renders
/// nothing for PRN meds.
struct DoseSummaryRow: View {
    let medication: Medication

    var body: some View {
        if !medication.isPRN {
            VStack(alignment: .leading, spacing: 2) {
                Text(DoseSummaryFormatter.summary(for: medication))
                    .font(.callout)
                if let mismatch = DoseSummaryFormatter.mismatch(for: medication) {
                    Label(mismatch, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
