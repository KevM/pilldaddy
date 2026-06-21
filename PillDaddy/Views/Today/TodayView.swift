import SwiftUI
import SwiftData

/// The Today tab: a day's dose-logging checklist.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(ReminderSettings.self) private var settings

    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var routines: [Routine]
    @Query(filter: #Predicate<Medication> { $0.isActive && $0.isPRN }, sort: \Medication.name)
    private var prnMeds: [Medication]
    @State private var selectedDay = Date.now
    @State private var expandedID: PersistentIdentifier?
    @State private var prnExpanded = false

    @State private var takingRoutine: DayQuery.RoutineDay?
    @State private var adjustingRoutine: DayQuery.RoutineDay?

    private var routineDays: [DayQuery.RoutineDay] {
        return DayQuery.routineDays(from: routines, on: selectedDay)
    }
    private var prnDoses: [DayQuery.PRNDose] {
        return DayQuery.prnDoses(from: prnMeds, on: selectedDay)
    }
    private var isToday: Bool { Calendar.current.isDate(selectedDay, inSameDayAs: .now) }
    private var doneCount: Int { routineDays.filter { $0.isCompleted }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    dayStepper
                    Text("\(doneCount) of \(routineDays.count) routines done")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(routineDays) { day in
                        RoutineLogCard(
                            routineDay: day,
                            isExpanded: expandedID == day.id,
                            onToggle: { toggle(day) },
                            onMarkAllTaken: { takingRoutine = day },
                            onAdjust: { adjustingRoutine = day },
                            onRevert: { revert(day) })
                    }

                    if !prnDoses.isEmpty {
                        PRNCard(doses: prnDoses, day: selectedDay, isExpanded: prnExpanded,
                                onToggle: { prnExpanded.toggle() })
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .sheet(item: $takingRoutine) { RoutineTakenConfirmSheet(routineDay: $0, day: selectedDay) }
            .sheet(item: $adjustingRoutine) { IndividualAdjustSheet(routineDay: $0, day: selectedDay) }
            .onAppear(perform: autoExpand)
            .onAppear { focusFromRouter() }
            .onChange(of: selectedDay) { _, _ in autoExpand() }
            .onChange(of: router.pendingRoutineUUID) { _, _ in focusFromRouter() }
            .onChange(of: routineDays.map { $0.state }) { _, _ in
                autoExpand()
                ReminderSync.refresh(context: context, settings: settings)
            }
        }
    }

    private var dayStepper: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(selectedDay, format: .dateTime.weekday().month().day())
                .font(.headline)
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(isToday)
        }
    }

    private func step(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) {
            // never step into the future
            if days > 0 && Calendar.current.startOfDay(for: d) > Calendar.current.startOfDay(for: .now) { return }
            selectedDay = d
        }
    }

    private func toggle(_ day: DayQuery.RoutineDay) {
        expandedID = (expandedID == day.id) ? nil : day.id
    }

    private func revert(_ day: DayQuery.RoutineDay) {
        DoseLogService.revertRoutine(day.routine, on: selectedDay, items: day.meds.map(\.item), in: context)
    }

    /// On today, expand the routine whose slot time is closest to now and not yet fully
    /// taken; otherwise expand nothing.
    private func autoExpand() {
        guard isToday else { expandedID = nil; return }
        let now = Date.now
        expandedID = routineDays
            .filter { !$0.isCompleted }
            .min { abs($0.slotDate.timeIntervalSince(now)) < abs($1.slotDate.timeIntervalSince(now)) }?
            .id
    }

    /// Honor a deep link: jump to today and expand the requested routine.
    private func focusFromRouter() {
        guard let uuid = router.pendingRoutineUUID else { return }
        if let routine = routines.first(where: { $0.uuid.uuidString == uuid }) {
            selectedDay = .now
            expandedID = routine.persistentModelID
        }
        router.pendingRoutineUUID = nil
    }
}

#if DEBUG
#Preview {
    TodayView()
        .environment(AppRouter())
        .environment(ReminderSettings())
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
