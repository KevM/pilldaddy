import SwiftUI
import SwiftData

/// Active routines grouped under color routines, with a trailing PRN section.
struct RoutinesView: View {
    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var routines: [Routine]
    @Query(filter: #Predicate<Medication> { $0.isActive && $0.isPRN }, sort: \Medication.name)
    private var prnMeds: [Medication]

    @State private var editingRoutine: Routine?

    var body: some View {
        List {
            ForEach(routines) { routine in
                Section {
                    let items = activeItems(routine)
                    if items.isEmpty {
                        Text("No active medications")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            NavigationLink {
                                if let med = item.medication {
                                    MedicationDetailView(medication: med)
                                }
                            } label: {
                                row(item)
                            }
                        }
                    }
                } header: {
                    header(routine)
                }
            }

            if !prnMeds.isEmpty {
                Section("As needed (PRN)") {
                    ForEach(prnMeds) { med in
                        NavigationLink {
                            MedicationDetailView(medication: med)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(med.name)
                                Text(med.strengthDescription).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editingRoutine) { RoutineEditor(routine: $0) }
    }

    private func header(_ routine: Routine) -> some View {
        HStack {
            Circle().fill(Color(hex: routine.colorHex)).frame(width: 12, height: 12)
            Text(routine.name.isEmpty ? "Routine" : routine.name)
            Text(routine.timeOfDay, style: .time)
            Spacer()
            Button("Edit") { editingRoutine = routine }.font(.caption)
        }
    }

    private func row(_ item: RoutineItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.medication?.name ?? "—")
                Text(item.medication?.strengthDescription ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                if let med = item.medication { DoseAllocationBadge(medication: med) }
            }
            Spacer()
            Text("\(DoseFormat.qty(item.quantity)) \(item.medication?.form ?? "")")
                .foregroundStyle(.secondary)
        }
    }

    private func activeItems(_ routine: Routine) -> [RoutineItem] {
        (routine.items ?? [])
            .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
            .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
    }
}

#if DEBUG
#Preview {
    NavigationStack { RoutinesView() }
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
