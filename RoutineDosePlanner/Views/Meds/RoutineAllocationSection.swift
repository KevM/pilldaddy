import SwiftUI
import SwiftData

/// Reusable per-routine allocation editor: a toggle + quantity row for every routine,
/// with a running "X of Y/day allocated" summary that turns red when over target.
/// Used by both the Add Medication editor and the Change Dose sheet.
struct RoutineAllocationSection: View {
    let title: String
    let routines: [Routine]
    @Binding var selected: Set<PersistentIdentifier>
    @Binding var quantities: [PersistentIdentifier: Double]
    let target: Double
    let strengthValue: Double
    let strengthUnit: String

    private var assignedTotal: Double {
        selected.reduce(0.0) { $0 + (quantities[$1] ?? 1.0) }
    }

    var body: some View {
        Section {
            if routines.isEmpty {
                Text("No routines yet — add one from the Meds tab.")
                    .foregroundStyle(.secondary)
            }
            ForEach(routines) { routine in
                routineAssignRow(routine)
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                let isOver = DoseAllocation.isOverTarget(allocated: assignedTotal, target: target)
                Text("\(DoseFormat.qty(assignedTotal)) of \(DoseFormat.qty(target))/day allocated (\(DoseFormat.qty(assignedTotal * strengthValue)) of \(DoseFormat.qty(target * strengthValue)) \(strengthUnit))")
                    .font(.caption)
                    .foregroundStyle(isOver ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private func routineAssignRow(_ routine: Routine) -> some View {
        let id = routine.persistentModelID
        let isOn = selected.contains(id)
        VStack(alignment: .leading) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { on in
                    if on {
                        selected.insert(id)
                        if let q = quantities[id], q > 0 {
                            // Keep existing positive quantity
                        } else {
                            quantities[id] = 1.0
                        }
                    } else {
                        selected.remove(id)
                    }
                })) {
                HStack {
                    Circle().fill(Color(hex: routine.colorHex)).frame(width: 12, height: 12)
                    Text(routine.name.isEmpty ? "Routine" : routine.name)
                    Spacer()
                    Text(routine.timeOfDay, style: .time)
                        .foregroundStyle(.secondary)
                }
            }
            if isOn {
                DoseQuantityField(
                    title: "Quantity",
                    value: Binding(
                        get: { quantities[id] ?? 1.0 },
                        set: { newValue in
                            if newValue <= 0 {
                                selected.remove(id)
                            } else {
                                quantities[id] = newValue
                            }
                        }),
                    range: 0...20, step: 0.5)
            }
        }
    }
}
