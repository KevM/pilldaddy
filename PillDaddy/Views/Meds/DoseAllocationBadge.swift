import SwiftUI

/// Amber caution shown when a scheduled med's allocation does not match its
/// daily-dose target. Renders nothing for PRN / discontinued / fully-allocated meds.
struct DoseAllocationBadge: View {
    let medication: Medication
    var showCaption: Bool = false

    var body: some View {
        if DoseAllocation.needsAttention(medication) {
            VStack(alignment: .leading, spacing: 2) {
                Label(label, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                if showCaption {
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var label: String {
        switch DoseAllocation.status(medication) {
        case .under: return "Under daily dose"
        case .over:  return "Over daily dose"
        case .full:  return ""
        }
    }

    private var caption: String {
        let allocated = DoseAllocation.allocated(medication)
        let target = medication.dailyDoseTarget
        let unit = medication.strengthUnit
        return "\(DoseFormat.qty(allocated)) of \(DoseFormat.qty(target)) \(medication.form)/day · \(DoseFormat.qty(allocated * medication.strengthValue)) of \(DoseFormat.qty(target * medication.strengthValue)) \(unit)"
    }
}
