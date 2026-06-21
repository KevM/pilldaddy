import SwiftUI
import SwiftData

/// Create or edit a routine: name, color, time, meal relation, recurrence, and the
/// pills it contains. (The README's "color manager".)
struct BatchEditor: View {
    /// nil = creating a new routine.
    let routine: Routine?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Medication> { $0.isActive && !$0.isPRN }, sort: \Medication.name)
    private var meds: [Medication]

    static let palette = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444",
                          "#A855F7", "#06B6D4", "#EC4899", "#84CC16"]
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"] // index 0 = Sunday (weekday 1)

    @State private var name = ""
    @State private var colorHex = "#3B82F6"
    @State private var time = Date.now
    @State private var meal = MealRelation.none
    @State private var recurrence = RecurrenceKind.daily
    @State private var weekdays: Set<Int> = []

    @State private var addingMed: Medication?
    @State private var addQuantity = 1.0
    @State private var editingMed: Medication?
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Name", text: $name)
                    colorRow
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Meal", selection: $meal) {
                        ForEach(MealRelation.allCases) { relation in
                            Text(mealLabel(relation)).tag(relation)
                        }
                    }
                    Picker("Repeats", selection: $recurrence) {
                        Text("Daily").tag(RecurrenceKind.daily)
                        Text("Weekdays").tag(RecurrenceKind.weekdays)
                    }
                    if recurrence == .weekdays { weekdayRow }
                }

                if let routine {
                    Section("Pills in this routine") {
                        ForEach(activeItems) { item in
                            Button {
                                editingMed = item.medication
                            } label: {
                                HStack {
                                    Text(item.medication?.name ?? "—")
                                    Spacer()
                                    Text("\(DoseFormat.qty(item.quantity)) \(item.medication?.form ?? "")")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                do {
                                    try MedicationService.removeFromBatch(activeItems[index], in: context)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        Menu("Add medication") {
                            ForEach(addableMeds(to: routine)) { med in
                                Button(med.name) {
                                    addingMed = med
                                    addQuantity = min(1.0, max(0.5, DoseAllocation.remaining(med)))
                                }
                                .disabled(DoseAllocation.remaining(med) <= 0)
                            }
                        }
                    }
                    Section {
                        Button("Delete routine", role: .destructive) { confirmingDelete = true }
                            .disabled(!activeItems.isEmpty)
                        if !activeItems.isEmpty {
                            Text("Remove the \(activeItems.count) active medication(s) before deleting.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(routine == nil ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear(perform: load)
            .sheet(item: $addingMed) { med in
                NavigationStack {
                    Form {
                        DoseQuantityField(
                            title: "Quantity", value: $addQuantity,
                            range: 0.5...20, step: 0.5,
                            max: DoseAllocation.remaining(med))
                        Text("\(DoseFormat.qty(DoseAllocation.remaining(med))) of \(DoseFormat.qty(med.dailyDoseTarget))/day remaining")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .navigationTitle("Add \(med.name)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { addingMed = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                do {
                                    if let routine {
                                        try MedicationService.addToBatch(med, routine, quantity: addQuantity, in: context)
                                    }
                                    addingMed = nil
                                } catch {
                                    errorMessage = errorMessage(for: error)
                                }
                            }
                            .disabled(DoseAllocation.isOverTarget(allocated: DoseAllocation.allocated(med) + addQuantity, target: med.dailyDoseTarget))
                        }
                    }
                    .alert("Cannot Add", isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    )) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        if let errorMessage {
                            Text(errorMessage)
                        }
                    }
                }
            }
            .sheet(item: $editingMed) { med in
                ChangeDoseSheet(medication: med)
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil && addingMed == nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .alert("Delete this routine?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    if let routine {
                        do {
                            try MedicationService.deleteBatch(routine, in: context)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Self.palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(Color.primary, lineWidth: colorHex == hex ? 3 : 0))
                        .onTapGesture { colorHex = hex }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                let on = weekdays.contains(day)
                Text(weekdaySymbols[day - 1])
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.2))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .clipShape(Circle())
                    .onTapGesture {
                        if on { weekdays.remove(day) } else { weekdays.insert(day) }
                    }
            }
        }
    }

    private func mealLabel(_ relation: MealRelation) -> String {
        switch relation {
        case .none: return "None"
        case .withFood: return "With food"
        case .beforeFood: return "Before food"
        case .afterFood: return "After food"
        }
    }

    private var activeItems: [RoutineItem] {
        guard let routine else { return [] }
        return (routine.items ?? []).filter { $0.medication?.isActive == true }
    }

    private func addableMeds(to routine: Routine) -> [Medication] {
        let present = Set(activeItems.compactMap { $0.medication?.persistentModelID })
        return meds.filter { !present.contains($0.persistentModelID) }
    }

    private func load() {
        guard let routine else { return }
        name = routine.name
        colorHex = routine.colorHex
        time = routine.timeOfDay
        meal = MealRelation(rawValue: routine.mealRelation) ?? .none
        recurrence = RecurrenceKind(rawValue: routine.recurrenceKind) ?? .daily
        weekdays = Set(routine.weekdays ?? [])
    }

    private func save() {
        let target = routine ?? Routine()
        if routine == nil { context.insert(target) }
        target.name = name
        target.colorHex = colorHex
        target.timeOfDay = time
        target.mealRelation = meal.rawValue
        target.recurrenceKind = recurrence.rawValue
        target.weekdays = recurrence == .weekdays ? weekdays.sorted() : nil
        try? context.save()
        dismiss()
    }

    private func errorMessage(for error: Error) -> String {
        if let doseError = error as? DoseAllocationError {
            switch doseError {
            case .exceedsDailyTarget:
                return "Total allocation across batches cannot exceed the daily dose target."
            }
        }
        return error.localizedDescription
    }
}

#if DEBUG
#Preview {
    BatchEditor(routine: nil)
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
