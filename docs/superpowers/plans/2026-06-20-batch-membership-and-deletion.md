# Batch Membership & Deletion UX — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let caregivers move/add/remove a medication's batch memberships from the medication detail view, delete batches when no active meds remain, document every membership change as an audit event, and replace the implicit PRN-vs-scheduled log discriminator with an explicit frozen flag.

**Architecture:** All mutations route through the existing `@MainActor enum MedicationService` / `DoseLogService` layers so invariants stay in one unit-testable place. Membership changes emit a new `MedChangeType.scheduleChanged` event (no reason). Batches are hard-deleted (history is self-contained on `DoseLog` snapshots). A new `DoseLog.isPRN` flag, frozen at log time plus a one-time backfill, decouples PRN classification from the live `batchItem` link.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-06-20-batch-membership-and-deletion-design.md`

---

## File Structure

**Modify:**
- `PillDaddy/Models/PillModelEnums.swift` — add `scheduleChanged` to `MedChangeType`.
- `PillDaddy/Services/MedicationLineage.swift` — add `.scheduleChanged` title case.
- `PillDaddy/Services/MedicationService.swift` — event in `addToBatch`; new `removeFromBatch`, `moveToBatch`, `deleteBatch`; new `BatchError`, `MembershipError`; private description helper.
- `PillDaddy/Models/DoseLog.swift` — add `isPRN` stored property + init param.
- `PillDaddy/Services/DoseLogService.swift` — set `isPRN` in `logPRN`.
- `PillDaddy/Services/DayQuery.swift` — classify PRN via `isPRN`.
- `PillDaddy/PillDaddyApp.swift` — call backfill on launch.
- `PillDaddy/Views/Meds/BatchEditor.swift` — route swipe-delete through service; add gated "Delete batch" button.
- `PillDaddy/Views/Meds/MedicationDetailView.swift` — replace read-only "Taken in" with editable "Schedule" section.

**Create:**
- `PillDaddy/Services/DoseLogMigration.swift` — one-time `isPRN` backfill.
- `PillDaddy/Views/Meds/BatchMembershipSheets.swift` — `AddToBatchSheet`, `MoveBatchSheet`.

**Test:**
- `PillDaddyTests/MedicationServiceTests.swift` — membership + delete service tests.
- `PillDaddyTests/MedicationLineageTests.swift` — `scheduleChanged` title.
- `PillDaddyTests/DoseLogServicePRNTests.swift` — `isPRN` set on PRN log.
- `PillDaddyTests/DayQueryTests.swift` — classification via `isPRN`.
- `PillDaddyTests/DoseLogMigrationTests.swift` — **new** — backfill behavior.

### Conventions used throughout

- **Build:** `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build -quiet`
- **Run one test:** `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/<Suite>/<method>`
- **After creating/deleting files:** run `xcodegen generate` (sources are directory-globbed in `project.yml`).
- If `iPhone 16` is not an installed simulator, substitute one from `xcrun simctl list devices available`.

---

## Task 1: `scheduleChanged` change-event type

**Files:**
- Modify: `PillDaddy/Models/PillModelEnums.swift:23`
- Modify: `PillDaddy/Services/MedicationLineage.swift:72-84`
- Test: `PillDaddyTests/MedicationLineageTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `PillDaddyTests/MedicationLineageTests.swift` (inside the `struct`):

```swift
    @Test
    func testScheduleChangedEventTitle() {
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.0)
        context.insert(med)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: "Morning · 1 tablet", newValue: "Afternoon · 1 tablet", medication: med))
        let events = MedicationLineage.events(from: med)
        let item = events.first { $0.event.eventType == MedChangeType.scheduleChanged.rawValue }
        #expect(item != nil)
        #expect(MedicationLineage.title(for: item!) == "Schedule changed")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/MedicationLineageTests/testScheduleChangedEventTitle`
Expected: FAIL — compile error, `scheduleChanged` is not a member of `MedChangeType`.

- [ ] **Step 3: Add the enum case**

In `PillDaddy/Models/PillModelEnums.swift`, change the `MedChangeType` case line to:

```swift
    case added, doseChanged, instructionsChanged, scheduleChanged, swapped, discontinued, reactivated, note
```

- [ ] **Step 4: Add the title case**

In `PillDaddy/Services/MedicationLineage.swift`, inside `title(for:)`'s switch, add after the `.instructionsChanged` case:

```swift
        case .scheduleChanged: return "Schedule changed"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/MedicationLineageTests/testScheduleChangedEventTitle`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add PillDaddy/Models/PillModelEnums.swift PillDaddy/Services/MedicationLineage.swift PillDaddyTests/MedicationLineageTests.swift
git commit -m "feat(allocation): add scheduleChanged medication change-event type"
```

---

## Task 2: Membership service methods (add event, remove, move)

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift:8-10` (errors), `:89-98` (`addToBatch`), and add new methods + helper.
- Test: `PillDaddyTests/MedicationServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `PillDaddyTests/MedicationServiceTests.swift` (inside the `struct`):

```swift
    @Test
    func testAddToBatchWritesScheduleChangedEvent() throws {
        let blue = Batch(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        try context.save()

        try MedicationService.addToBatch(med, blue, quantity: 1.0, in: context)

        #expect(med.batchItems?.count == 1)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "")
        #expect(event.newValue == "Morning · 1 tablet")
        #expect(event.reasoning == "")
    }

    @Test
    func testAddToBatchStillEnforcesAllocationCap() throws {
        let blue = Batch(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet")
        context.insert(med)
        try context.save()

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addToBatch(med, blue, quantity: 2.0, in: context)
        }
    }

    @Test
    func testRemoveFromBatchDeletesItemAndWritesEvent() throws {
        let blue = Batch(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet")
        context.insert(med)
        let item = BatchItem(quantity: 1.0, medication: med, batch: blue)
        context.insert(item)
        try context.save()

        try MedicationService.removeFromBatch(item, in: context)

        #expect(med.batchItems?.isEmpty == true)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "Morning · 1 tablet")
        #expect(event.newValue == "")
    }

    @Test
    func testMoveToBatchPreservesQuantityAndWritesOldNewEvent() throws {
        let morning = Batch(name: "Morning")
        let afternoon = Batch(name: "Afternoon")
        context.insert(morning); context.insert(afternoon)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        let item = BatchItem(quantity: 1.5, medication: med, batch: morning)
        context.insert(item)
        try context.save()

        try MedicationService.moveToBatch(item, to: afternoon, in: context)

        #expect(item.batch?.name == "Afternoon")
        #expect(item.quantity == 1.5)
        #expect(DoseAllocation.allocated(med) == 1.5)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "Morning · 1.5 tablet")
        #expect(event.newValue == "Afternoon · 1.5 tablet")
    }

    @Test
    func testMoveToBatchRejectsDuplicateMembership() throws {
        let morning = Batch(name: "Morning")
        let afternoon = Batch(name: "Afternoon")
        context.insert(morning); context.insert(afternoon)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        let inMorning = BatchItem(quantity: 1.0, medication: med, batch: morning)
        let inAfternoon = BatchItem(quantity: 1.0, medication: med, batch: afternoon)
        context.insert(inMorning); context.insert(inAfternoon)
        try context.save()

        #expect(throws: MembershipError.alreadyInBatch) {
            try MedicationService.moveToBatch(inMorning, to: afternoon, in: context)
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/MedicationServiceTests/testRemoveFromBatchDeletesItemAndWritesEvent`
Expected: FAIL — `removeFromBatch` / `moveToBatch` / `MembershipError` not defined.

- [ ] **Step 3: Add the `MembershipError` enum**

In `PillDaddy/Services/MedicationService.swift`, after the existing `DoseAllocationError` enum (around line 10), add:

```swift
enum MembershipError: Error, Equatable {
    case alreadyInBatch
}
```

- [ ] **Step 4: Add the description helper**

In `MedicationService`, in the `// MARK: - Internal helpers` section (near `doseSummary`), add:

```swift
    /// Human-readable membership description frozen into schedule-change events,
    /// e.g. "Morning · 1 tablet".
    static func membershipDescription(_ item: BatchItem) -> String {
        let batch = item.batch?.name ?? "?"
        let form = item.medication?.form ?? ""
        return "\(batch) · \(DoseFormat.qty(item.quantity)) \(form)"
    }
```

- [ ] **Step 5: Emit an event from `addToBatch`**

In `MedicationService.addToBatch`, replace the body (currently lines ~92-97) with:

```swift
        if DoseAllocation.isOverTarget(allocated: DoseAllocation.allocated(med) + quantity, target: med.dailyDoseTarget) {
            throw DoseAllocationError.exceedsDailyTarget
        }
        let item = BatchItem(quantity: quantity, medication: med, batch: batch)
        context.insert(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: "", newValue: membershipDescription(item), medication: med))
        try context.save()
```

- [ ] **Step 6: Add `removeFromBatch` and `moveToBatch`**

In `MedicationService`, after `addToBatch`, add:

```swift
    /// Removes a medication's batch membership and records a `scheduleChanged`
    /// event documenting what left. No reason required.
    static func removeFromBatch(_ item: BatchItem, in context: ModelContext) throws {
        let med = item.medication
        let old = membershipDescription(item)
        context.delete(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: old, newValue: "", medication: med))
        try context.save()
    }

    /// Relocates a membership to another batch, preserving its quantity, and
    /// records a `scheduleChanged` event. Because the quantity is relocated (not
    /// added), total allocation is unchanged, so no cap check is needed. Throws
    /// if the target batch already contains this medication.
    static func moveToBatch(_ item: BatchItem, to batch: Batch, in context: ModelContext) throws {
        let medID = item.medication?.persistentModelID
        let duplicate = (batch.items ?? []).contains { $0.medication?.persistentModelID == medID }
        if duplicate { throw MembershipError.alreadyInBatch }

        let med = item.medication
        let old = membershipDescription(item)
        item.batch = batch
        let new = membershipDescription(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: old, newValue: new, medication: med))
        try context.save()
    }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/MedicationServiceTests`
Expected: PASS (all `MedicationServiceTests`, including the five new ones).

- [ ] **Step 8: Commit**

```bash
git add PillDaddy/Services/MedicationService.swift PillDaddyTests/MedicationServiceTests.swift
git commit -m "feat(allocation): audited add/remove/move batch membership service methods"
```

---

## Task 3: Gated hard-delete of batches (service)

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift` (add `BatchError` + `deleteBatch`).
- Test: `PillDaddyTests/MedicationServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `PillDaddyTests/MedicationServiceTests.swift`:

```swift
    @Test
    func testDeleteBatchThrowsWhenActiveMedicationPresent() throws {
        let batch = Batch(name: "Morning")
        context.insert(batch)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet", isActive: true)
        context.insert(med)
        context.insert(BatchItem(quantity: 1.0, medication: med, batch: batch))
        try context.save()

        #expect(throws: BatchError.hasActiveMedications) {
            try MedicationService.deleteBatch(batch, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<Batch>()).count == 1)
    }

    @Test
    func testDeleteBatchSucceedsWhenNoActiveMedsAndPreservesDoseLogSnapshots() throws {
        let batch = Batch(name: "Morning", colorHex: "#3B82F6")
        context.insert(batch)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet", isActive: false)
        context.insert(med)
        let item = BatchItem(quantity: 1.0, medication: med, batch: batch)
        context.insert(item)
        let log = DoseLog(scheduledDate: .now, takenAt: .now, status: .taken, quantity: 1.0,
                          snapshotMedName: "Metoprolol", snapshotStrength: "30 mg",
                          snapshotStrengthValue: 30, snapshotStrengthUnit: "mg",
                          snapshotBatchColorHex: "#3B82F6", medication: med, batchItem: item)
        context.insert(log)
        try context.save()

        try MedicationService.deleteBatch(batch, in: context)

        #expect(try context.fetch(FetchDescriptor<Batch>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BatchItem>()).isEmpty)   // cascade removed the join row
        let logs = try context.fetch(FetchDescriptor<DoseLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.batchItem == nil)                              // link nullified
        #expect(logs.first?.snapshotMedName == "Metoprolol")              // snapshot survives
        #expect(logs.first?.snapshotBatchColorHex == "#3B82F6")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/MedicationServiceTests/testDeleteBatchThrowsWhenActiveMedicationPresent`
Expected: FAIL — `BatchError` / `deleteBatch` not defined.

- [ ] **Step 3: Add the `BatchError` enum**

In `PillDaddy/Services/MedicationService.swift`, after `MembershipError` (from Task 2), add:

```swift
enum BatchError: Error, Equatable {
    case hasActiveMedications
}
```

- [ ] **Step 4: Add `deleteBatch`**

In `MedicationService`, after `moveToBatch`, add:

```swift
    /// Hard-deletes a batch, allowed only when no active (non-PRN) medication is
    /// a member. Remaining (discontinued-med) join rows cascade away; dose-log
    /// snapshots survive intact.
    static func deleteBatch(_ batch: Batch, in context: ModelContext) throws {
        let hasActive = (batch.items ?? []).contains {
            ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false)
        }
        if hasActive { throw BatchError.hasActiveMedications }
        context.delete(batch)
        try context.save()
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/MedicationServiceTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add PillDaddy/Services/MedicationService.swift PillDaddyTests/MedicationServiceTests.swift
git commit -m "feat(allocation): gated hard-delete of batches in MedicationService"
```

---

## Task 4: Explicit `DoseLog.isPRN` discriminator

**Files:**
- Modify: `PillDaddy/Models/DoseLog.swift`
- Modify: `PillDaddy/Services/DoseLogService.swift:68-73` (`logPRN`)
- Modify: `PillDaddy/Services/DayQuery.swift:83`
- Test: `PillDaddyTests/DoseLogServicePRNTests.swift`, `PillDaddyTests/DayQueryTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `PillDaddyTests/DoseLogServicePRNTests.swift` (inside the `struct`):

```swift
    @Test
    func testLogPRNSetsIsPRNFlag() throws {
        let med = Medication(name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, isPRN: true)
        context.insert(med)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)
        let all = try logs()
        #expect(all.allSatisfy { $0.isPRN })
    }
```

Add to `PillDaddyTests/DayQueryTests.swift` (inside its `struct`):

```swift
    @Test
    func testPrnDosesUsesIsPRNFlagNotBatchItemLink() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        // A scheduled (non-PRN) log whose batchItem link has been nullified must NOT
        // be classified as PRN.
        let scheduled = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                                   form: "tablet", isPRN: false)
        context.insert(scheduled)
        let orphanLog = DoseLog(scheduledDate: .now, status: .taken,
                                medication: scheduled, batchItem: nil)
        orphanLog.isPRN = false
        context.insert(orphanLog)

        // A genuine PRN log.
        let tylenol = Medication(name: "Tylenol", strengthValue: 500, strengthUnit: "mg",
                                 form: "tablet", isPRN: true)
        context.insert(tylenol)
        let prnLog = DoseLog(scheduledDate: .now, status: .taken,
                             medication: tylenol, batchItem: nil)
        prnLog.isPRN = true
        context.insert(prnLog)
        try context.save()

        let prnMeds = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isActive && $0.isPRN }))
        let result = DayQuery.prnDoses(from: prnMeds, on: .now)
        let totalLogs = result.reduce(0) { $0 + $1.logs.count }
        #expect(totalLogs == 1)                       // only the genuine PRN log
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/DoseLogServicePRNTests/testLogPRNSetsIsPRNFlag`
Expected: FAIL — `isPRN` is not a member of `DoseLog`.

- [ ] **Step 3: Add `isPRN` to `DoseLog`**

In `PillDaddy/Models/DoseLog.swift`:

Add the stored property after `var snapshotBatchColorHex` (line 17):

```swift
    var isPRN: Bool = false                  // frozen at log time; true only for ad-hoc PRN doses
```

Add the init parameter — change the `init` signature line that reads `snapshotBatchColorHex: String = "",` to insert a new parameter right after it:

```swift
                 snapshotBatchColorHex: String = "", isPRN: Bool = false,
```

And add the assignment in the init body after `self.snapshotBatchColorHex = snapshotBatchColorHex`:

```swift
        self.isPRN = isPRN
```

- [ ] **Step 4: Set the flag in `logPRN`**

In `PillDaddy/Services/DoseLogService.swift`, in `logPRN`, change the `DoseLog(...)` initializer call's trailing arguments from:

```swift
            snapshotBatchColorHex: "", medication: med, batchItem: nil)
```

to:

```swift
            snapshotBatchColorHex: "", isPRN: true, medication: med, batchItem: nil)
```

(The scheduled `upsert` path leaves `isPRN` at its `false` default — no change needed there.)

- [ ] **Step 5: Switch `DayQuery.prnDoses` to the flag**

In `PillDaddy/Services/DayQuery.swift`, in `prnDoses`, change:

```swift
                .filter { $0.batchItem == nil && cal.isDate($0.scheduledDate, inSameDayAs: day) }
```

to:

```swift
                .filter { $0.isPRN && cal.isDate($0.scheduledDate, inSameDayAs: day) }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/DoseLogServicePRNTests -only-testing:PillDaddyTests/DayQueryTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add PillDaddy/Models/DoseLog.swift PillDaddy/Services/DoseLogService.swift PillDaddy/Services/DayQuery.swift PillDaddyTests/DoseLogServicePRNTests.swift PillDaddyTests/DayQueryTests.swift
git commit -m "feat(logs): explicit isPRN flag on DoseLog, decouple PRN classification from batchItem link"
```

---

## Task 5: One-time `isPRN` backfill on launch

**Files:**
- Create: `PillDaddy/Services/DoseLogMigration.swift`
- Modify: `PillDaddy/PillDaddyApp.swift:41-59` (init)
- Test: `PillDaddyTests/DoseLogMigrationTests.swift` (new)

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/DoseLogMigrationTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DoseLogMigrationTests {

    @Test
    func testBackfillTagsLegacyNilBatchItemLogsAsPRN() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Tylenol", strengthValue: 500, strengthUnit: "mg", isPRN: true)
        context.insert(med)

        // Legacy PRN log: nil batchItem, isPRN still at the migration default of false.
        let legacy = DoseLog(scheduledDate: .now, status: .taken, medication: med, batchItem: nil)
        legacy.isPRN = false
        context.insert(legacy)

        // Scheduled log with a live batchItem must stay non-PRN.
        let batch = Batch(name: "Morning")
        context.insert(batch)
        let item = BatchItem(quantity: 1.0, medication: med, batch: batch)
        context.insert(item)
        let scheduled = DoseLog(scheduledDate: .now, status: .taken, medication: med, batchItem: item)
        scheduled.isPRN = false
        context.insert(scheduled)
        try context.save()

        DoseLogMigration.backfillPRNFlag(in: context)

        #expect(legacy.isPRN == true)
        #expect(scheduled.isPRN == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/DoseLogMigrationTests/testBackfillTagsLegacyNilBatchItemLogsAsPRN`
Expected: FAIL — `DoseLogMigration` not defined (after `xcodegen generate` adds the new test file; until the impl file exists this won't compile).

- [ ] **Step 3: Create the migration helper**

Create `PillDaddy/Services/DoseLogMigration.swift`:

```swift
import Foundation
import SwiftData

/// One-time data fixes for dose logs. Idempotent and cheap (single-user dataset).
@MainActor
enum DoseLogMigration {

    /// Sets `isPRN = true` for legacy logs created before the flag existed, where
    /// the absence of a `batchItem` link was the only PRN signal. Idempotent.
    static func backfillPRNFlag(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        var changed = false
        for log in all where log.batchItem == nil && !log.isPRN {
            log.isPRN = true
            changed = true
        }
        if changed { try? context.save() }
    }
}
```

- [ ] **Step 4: Regenerate the project so both new files are in the target**

Run: `xcodegen generate`
Expected: "Created project at ..." with no errors.

- [ ] **Step 5: Call the backfill on launch**

In `PillDaddy/PillDaddyApp.swift`, inside `init()`, immediately after the `do { ... } catch { ... }` block that assigns `container` (before the `#if DEBUG` seed block), add:

```swift
        DoseLogMigration.backfillPRNFlag(in: container.mainContext)
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet -only-testing:PillDaddyTests/DoseLogMigrationTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add PillDaddy/Services/DoseLogMigration.swift PillDaddy/PillDaddyApp.swift PillDaddyTests/DoseLogMigrationTests.swift project.yml PillDaddy.xcodeproj
git commit -m "feat(logs): one-time backfill of DoseLog.isPRN on launch"
```

---

## Task 6: BatchEditor — route swipe-delete through service + gated Delete button

**Files:**
- Modify: `PillDaddy/Views/Meds/BatchEditor.swift`

No unit test (the codebase tests services, not SwiftUI views); verification is a clean build. The deletion logic itself is already covered by Task 3's service tests.

- [ ] **Step 1: Add delete-confirmation state**

In `BatchEditor`, after the existing `@State private var errorMessage: String?` (line 29), add:

```swift
    @State private var confirmingDelete = false
```

- [ ] **Step 2: Route swipe-to-delete through the audited service**

In `BatchEditor`, replace the existing `.onDelete` block (lines ~65-68):

```swift
                        .onDelete { offsets in
                            for index in offsets { context.delete(activeItems[index]) }
                            try? context.save()
                        }
```

with:

```swift
                        .onDelete { offsets in
                            for index in offsets {
                                try? MedicationService.removeFromBatch(activeItems[index], in: context)
                            }
                        }
```

- [ ] **Step 3: Add the gated Delete-batch section**

In `BatchEditor`, inside `if let batch { ... }` after the "Pills in this batch" `Section { ... }` (i.e. after the closing brace of that section, still inside the `if let batch` block, around line 79), add:

```swift
                    Section {
                        Button("Delete batch", role: .destructive) { confirmingDelete = true }
                            .disabled(!activeItems.isEmpty)
                        if !activeItems.isEmpty {
                            Text("Remove the \(activeItems.count) active medication(s) before deleting.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
```

- [ ] **Step 4: Add the confirmation alert**

In `BatchEditor`, add this modifier to the `Form` (e.g. right after the existing `.sheet(item: $editingMed) { ... }` modifier, around line 134):

```swift
            .alert("Delete this batch?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    if let batch {
                        try? MedicationService.deleteBatch(batch, in: context)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
```

- [ ] **Step 5: Verify the build**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build -quiet`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add PillDaddy/Views/Meds/BatchEditor.swift
git commit -m "feat(allocation): gated Delete batch button + audited swipe-delete in BatchEditor"
```

---

## Task 7: MedicationDetailView — editable Schedule section + membership sheets

**Files:**
- Create: `PillDaddy/Views/Meds/BatchMembershipSheets.swift`
- Modify: `PillDaddy/Views/Meds/MedicationDetailView.swift`

No unit test (SwiftUI views); verification is a clean build + the SwiftUI previews. Membership mutations are covered by Task 2's service tests.

- [ ] **Step 1: Create the membership sheets**

Create `PillDaddy/Views/Meds/BatchMembershipSheets.swift`:

```swift
import SwiftUI
import SwiftData

/// Adds the medication to a batch it is not already in, with an allocation-capped
/// quantity. Routes through `MedicationService.addToBatch`.
struct AddToBatchSheet: View {
    let medication: Medication

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var allBatches: [Batch]

    @State private var selectedBatch: Batch?
    @State private var quantity = 1.0
    @State private var errorMessage: String?

    private var available: [Batch] {
        let present = Set((medication.batchItems ?? []).compactMap { $0.batch?.persistentModelID })
        return allBatches.filter { !present.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if available.isEmpty {
                    Text("This medication is already in every batch.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Batch", selection: $selectedBatch) {
                        Text("Select…").tag(Batch?.none)
                        ForEach(available) { batch in
                            Text(batch.name.isEmpty ? "Batch" : batch.name).tag(Batch?.some(batch))
                        }
                    }
                    DoseQuantityField(
                        title: "Quantity", value: $quantity,
                        range: 0.5...20, step: 0.5,
                        max: DoseAllocation.remaining(medication))
                    Text("\(DoseFormat.qty(DoseAllocation.remaining(medication))) of \(DoseFormat.qty(medication.dailyDoseTarget))/day remaining")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add to batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(selectedBatch == nil ||
                                  DoseAllocation.isOverTarget(
                                    allocated: DoseAllocation.allocated(medication) + quantity,
                                    target: medication.dailyDoseTarget))
                }
            }
            .alert("Cannot Add", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .onAppear {
                quantity = min(1.0, max(0.5, DoseAllocation.remaining(medication)))
            }
        }
    }

    private func add() {
        guard let batch = selectedBatch else { return }
        do {
            try MedicationService.addToBatch(medication, batch, quantity: quantity, in: context)
            dismiss()
        } catch DoseAllocationError.exceedsDailyTarget {
            errorMessage = "Total allocation across batches cannot exceed the daily dose target."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Moves an existing membership to another batch (quantity carried over), routing
/// through `MedicationService.moveToBatch`.
struct MoveBatchSheet: View {
    let item: BatchItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var allBatches: [Batch]

    @State private var errorMessage: String?

    private var available: [Batch] {
        let present = Set((item.medication?.batchItems ?? []).compactMap { $0.batch?.persistentModelID })
        return allBatches.filter { !present.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            List {
                if available.isEmpty {
                    Text("No other batches to move to.").foregroundStyle(.secondary)
                } else {
                    ForEach(available) { batch in
                        Button {
                            move(to: batch)
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: batch.colorHex)).frame(width: 10, height: 10)
                                Text(batch.name.isEmpty ? "Batch" : batch.name)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Move to batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Cannot Move", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
    }

    private func move(to batch: Batch) {
        do {
            try MedicationService.moveToBatch(item, to: batch, in: context)
            dismiss()
        } catch MembershipError.alreadyInBatch {
            errorMessage = "This medication is already in that batch."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Regenerate the project so the new view file is in the target**

Run: `xcodegen generate`
Expected: "Created project at ..." with no errors.

- [ ] **Step 3: Add sheet state + enum cases to MedicationDetailView**

In `PillDaddy/Views/Meds/MedicationDetailView.swift`, replace the existing `@State private var sheet: DetailSheet?` declaration **and** the `DetailSheet` enum (lines 9-15) — as one contiguous block — with the following (adds a `movingItem` state and an `addToBatch` case):

```swift
    @State private var sheet: DetailSheet?
    @State private var movingItem: BatchItem?

    enum DetailSheet: Identifiable {
        case edit, dose, instructions, swap, lifecycle, addToBatch
        var id: Int { hashValue }
    }
```

- [ ] **Step 4: Replace the read-only "Taken in" section with an editable "Schedule" section**

In `MedicationDetailView`, replace the entire `if medication.isActive && !(medication.batchItems ?? []).isEmpty { Section("Taken in") { ... } }` block (lines 34-47) with:

```swift
            if medication.isActive && !medication.isPRN {
                Section("Schedule") {
                    ForEach(medication.batchItems ?? []) { item in
                        Menu {
                            Button("Move to another batch…") { movingItem = item }
                            Button("Remove from batch", role: .destructive) {
                                try? MedicationService.removeFromBatch(item, in: context)
                            }
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: item.batch?.colorHex ?? "#8E8E93"))
                                    .frame(width: 10, height: 10)
                                Text(item.batch?.name ?? "—")
                                Spacer()
                                Text("\(DoseFormat.qty(item.quantity)) \(medication.form)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Add to batch…") { sheet = .addToBatch }
                        .disabled(DoseAllocation.remaining(medication) <= 0)
                }
            }
```

- [ ] **Step 5: Wire up the new sheets**

In `MedicationDetailView`, add the new case to the existing `.sheet(item: $sheet)` switch (after the `.lifecycle` case, ~line 86):

```swift
            case .addToBatch: AddToBatchSheet(medication: medication)
```

Then add a second sheet modifier right after the `.sheet(item: $sheet) { ... }` block (~line 88):

```swift
        .sheet(item: $movingItem) { item in
            MoveBatchSheet(item: item)
        }
```

- [ ] **Step 6: Verify the build**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build -quiet`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add PillDaddy/Views/Meds/BatchMembershipSheets.swift PillDaddy/Views/Meds/MedicationDetailView.swift project.yml PillDaddy.xcodeproj
git commit -m "feat(allocation): manage batch membership (add/move/remove) from medication detail"
```

---

## Task 8: Full suite verification

**Files:** none (verification only).

- [ ] **Step 1: Regenerate and run the entire test suite**

Run:
```bash
xcodegen generate
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' test -quiet
```
Expected: TEST SUCCEEDED — all suites green, including the new tests in Tasks 1–5.

- [ ] **Step 2: Manual smoke check (simulator)**

Launch the app and verify:
1. Meds → a batch's Edit → "Delete batch" is disabled with the caption while active meds remain; remove them, then delete works and dismisses.
2. A medication detail → "Schedule" section: "Add to batch…" places it (capped by remaining allocation); a membership's menu offers Move (lists only other batches) and Remove.
3. Each add/move/remove appears in the med's "Full history & notes" as a "Schedule changed" entry.
4. Today tab PRN section still shows only genuine PRN doses.

- [ ] **Step 3: Commit any fixes**

If the smoke check surfaced issues, fix them, re-run Step 1, and commit:

```bash
git add -A
git commit -m "fix(allocation): address membership/deletion smoke-check findings"
```
