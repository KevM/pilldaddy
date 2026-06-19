import SwiftUI
import SwiftData

/// Create or edit a batch: name, color, time, meal relation, recurrence, and the
/// pills it contains. (The README's "color manager".)
struct BatchEditor: View {
    /// nil = creating a new batch.
    let batch: Batch?

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Batch") {
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

                if let batch {
                    Section("Pills in this batch") {
                        ForEach(batch.items ?? []) { item in
                            HStack {
                                Text(item.medication?.name ?? "—")
                                Spacer()
                                Text("\(DoseFormat.qty(item.quantity)) \(item.medication?.form ?? "")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let items = batch.items ?? []
                            for index in offsets { context.delete(items[index]) }
                            try? context.save()
                        }
                        Menu("Add medication") {
                            ForEach(addableMeds(to: batch)) { med in
                                Button(med.name) {
                                    context.insert(BatchItem(quantity: 1.0, medication: med, batch: batch))
                                    try? context.save()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(batch == nil ? "New batch" : "Edit batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear(perform: load)
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

    private func addableMeds(to batch: Batch) -> [Medication] {
        let present = Set((batch.items ?? []).compactMap { $0.medication?.persistentModelID })
        return meds.filter { !present.contains($0.persistentModelID) }
    }

    private func load() {
        guard let batch else { return }
        name = batch.name
        colorHex = batch.colorHex
        time = batch.timeOfDay
        meal = MealRelation(rawValue: batch.mealRelation) ?? .none
        recurrence = RecurrenceKind(rawValue: batch.recurrenceKind) ?? .daily
        weekdays = Set(batch.weekdays ?? [])
    }

    private func save() {
        let target = batch ?? Batch()
        if batch == nil { context.insert(target) }
        target.name = name
        target.colorHex = colorHex
        target.timeOfDay = time
        target.mealRelation = meal.rawValue
        target.recurrenceKind = recurrence.rawValue
        target.weekdays = recurrence == .weekdays ? weekdays.sorted() : nil
        try? context.save()
        dismiss()
    }
}

#if DEBUG
#Preview {
    BatchEditor(batch: nil)
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
