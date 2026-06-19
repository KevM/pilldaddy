# Session 2 — Dose Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the stubbed **Today** tab into a working dose-logging checklist that writes `DoseLog` rows — batch-first with per-med override, ad-hoc PRN logging, back-fill of past days, and edit/revert.

**Architecture:** Mirror Session 1's split. A pure read helper (`DayQuery`) assembles a given day's batches/PRN meds with their existing logs and computed state; a mutation service (`DoseLogService`, a `@MainActor enum` of statics taking a `ModelContext`) owns all atomic upsert/fill/preserve rules so they're unit-testable. SwiftUI views under `Views/Today/` render `DayQuery` output (reactive via `@Query`) and call `DoseLogService`; they never hand-roll `DoseLog` mutations.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest, XcodeGen.

**Spec:** [2026-06-19-session-2-dose-logging-design.md](../specs/2026-06-19-session-2-dose-logging-design.md)

---

## Conventions used throughout this plan

- **Regenerate after adding files.** XcodeGen sources are folder-based (`sources: [PillDaddy]`, `[PillDaddyTests]`). After creating any new `.swift` file, run `xcodegen generate` before building so the new file is in the target.
- **Build command:**
  ```bash
  xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
  ```
- **Test command (one suite):**
  ```bash
  xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/<SuiteName> 2>&1 | tail -30
  ```
- **Full test command:**
  ```bash
  xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
  ```
- A "day" is any `Date`; calendar-day comparisons use `Calendar.current`. A scheduled `DoseLog`'s slot identity is `medication` + `batchItem` + same calendar day; its `scheduledDate` is that day combined with the batch's `timeOfDay` clock components.

---

## Task 1: `DayQuery` — recurrence, slot, day assembly

Pure helper (no `ModelContext` fetch — operates on already-fetched arrays so the same code is both reactive in views via `@Query` and trivially testable). Defines the value types the Today screen renders.

**Files:**
- Create: `PillDaddy/Services/DayQuery.swift`
- Test: `PillDaddyTests/DayQueryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PillDaddyTests/DayQueryTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class DayQueryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    private func fetchBatches() throws -> [Batch] {
        try context.fetch(FetchDescriptor<Batch>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timeOfDay)]))
    }

    func testDailyBatchRecursEveryDay() throws {
        let b = Batch(name: "Blue", recurrenceKind: .daily)
        context.insert(b)
        XCTAssertTrue(DayQuery.recurs(b, on: .now))
    }

    func testWeekdaysBatchOnlyRecursOnListedWeekdays() throws {
        let day = Date.now
        let wd = Calendar.current.component(.weekday, from: day)
        let exclude = Batch(name: "Wk", recurrenceKind: .weekdays,
                            weekdays: [1,2,3,4,5,6,7].filter { $0 != wd })
        let include = Batch(name: "Wk2", recurrenceKind: .weekdays, weekdays: [wd])
        context.insert(exclude); context.insert(include)
        XCTAssertFalse(DayQuery.recurs(exclude, on: day))
        XCTAssertTrue(DayQuery.recurs(include, on: day))
    }

    func testBatchDaysExcludeDiscontinuedAndPRNAndEmptyBatches() throws {
        let blue = Batch(name: "Blue", sortOrder: 0)
        let empty = Batch(name: "Empty", sortOrder: 1)
        context.insert(blue); context.insert(empty)

        let active = MedicationService.addMedication(
            name: "Active", strength: "10mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        _ = active
        let stopped = MedicationService.addMedication(
            name: "Stopped", strength: "10mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        try MedicationService.discontinue(stopped, reason: "x", in: context)

        let days = DayQuery.batchDays(from: try fetchBatches(), on: .now)
        XCTAssertEqual(days.count, 1)                       // Empty batch dropped
        XCTAssertEqual(days.first?.batch.name, "Blue")
        XCTAssertEqual(days.first?.meds.map { $0.item.medication?.name }, ["Active"])
        XCTAssertEqual(days.first?.state, .pending)         // nothing logged yet
    }

    func testBatchDayStateReflectsExistingLogs() throws {
        let blue = Batch(name: "Blue", timeOfDay: .now, sortOrder: 0)
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "A", strength: "1mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let med2 = MedicationService.addMedication(
            name: "B", strength: "1mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        _ = (med, med2)

        let item = try XCTUnwrap((blue.items ?? []).first { $0.medication?.name == "A" })
        let log = DoseLog(scheduledDate: .now, status: .taken, medication: item.medication, batchItem: item)
        context.insert(log)
        try context.save()

        let day = try XCTUnwrap(DayQuery.batchDays(from: try fetchBatches(), on: .now).first)
        XCTAssertEqual(day.state, .partial)
        let aDose = try XCTUnwrap(day.meds.first { $0.item.medication?.name == "A" })
        XCTAssertNotNil(aDose.log)
        let bDose = try XCTUnwrap(day.meds.first { $0.item.medication?.name == "B" })
        XCTAssertNil(bDose.log)
    }

    func testPRNDosesReturnActivePRNWithThatDaysLogs() throws {
        let tylenol = MedicationService.addMedication(
            name: "Tylenol", strength: "500mg", form: "tablet", isPRN: true, notes: "",
            placements: [], reason: "", in: context)
        context.insert(DoseLog(scheduledDate: .now, takenAt: .now, status: .taken,
                               quantity: 1.0, medication: tylenol, batchItem: nil))
        // a log from a different day must not appear
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        context.insert(DoseLog(scheduledDate: yesterday, takenAt: yesterday, status: .taken,
                               quantity: 1.0, medication: tylenol, batchItem: nil))
        try context.save()

        let meds = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isActive && $0.isPRN }, sortBy: [SortDescriptor(\.name)]))
        let prn = DayQuery.prnDoses(from: meds, on: .now)
        XCTAssertEqual(prn.map { $0.med.name }, ["Tylenol"])
        XCTAssertEqual(prn.first?.logs.count, 1)
    }
}
```

- [ ] **Step 2: Generate project and run tests to verify they fail**

```bash
xcodegen generate
xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/DayQueryTests 2>&1 | tail -30
```
Expected: FAIL — `DayQuery` is undefined (compile error).

- [ ] **Step 3: Implement `DayQuery`**

Create `PillDaddy/Services/DayQuery.swift`:

```swift
import Foundation
import SwiftData

/// Pure read helpers that assemble a single day's logging state from already-fetched
/// model objects. No fetching, so it's reactive in views (driven by `@Query`) and
/// directly unit-testable.
@MainActor
enum DayQuery {

    enum BatchState { case pending, partial, taken }

    /// One scheduled med on a day, paired with its existing log (if any).
    struct MedDose: Identifiable {
        let item: BatchItem
        let log: DoseLog?
        var id: PersistentIdentifier { item.persistentModelID }
    }

    /// A batch occurring on a day, with its active scheduled meds and computed state.
    struct BatchDay: Identifiable {
        let batch: Batch
        let slotDate: Date
        let meds: [MedDose]
        var id: PersistentIdentifier { batch.persistentModelID }
        var state: BatchState {
            let logged = meds.filter { $0.log != nil }.count
            if logged == 0 { return .pending }
            return logged == meds.count ? .taken : .partial
        }
    }

    /// A PRN med on a day, with that day's ad-hoc logs (newest first).
    struct PRNDose: Identifiable {
        let med: Medication
        let logs: [DoseLog]
        var id: PersistentIdentifier { med.persistentModelID }
    }

    /// Whether a batch occurs on the given day (daily always; weekdays per its list).
    static func recurs(_ batch: Batch, on day: Date) -> Bool {
        switch RecurrenceKind(rawValue: batch.recurrenceKind) ?? .daily {
        case .daily: return true
        case .weekdays:
            let wd = Calendar.current.component(.weekday, from: day)
            return (batch.weekdays ?? []).contains(wd)
        }
    }

    /// The slot datetime for a batch on a day: that calendar day + the batch's clock time.
    static func slotDate(for batch: Batch, on day: Date) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let comps = cal.dateComponents([.hour, .minute], from: batch.timeOfDay)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0,
                        second: 0, of: start) ?? start
    }

    /// Batches occurring on the day (in their stored order), each with active, non-PRN
    /// meds and any existing logs. Empty batches are omitted.
    static func batchDays(from batches: [Batch], on day: Date) -> [BatchDay] {
        let cal = Calendar.current
        return batches
            .filter { recurs($0, on: day) }
            .compactMap { batch -> BatchDay? in
                let meds = (batch.items ?? [])
                    .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
                    .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
                    .map { item in
                        MedDose(item: item,
                                log: (item.doseLogs ?? []).first {
                                    cal.isDate($0.scheduledDate, inSameDayAs: day) })
                    }
                guard !meds.isEmpty else { return nil }
                return BatchDay(batch: batch, slotDate: slotDate(for: batch, on: day), meds: meds)
            }
    }

    /// Active PRN meds, each with that day's logs (newest first).
    static func prnDoses(from meds: [Medication], on day: Date) -> [PRNDose] {
        let cal = Calendar.current
        return meds.map { med in
            let logs = (med.doseLogs ?? [])
                .filter { $0.batchItem == nil && cal.isDate($0.scheduledDate, inSameDayAs: day) }
                .sorted { ($0.takenAt ?? $0.scheduledDate) > ($1.takenAt ?? $1.scheduledDate) }
            return PRNDose(med: med, logs: logs)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/DayQueryTests 2>&1 | tail -30
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/DayQuery.swift PillDaddyTests/DayQueryTests.swift project.yml
git commit -m "feat: add DayQuery day-assembly read helper for dose logging"
```

---

## Task 2: `DoseLogService` — taken / skip / revert

Owns the upsert, fill-not-overwrite, and required-note rules for scheduled logs.

**Files:**
- Create: `PillDaddy/Services/DoseLogService.swift`
- Test: `PillDaddyTests/DoseLogServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PillDaddyTests/DoseLogServiceTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class DoseLogServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var blue: Batch!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
        blue = Batch(name: "Blue", colorHex: "#3B82F6", timeOfDay: .now, sortOrder: 0)
        context.insert(blue)
    }

    override func tearDown() async throws {
        blue = nil; context = nil; container = nil
        try await super.tearDown()
    }

    private func addMed(_ name: String, qty: Double) -> BatchItem {
        let med = MedicationService.addMedication(
            name: name, strength: "10mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: qty)], reason: "", in: context)
        return (med.batchItems ?? []).first!
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    func testLogBatchTakenWritesOneRowPerItemWithSnapshotsAndQuantity() throws {
        let a = addMed("A", qty: 0.5)
        let b = addMed("B", qty: 1.0)
        let at = Date.now
        DoseLogService.logBatchTaken(blue, on: .now, items: [a, b], takenAt: at, note: "", in: context)

        let all = try logs()
        XCTAssertEqual(all.count, 2)
        let aLog = try XCTUnwrap(all.first { $0.snapshotMedName == "A" })
        XCTAssertEqual(aLog.status, DoseStatus.taken.rawValue)
        XCTAssertEqual(aLog.quantity, 0.5)
        XCTAssertEqual(aLog.snapshotStrength, "10mg")
        XCTAssertEqual(aLog.snapshotBatchColorHex, "#3B82F6")
        XCTAssertEqual(aLog.takenAt, at)
    }

    func testLogBatchTakenIsIdempotentUpsert() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        XCTAssertEqual(try logs().count, 1)   // updated, not duplicated
    }

    func testLogBatchTakenLeavesUntouchedItemsAlone() throws {
        let a = addMed("A", qty: 1.0)
        let b = addMed("B", qty: 1.0)
        // B already skipped individually
        try DoseLogService.logMed(b, on: .now, status: .skipped, takenAt: nil, note: "BP low", in: context)
        // Batch-take only A (fill set excludes B)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)

        let bLog = try XCTUnwrap(try logs().first { $0.snapshotMedName == "B" })
        XCTAssertEqual(bLog.status, DoseStatus.skipped.rawValue)   // skip preserved
        XCTAssertEqual(bLog.notes, "BP low")
        XCTAssertEqual(try logs().count, 2)
    }

    func testLogMedSkipRequiresNote() throws {
        let a = addMed("A", qty: 1.0)
        XCTAssertThrowsError(
            try DoseLogService.logMed(a, on: .now, status: .skipped, takenAt: nil, note: "  ", in: context)
        ) { XCTAssertEqual($0 as? DoseLogServiceError, .noteRequired) }
        XCTAssertEqual(try logs().count, 0)
    }

    func testLogMedTakenAllowsEmptyNoteAndClearsTakenAtOnSkip() throws {
        let a = addMed("A", qty: 1.0)
        try DoseLogService.logMed(a, on: .now, status: .taken, takenAt: .now, note: "", in: context)
        XCTAssertEqual(try XCTUnwrap(try logs().first).takenAt != nil, true)
        try DoseLogService.logMed(a, on: .now, status: .skipped, takenAt: nil, note: "held", in: context)
        let log = try XCTUnwrap(try logs().first)
        XCTAssertEqual(log.status, DoseStatus.skipped.rawValue)
        XCTAssertNil(log.takenAt)
        XCTAssertEqual(try logs().count, 1)   // same row, upserted
    }

    func testRevertDeletesTheSlotRow() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        DoseLogService.revert(a, on: .now, in: context)
        XCTAssertEqual(try logs().count, 0)
    }

    func testRevertBatchDeletesAllSlotRows() throws {
        let a = addMed("A", qty: 1.0)
        let b = addMed("B", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a, b], takenAt: .now, note: "", in: context)
        DoseLogService.revertBatch(blue, on: .now, items: [a, b], in: context)
        XCTAssertEqual(try logs().count, 0)
    }

    func testSnapshotStaysFrozenAfterRename() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        a.medication?.name = "Renamed"
        try context.save()
        XCTAssertEqual(try XCTUnwrap(try logs().first).snapshotMedName, "A")
    }
}
```

- [ ] **Step 2: Generate project and run tests to verify they fail**

```bash
xcodegen generate
xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/DoseLogServiceTests 2>&1 | tail -30
```
Expected: FAIL — `DoseLogService` / `DoseLogServiceError` undefined.

- [ ] **Step 3: Implement `DoseLogService`**

Create `PillDaddy/Services/DoseLogService.swift`:

```swift
import Foundation
import SwiftData

enum DoseLogServiceError: Error, Equatable {
    case noteRequired
}

/// Owns every dose-logging mutation as a single atomic save. The idempotency
/// (one row per med/slot/day), fill-not-overwrite, and required-note rules live
/// here so they're unit-testable independent of the UI.
@MainActor
enum DoseLogService {

    // MARK: - Scheduled batches

    /// Marks the given items taken for the batch's slot on `day` (the fill set the
    /// confirm sheet computed). Items not passed are left untouched. Optional note.
    static func logBatchTaken(
        _ batch: Batch, on day: Date, items: [BatchItem],
        takenAt: Date, note: String, in context: ModelContext
    ) {
        for item in items {
            upsert(item: item, on: day, status: .taken, takenAt: takenAt, note: note, in: context)
        }
        try? context.save()
    }

    /// Upserts a single med's row for its slot on `day`. A skip requires a note.
    static func logMed(
        _ item: BatchItem, on day: Date, status: DoseStatus,
        takenAt: Date?, note: String, in context: ModelContext
    ) throws {
        if status == .skipped { try requireNote(note) }
        upsert(item: item, on: day, status: status, takenAt: takenAt, note: note, in: context)
        try context.save()
    }

    /// Deletes the slot row for one med on `day` (back to unlogged).
    static func revert(_ item: BatchItem, on day: Date, in context: ModelContext) {
        if let log = existingLog(for: item, on: day) { context.delete(log) }
        try? context.save()
    }

    /// Deletes the slot rows for all given items on `day` (back to unlogged).
    static func revertBatch(_ batch: Batch, on day: Date, items: [BatchItem], in context: ModelContext) {
        for item in items {
            if let log = existingLog(for: item, on: day) { context.delete(log) }
        }
        try? context.save()
    }

    // MARK: - PRN

    /// Records a new ad-hoc PRN dose (never upserted — each is its own dose).
    @discardableResult
    static func logPRN(
        _ med: Medication, takenAt: Date, quantity: Double,
        note: String, in context: ModelContext
    ) -> DoseLog {
        let log = DoseLog(
            scheduledDate: takenAt, takenAt: takenAt, status: .taken,
            quantity: quantity, notes: note,
            snapshotMedName: med.name, snapshotStrength: med.strength,
            snapshotBatchColorHex: "", medication: med, batchItem: nil)
        context.insert(log)
        try? context.save()
        return log
    }

    /// Removes a single PRN dose.
    static func deletePRNLog(_ log: DoseLog, in context: ModelContext) {
        context.delete(log)
        try? context.save()
    }

    // MARK: - Internal

    @discardableResult
    private static func upsert(
        item: BatchItem, on day: Date, status: DoseStatus,
        takenAt: Date?, note: String, in context: ModelContext
    ) -> DoseLog {
        let log: DoseLog
        if let existing = existingLog(for: item, on: day) {
            log = existing
        } else {
            log = DoseLog(medication: item.medication, batchItem: item)
            context.insert(log)
        }
        let slot = item.batch.map { DayQuery.slotDate(for: $0, on: day) }
            ?? Calendar.current.startOfDay(for: day)
        log.scheduledDate = slot
        log.status = status.rawValue
        log.takenAt = (status == .taken) ? (takenAt ?? .now) : nil
        log.quantity = item.quantity
        log.notes = note
        log.snapshotMedName = item.medication?.name ?? ""
        log.snapshotStrength = item.medication?.strength ?? ""
        log.snapshotBatchColorHex = item.batch?.colorHex ?? ""
        return log
    }

    private static func existingLog(for item: BatchItem, on day: Date) -> DoseLog? {
        let cal = Calendar.current
        return (item.doseLogs ?? []).first { cal.isDate($0.scheduledDate, inSameDayAs: day) }
    }

    private static func requireNote(_ note: String) throws {
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DoseLogServiceError.noteRequired
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/DoseLogServiceTests 2>&1 | tail -30
```
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/DoseLogService.swift PillDaddyTests/DoseLogServiceTests.swift project.yml
git commit -m "feat: add DoseLogService with upsert, fill, and required-note rules"
```

---

## Task 3: `DoseLogService` — PRN logging tests

The PRN methods were implemented in Task 2; this task adds their dedicated tests (kept separate from the scheduled-logging suite for clarity).

**Files:**
- Test: `PillDaddyTests/DoseLogServicePRNTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PillDaddyTests/DoseLogServicePRNTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class DoseLogServicePRNTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil; container = nil
        try await super.tearDown()
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    func testLogPRNCreatesBatchItemNilRowAndIsRepeatable() throws {
        let med = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(med)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 2.0, note: "headache", in: context)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)

        let all = try logs()
        XCTAssertEqual(all.count, 2)                  // each PRN dose is its own row
        XCTAssertTrue(all.allSatisfy { $0.batchItem == nil })
        XCTAssertEqual(all.first?.snapshotMedName, "Acetaminophen")
        XCTAssertEqual(Set(all.map { $0.quantity }), [1.0, 2.0])
    }

    func testDeletePRNLogRemovesExactlyOne() throws {
        let med = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(med)
        let first = DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)

        DoseLogService.deletePRNLog(first, in: context)
        XCTAssertEqual(try logs().count, 1)
    }
}
```

- [ ] **Step 2: Generate project and run tests to verify they pass**

```bash
xcodegen generate
xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/DoseLogServicePRNTests 2>&1 | tail -30
```
Expected: PASS (2 tests). (Implementation already exists from Task 2.)

- [ ] **Step 3: Commit**

```bash
git add PillDaddyTests/DoseLogServicePRNTests.swift project.yml
git commit -m "test: cover DoseLogService PRN logging"
```

---

## Task 4: Seed sample dose logs

Add a realistic mix of logged states to the dev seed so the Today screen shows taken / skipped / pending out of the box.

**Files:**
- Modify: `PillDaddy/Helpers/SeedData.swift`
- Test: `PillDaddyTests/SeedDataTests.swift` (add one test)

- [ ] **Step 1: Write the failing test**

Add this method inside `final class SeedDataTests` in `PillDaddyTests/SeedDataTests.swift`:

```swift
    func testSeedIncludesTodaysDoseLogs() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        SeedData.seedIfEmpty(context)
        try context.save()

        let cal = Calendar.current
        let logs = try context.fetch(FetchDescriptor<DoseLog>())
        let todays = logs.filter { cal.isDate($0.scheduledDate, inSameDayAs: .now) }
        XCTAssertGreaterThanOrEqual(todays.count, 2)
        XCTAssertTrue(todays.contains { $0.status == DoseStatus.taken.rawValue })
        XCTAssertTrue(todays.contains { $0.status == DoseStatus.skipped.rawValue })
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/SeedDataTests/testSeedIncludesTodaysDoseLogs 2>&1 | tail -30
```
Expected: FAIL — no dose logs seeded yet.

- [ ] **Step 3: Add the seed logs**

In `PillDaddy/Helpers/SeedData.swift`, replace the final block (the two `MedicationChangeEvent` inserts at the end of `seedIfEmpty`) with those same inserts **followed by** the dose-log seed. The full replacement:

```swift
        // A bit of journal history on Metoprolol
        context.insert(MedicationChangeEvent(
            type: .added, reasoning: "Started for hypertension", medication: metoprolol))
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: "Reduced evening dose after dizziness",
            oldValue: "1 tablet", newValue: "½ tablet", medication: metoprolol))

        // Today's logging: Blue batch partially logged (Metoprolol taken, Vitamin D
        // skipped), one PRN dose taken. Green batch left pending.
        let blueSlot = DayQuery.slotDate(for: blue, on: .now)
        context.insert(DoseLog(
            scheduledDate: blueSlot, takenAt: time(9, 5), status: .taken, quantity: 1.0,
            snapshotMedName: metoprolol.name, snapshotStrength: metoprolol.strength,
            snapshotBatchColorHex: blue.colorHex,
            medication: metoprolol, batchItem: metoprololBlue))
        context.insert(DoseLog(
            scheduledDate: blueSlot, status: .skipped, quantity: 1.0, notes: "Held — low appetite",
            snapshotMedName: vitaminD.name, snapshotStrength: vitaminD.strength,
            snapshotBatchColorHex: blue.colorHex,
            medication: vitaminD, batchItem: vitaminDBlue))
        context.insert(DoseLog(
            scheduledDate: time(14, 30), takenAt: time(14, 30), status: .taken, quantity: 1.0,
            snapshotMedName: acetaminophen.name, snapshotStrength: acetaminophen.strength,
            medication: acetaminophen, batchItem: nil))
```

For this to compile, the seed must keep references to the two Blue `BatchItem`s. Change the existing `BatchItem` creation lines so the Blue items are named locals:

Replace:
```swift
        context.insert(BatchItem(quantity: 1.0, medication: metoprolol, batch: blue))
        context.insert(BatchItem(quantity: 0.5, medication: metoprolol, batch: green))
        context.insert(BatchItem(quantity: 1.0, medication: vitaminD, batch: blue))
```
with:
```swift
        let metoprololBlue = BatchItem(quantity: 1.0, medication: metoprolol, batch: blue)
        let vitaminDBlue = BatchItem(quantity: 1.0, medication: vitaminD, batch: blue)
        context.insert(metoprololBlue)
        context.insert(BatchItem(quantity: 0.5, medication: metoprolol, batch: green))
        context.insert(vitaminDBlue)
```

- [ ] **Step 4: Run the SeedData tests to verify they pass**

```bash
xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/SeedDataTests 2>&1 | tail -30
```
Expected: PASS (all 3 SeedData tests — the two existing plus the new one).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Helpers/SeedData.swift PillDaddyTests/SeedDataTests.swift
git commit -m "feat: seed today's dose logs (taken/skipped/PRN) for dogfooding"
```

---

## Task 5: `PRNLogSheet` view

A sheet to record one ad-hoc PRN dose.

**Files:**
- Create: `PillDaddy/Views/Today/PRNLogSheet.swift`

- [ ] **Step 1: Create the view**

Create `PillDaddy/Views/Today/PRNLogSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// Records a single ad-hoc PRN dose: time (default now), quantity, optional note.
struct PRNLogSheet: View {
    let medication: Medication

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var takenAt = Date.now
    @State private var quantity = 1.0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Dose") {
                    DatePicker("Time", selection: $takenAt)
                    Stepper("Quantity: \(DoseFormat.qty(quantity))",
                            value: $quantity, in: 0.5...20, step: 0.5)
                }
                Section("Note (optional)") {
                    TextField("e.g. for headache", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log \(medication.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        DoseLogService.logPRN(medication, takenAt: takenAt,
                                              quantity: quantity, note: note, in: context)
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return PRNLogSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
```

- [ ] **Step 2: Generate project and build**

```bash
xcodegen generate
xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Today/PRNLogSheet.swift project.yml
git commit -m "feat: add PRNLogSheet for ad-hoc PRN dose logging"
```

---

## Task 6: `PRNCard` view

The as-needed card: collapsed until tapped; expanded shows each PRN med with "Log a dose" and that day's logged instances (swipe/tap to delete).

**Files:**
- Create: `PillDaddy/Views/Today/PRNCard.swift`

- [ ] **Step 1: Create the view**

Create `PillDaddy/Views/Today/PRNCard.swift`:

```swift
import SwiftUI
import SwiftData

/// Regime-style "as-needed" card. The per-drug log UI is hidden until expanded.
struct PRNCard: View {
    let doses: [DayQuery.PRNDose]
    let isExpanded: Bool
    let onToggle: () -> Void

    @Environment(\.modelContext) private var context
    @State private var loggingMed: Medication?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    Text("As-needed").font(.headline)
                    Spacer()
                    Text("\(doses.count)").foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(doses) { dose in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(dose.med.name)
                                Text(dose.med.strength).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Log a dose") { loggingMed = dose.med }
                                .font(.caption).buttonStyle(.borderedProminent)
                        }
                        ForEach(dose.logs) { log in
                            HStack {
                                Text("↳ \((log.takenAt ?? log.scheduledDate), style: .time) · \(DoseFormat.qty(log.quantity))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    DoseLogService.deletePRNLog(log, in: context)
                                } label: { Image(systemName: "trash").font(.caption) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .sheet(item: $loggingMed) { PRNLogSheet(medication: $0) }
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    let meds = try! container.mainContext.fetch(
        FetchDescriptor<Medication>(predicate: #Predicate { $0.isActive && $0.isPRN }))
    return PRNCard(doses: DayQuery.prnDoses(from: meds, on: .now),
                   isExpanded: true, onToggle: {})
        .modelContainer(container)
        .padding()
}
#endif
```

Note: `Medication` is a SwiftData `@Model`, which conforms to `Identifiable`, so `sheet(item:)` works with `loggingMed`.

- [ ] **Step 2: Generate project and build**

```bash
xcodegen generate
xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Today/PRNCard.swift project.yml
git commit -m "feat: add PRNCard as-needed logging card"
```

---

## Task 7: `BatchTakenConfirmSheet` view

The "Mark all taken" fill sheet: editable time, optional note, and the grouped med list. Un-logged meds are marked taken; already-taken meds are shown and preserved; skipped meds are shown with a toggle to optionally flip them to taken. Confirm computes the fill set (un-logged + flipped skips) and calls `logBatchTaken`.

**Files:**
- Create: `PillDaddy/Views/Today/BatchTakenConfirmSheet.swift`

- [ ] **Step 1: Create the view**

Create `PillDaddy/Views/Today/BatchTakenConfirmSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// "Mark all taken" as a fill, not an overwrite. Un-logged meds → taken; already
/// taken → preserved; skipped → preserved unless the caregiver flips them here.
struct BatchTakenConfirmSheet: View {
    let batchDay: DayQuery.BatchDay
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var takenAt = Date.now
    @State private var note = ""
    /// Skipped meds the caregiver chose to flip to taken (by item id).
    @State private var flipped: Set<PersistentIdentifier> = []

    private var unlogged: [DayQuery.MedDose] { batchDay.meds.filter { $0.log == nil } }
    private var alreadyTaken: [DayQuery.MedDose] {
        batchDay.meds.filter { $0.log?.status == DoseStatus.taken.rawValue }
    }
    private var skipped: [DayQuery.MedDose] {
        batchDay.meds.filter { $0.log?.status == DoseStatus.skipped.rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") { DatePicker("Taken at", selection: $takenAt) }

                if !unlogged.isEmpty {
                    Section("Will be marked taken") {
                        ForEach(unlogged) { medRow($0) }
                    }
                }
                if !alreadyTaken.isEmpty {
                    Section("Already taken") {
                        ForEach(alreadyTaken) { dose in
                            medRow(dose).foregroundStyle(.secondary)
                        }
                    }
                }
                if !skipped.isEmpty {
                    Section("Skipped — tap to take instead") {
                        ForEach(skipped) { dose in
                            Button { toggleFlip(dose) } label: {
                                HStack {
                                    Image(systemName: flipped.contains(dose.id)
                                          ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(dose.item.medication?.name ?? "—")
                                        if let n = dose.log?.notes, !n.isEmpty {
                                            Text(n).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Note (optional)") {
                    TextField("Applies to the doses being taken", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(batchDay.batch.name.isEmpty ? "Batch" : batchDay.batch.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                }
            }
        }
    }

    private func medRow(_ dose: DayQuery.MedDose) -> some View {
        HStack {
            Text(dose.item.medication?.name ?? "—")
            Spacer()
            Text("\(DoseFormat.qty(dose.item.quantity)) \(dose.item.medication?.form ?? "")")
                .foregroundStyle(.secondary)
        }
    }

    private func toggleFlip(_ dose: DayQuery.MedDose) {
        if flipped.contains(dose.id) { flipped.remove(dose.id) } else { flipped.insert(dose.id) }
    }

    private func confirm() {
        let fill = unlogged.map(\.item) + skipped.filter { flipped.contains($0.id) }.map(\.item)
        DoseLogService.logBatchTaken(batchDay.batch, on: day, items: fill,
                                     takenAt: takenAt, note: note, in: context)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    let batches = try! container.mainContext.fetch(
        FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.sortOrder)]))
    let day = DayQuery.batchDays(from: batches, on: .now).first!
    return BatchTakenConfirmSheet(batchDay: day, day: .now)
        .modelContainer(container)
}
#endif
```

- [ ] **Step 2: Generate project and build**

```bash
xcodegen generate
xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Today/BatchTakenConfirmSheet.swift project.yml
git commit -m "feat: add BatchTakenConfirmSheet (fill-not-overwrite mark-all-taken)"
```

---

## Task 8: `IndividualAdjustSheet` view

Per-med taken/skip/clear with a shared note that is required when any med is being skipped. Saves each changed med via `logMed`/`revert`.

**Files:**
- Create: `PillDaddy/Views/Today/IndividualAdjustSheet.swift`

- [ ] **Step 1: Create the view**

Create `PillDaddy/Views/Today/IndividualAdjustSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// Per-med taken / skip / clear for one batch on a day. A note is required when
/// any med is set to Skip (the note applies to those skips).
struct IndividualAdjustSheet: View {
    let batchDay: DayQuery.BatchDay
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    enum Choice: String, CaseIterable, Identifiable {
        case clear = "—", taken = "Taken", skip = "Skip"
        var id: String { rawValue }
    }

    @State private var choices: [PersistentIdentifier: Choice] = [:]
    @State private var note = ""

    private var anySkip: Bool { choices.values.contains(.skip) }
    private var saveDisabled: Bool {
        anySkip && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(batchDay.meds) { dose in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dose.item.medication?.name ?? "—")
                            Picker("", selection: binding(for: dose)) {
                                ForEach(Choice.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 2)
                    }
                }
                if anySkip {
                    Section("Reason for skip (required)") {
                        TextField("e.g. BP too low", text: $note, axis: .vertical)
                    }
                }
            }
            .navigationTitle("Adjust \(batchDay.batch.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saveDisabled)
                }
            }
            .onAppear(perform: seedChoices)
        }
    }

    private func binding(for dose: DayQuery.MedDose) -> Binding<Choice> {
        Binding(
            get: { choices[dose.id] ?? .clear },
            set: { choices[dose.id] = $0 })
    }

    private func seedChoices() {
        for dose in batchDay.meds {
            switch dose.log?.status {
            case DoseStatus.taken.rawValue: choices[dose.id] = .taken
            case DoseStatus.skipped.rawValue: choices[dose.id] = .skip
            default: choices[dose.id] = .clear
            }
        }
    }

    private func save() {
        for dose in batchDay.meds {
            switch choices[dose.id] ?? .clear {
            case .taken:
                try? DoseLogService.logMed(dose.item, on: day, status: .taken,
                                           takenAt: .now, note: "", in: context)
            case .skip:
                try? DoseLogService.logMed(dose.item, on: day, status: .skipped,
                                           takenAt: nil, note: note, in: context)
            case .clear:
                DoseLogService.revert(dose.item, on: day, in: context)
            }
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    let batches = try! container.mainContext.fetch(
        FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.sortOrder)]))
    let day = DayQuery.batchDays(from: batches, on: .now).first!
    return IndividualAdjustSheet(batchDay: day, day: .now)
        .modelContainer(container)
}
#endif
```

- [ ] **Step 2: Generate project and build**

```bash
xcodegen generate
xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Today/IndividualAdjustSheet.swift project.yml
git commit -m "feat: add IndividualAdjustSheet for per-med taken/skip/clear"
```

---

## Task 9: `BatchLogCard` view

A collapsed/expanded batch card. Collapsed shows name, time, and a status chip. Expanded shows the meds (with per-med status) and the action buttons.

**Files:**
- Create: `PillDaddy/Views/Today/BatchLogCard.swift`

- [ ] **Step 1: Create the view**

Create `PillDaddy/Views/Today/BatchLogCard.swift`:

```swift
import SwiftUI
import SwiftData

/// One batch on the Today screen. Collapsed → summary; expanded → meds + actions.
struct BatchLogCard: View {
    let batchDay: DayQuery.BatchDay
    let isExpanded: Bool
    let onToggle: () -> Void
    let onMarkAllTaken: () -> Void
    let onAdjust: () -> Void
    let onRevert: () -> Void

    private var color: Color { Color(hex: batchDay.batch.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack {
                    Circle().fill(color).frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text(batchDay.batch.name.isEmpty ? "Batch" : batchDay.batch.name)
                            .font(.headline)
                        Text(batchDay.slotDate, style: .time)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusChip
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(batchDay.meds) { dose in
                    HStack {
                        Text(dose.item.medication?.name ?? "—")
                        Spacer()
                        Text("\(DoseFormat.qty(dose.item.quantity)) \(dose.item.medication?.form ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                        medChip(dose)
                    }
                }
                actionButtons
            }
        }
        .padding()
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var statusChip: some View {
        switch batchDay.state {
        case .taken: Label("Taken", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .partial: Text("Partial").foregroundStyle(.orange)
        case .pending: Text("Pending").foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    @ViewBuilder private func medChip(_ dose: DayQuery.MedDose) -> some View {
        switch dose.log?.status {
        case DoseStatus.taken.rawValue:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case DoseStatus.skipped.rawValue:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.orange).font(.caption)
        default:
            Image(systemName: "circle").foregroundStyle(.secondary).font(.caption)
        }
    }

    @ViewBuilder private var actionButtons: some View {
        VStack(spacing: 8) {
            if batchDay.state != .taken {
                Button("Mark all taken", action: onMarkAllTaken)
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            }
            Button("Adjust individually…", action: onAdjust)
                .buttonStyle(.bordered).frame(maxWidth: .infinity)
            if batchDay.state != .pending {
                Button("Clear log", role: .destructive, action: onRevert)
                    .font(.caption)
            }
        }
        .padding(.top, 4)
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    let batches = try! container.mainContext.fetch(
        FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.sortOrder)]))
    let day = DayQuery.batchDays(from: batches, on: .now).first!
    return BatchLogCard(batchDay: day, isExpanded: true, onToggle: {},
                        onMarkAllTaken: {}, onAdjust: {}, onRevert: {})
        .modelContainer(container)
        .padding()
}
#endif
```

- [ ] **Step 2: Generate project and build**

```bash
xcodegen generate
xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Today/BatchLogCard.swift project.yml
git commit -m "feat: add BatchLogCard collapsed/expanded batch card"
```

---

## Task 10: `TodayView` host

Ties it together: day stepper (today default, back-fill past, no future), progress line, accordion of `BatchLogCard`s (closest-to-now auto-expands on today; collapses after fully logged), and the `PRNCard`. Reactive via `@Query`.

**Files:**
- Create: `PillDaddy/Views/Today/TodayView.swift`

- [ ] **Step 1: Create the view**

Create `PillDaddy/Views/Today/TodayView.swift`:

```swift
import SwiftUI
import SwiftData

/// The Today tab: a day's dose-logging checklist.
struct TodayView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var batches: [Batch]
    @Query(filter: #Predicate<Medication> { $0.isActive && $0.isPRN }, sort: \Medication.name)
    private var prnMeds: [Medication]
    /// Observed so inserts/deletes of logs re-render the screen.
    @Query private var allLogs: [DoseLog]

    @State private var selectedDay = Date.now
    @State private var expandedID: PersistentIdentifier?
    @State private var prnExpanded = false

    @State private var takingBatch: DayQuery.BatchDay?
    @State private var adjustingBatch: DayQuery.BatchDay?

    private var batchDays: [DayQuery.BatchDay] {
        _ = allLogs.count   // touch to keep the view dependent on log changes
        return DayQuery.batchDays(from: batches, on: selectedDay)
    }
    private var prnDoses: [DayQuery.PRNDose] {
        _ = allLogs.count
        return DayQuery.prnDoses(from: prnMeds, on: selectedDay)
    }
    private var isToday: Bool { Calendar.current.isDate(selectedDay, inSameDayAs: .now) }
    private var doneCount: Int { batchDays.filter { $0.state == .taken }.count }

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
                        PRNCard(doses: prnDoses, isExpanded: prnExpanded,
                                onToggle: { prnExpanded.toggle() })
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .sheet(item: $takingBatch) { BatchTakenConfirmSheet(batchDay: $0, day: selectedDay) }
            .sheet(item: $adjustingBatch) { IndividualAdjustSheet(batchDay: $0, day: selectedDay) }
            .onAppear(perform: autoExpand)
            .onChange(of: selectedDay) { _, _ in autoExpand() }
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
            .filter { $0.state != .taken }
            .min { abs($0.slotDate.timeIntervalSince(now)) < abs($1.slotDate.timeIntervalSince(now)) }?
            .id
    }
}

#if DEBUG
#Preview {
    TodayView()
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 2: Generate project and build**

```bash
xcodegen generate
xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Today/TodayView.swift project.yml
git commit -m "feat: add TodayView dose-logging screen"
```

---

## Task 11: Wire `TodayView` into the tab bar

**Files:**
- Modify: `PillDaddy/Views/MainTabView.swift:6-7`

- [ ] **Step 1: Replace the Today placeholder**

In `PillDaddy/Views/MainTabView.swift`, replace:

```swift
            PlaceholderTab(title: "Today", systemImage: "checklist")
                .tabItem { Label("Today", systemImage: "checklist") }
```
with:
```swift
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/MainTabView.swift
git commit -m "feat: show TodayView in the Today tab"
```

---

## Task 12: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Regenerate and run the entire test suite**

```bash
xcodegen generate
xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```
Expected: TEST SUCCEEDED — all suites pass (DayQuery, DoseLogService, DoseLogServicePRN, SeedData, plus the existing model/service suites).

- [ ] **Step 2: Manual dogfood pass (Simulator)**

Launch with seed data:
```bash
xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
xcrun simctl boot "iPhone 17" 2>/dev/null || true
open -a Simulator
```
Then run from Xcode with the `-seedTestData` launch argument (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments), and confirm on the **Today** tab:
- The screen opens with the batch closest to now auto-expanded; others collapsed.
- Seeded state shows: Blue partial (Metoprolol taken ✓, Vitamin D skipped ✗), Green pending, one PRN dose under As-needed.
- **Mark all taken** on a pending batch → confirm sheet (editable time, optional note) → batch shows Taken and collapses.
- On a batch with a skip, **Mark all taken** shows the skipped med under "Skipped — tap to take instead," preserved unless flipped.
- **Adjust individually…** → set a med to Skip → Save is blocked until a reason is entered.
- **As-needed** card is collapsed until tapped; **Log a dose** records an instance; the trash button deletes it.
- Step the day stepper back one day (cards collapsed, all pending), back-fill a batch, then forward — the **next** (future) button is disabled on today.
- Re-tap a logged batch and use **Clear log** to revert it to pending.

- [ ] **Step 3: Final commit (if the manual pass surfaced any fixes)**

```bash
git add -A
git commit -m "fix: dose-logging manual-pass adjustments"
```
(Skip if nothing changed.)

---

## Self-Review notes (for the implementer)

- **Spec coverage:** day stepper + back-fill (Task 10); accordion + closest-to-now auto-expand + collapse-on-complete (Task 10); Mark-all-taken fill/preserve/flip (Tasks 2, 7); required-note skip (Tasks 2, 8); one-row-per-slot upsert + revert (Task 2); PRN card collapsed-until-expanded + per-drug repeatable logging + delete (Tasks 3, 5, 6); recurrence-aware day assembly + state + discontinued exclusion (Task 1); quantity + frozen snapshots (Tasks 1–2, 4); sample logs in seed (Task 4); deferred auto-missed/Settings — intentionally absent.
- **Type consistency:** `DayQuery.BatchDay/MedDose/PRNDose/BatchState`, `DoseLogService.{logBatchTaken,logMed,revert,revertBatch,logPRN,deletePRNLog}`, and `DoseLogServiceError.noteRequired` are used identically across service, views, and tests.
- **"Pending" is display-only** — no `missed` rows are ever written this session.
```
