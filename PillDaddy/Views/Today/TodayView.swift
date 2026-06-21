import SwiftUI
import SwiftData

/// The Today tab: a day's dose-logging checklist.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(ReminderSettings.self) private var settings

    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var batches: [Batch]
    @Query(filter: #Predicate<Medication> { $0.isActive && $0.isPRN }, sort: \Medication.name)
    private var prnMeds: [Medication]
    @State private var selectedDay = Date.now
    @State private var expandedID: PersistentIdentifier?
    @State private var prnExpanded = false

    @State private var takingBatch: DayQuery.BatchDay?
    @State private var adjustingBatch: DayQuery.BatchDay?

    private var batchDays: [DayQuery.BatchDay] {
        return DayQuery.batchDays(from: batches, on: selectedDay)
    }
    private var prnDoses: [DayQuery.PRNDose] {
        return DayQuery.prnDoses(from: prnMeds, on: selectedDay)
    }
    private var isToday: Bool { Calendar.current.isDate(selectedDay, inSameDayAs: .now) }
    private var doneCount: Int { batchDays.filter { $0.isCompleted }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    dayStepper
                    Text("\(doneCount) of \(batchDays.count) batches done")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(batchDays) { day in
                        BatchLogCard(
                            batchDay: day,
                            isExpanded: expandedID == day.id,
                            onToggle: { toggle(day) },
                            onMarkAllTaken: { takingBatch = day },
                            onAdjust: { adjustingBatch = day },
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
            .sheet(item: $takingBatch) { BatchTakenConfirmSheet(batchDay: $0, day: selectedDay) }
            .sheet(item: $adjustingBatch) { IndividualAdjustSheet(batchDay: $0, day: selectedDay) }
            .onAppear(perform: autoExpand)
            .onAppear { focusFromRouter() }
            .onChange(of: selectedDay) { _, _ in autoExpand() }
            .onChange(of: router.pendingBatchUUID) { _, _ in focusFromRouter() }
            .onChange(of: batchDays.map { $0.state }) { _, _ in
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

    private func toggle(_ day: DayQuery.BatchDay) {
        expandedID = (expandedID == day.id) ? nil : day.id
    }

    private func revert(_ day: DayQuery.BatchDay) {
        DoseLogService.revertBatch(day.batch, on: selectedDay, items: day.meds.map(\.item), in: context)
    }

    /// On today, expand the batch whose slot time is closest to now and not yet fully
    /// taken; otherwise expand nothing.
    private func autoExpand() {
        guard isToday else { expandedID = nil; return }
        let now = Date.now
        expandedID = batchDays
            .filter { !$0.isCompleted }
            .min { abs($0.slotDate.timeIntervalSince(now)) < abs($1.slotDate.timeIntervalSince(now)) }?
            .id
    }

    /// Honor a deep link: jump to today and expand the requested batch.
    private func focusFromRouter() {
        guard let uuid = router.pendingBatchUUID else { return }
        if let batch = batches.first(where: { $0.uuid.uuidString == uuid }) {
            selectedDay = .now
            expandedID = batch.persistentModelID
        }
        router.pendingBatchUUID = nil
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
