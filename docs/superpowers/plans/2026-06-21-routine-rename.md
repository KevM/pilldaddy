# Routine Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the app's ubiquitous language around "Routine" — rename the `Batch` entity to `Routine`, `BatchItem` to `RoutineItem`, and the "Regime" umbrella to "Routines" — while folding in store-reset-only schema improvements (stable `uuid`s, `rxNormCode`, and removal of dead fields).

**Architecture:** SwiftData `@Model` entities renamed via a destructive store reset (no migration plan). The work is sequenced so the project compiles and the test suite stays green at every commit: additive schema changes first, field removals second, then the entity rename, then dependent-symbol and copy renames, then identifier/widget plumbing.

**Tech Stack:** Swift, SwiftUI, SwiftData, CloudKit, XcodeGen, Swift Testing (`import Testing`).

---

## Conventions for every task

- **Build:** `xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Test:** `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Regenerate project after any file add/rename/delete:** `xcodegen generate`
- New tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) — never XCTest.
- Commit after each task.

### Master identifier map (used by Tasks 4–6)

| Old | New |
|---|---|
| `Batch` (type) | `Routine` |
| `BatchItem` (type) | `RoutineItem` |
| `Medication.batchItems` | `Medication.routineItems` |
| `.batchItem` (DoseLog property) | `.routineItem` |
| `.batch` (RoutineItem property, BatchDay property, locals) | `.routine` |
| `BatchError` | `RoutineError` |
| `.alreadyInBatch` | `.alreadyInRoutine` |
| `addToBatch / removeFromBatch / moveToBatch / deleteBatch` | `addToRoutine / removeFromRoutine / moveToRoutine / deleteRoutine` |
| `DayQuery.BatchState / BatchDay / batchDays / recurs(_:on:) / slotDate(for:on:)` | `RoutineState / RoutineDay / routineDays / recurs / slotDate` |
| `RegimeQuery / BatchGroup / activeBatchGroups` | `RoutineQuery / RoutineGroup / activeRoutineGroups` |
| `RegimeView` | `RoutinesView` |
| `BatchEditor` | `RoutineEditor` |
| `AddToBatchSheet / MoveBatchSheet` | `AddToRoutineSheet / MoveRoutineSheet` |
| `BatchLogCard` | `RoutineLogCard` |
| `BatchTakenConfirmSheet` | `RoutineTakenConfirmSheet` |
| `MedsView.Mode.regime = "Regime"` | `MedsView.Mode.routines = "Routines"` |
| locals `batch / batches / editingBatch / batchDay / batchDays` | `routine / routines / editingRoutine / routineDay / routineDays` |
| `pendingBatchUUID` | `pendingRoutineUUID` |
| `batchID / batchName` (PillReminderAttributes) | `routineID / routineName` |
| userInfo key `"batchUUID"`, URL host `batch`, scheme path `pilldaddy://batch/` | `"routineUUID"`, `routine`, `pilldaddy://routine/` |

---

## Task 1: Baseline green

**Files:** none (verification only)

- [ ] **Step 1: Confirm a clean starting point**

Run: `git status` — expected: on branch `routine-rename`, clean tree (the design spec already committed).

- [ ] **Step 2: Build and test the current tree**

Run the Build command, then the Test command (see Conventions).
Expected: BUILD SUCCEEDED and all tests pass. This is the green baseline every later task must preserve.

---

## Task 2: Add stable identifiers and `rxNormCode` (additive)

**Files:**
- Modify: `PillDaddy/Models/Medication.swift`
- Modify: `PillDaddy/Models/DoseLog.swift`
- Test: `PillDaddyTests/IdentifierDefaultsTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/IdentifierDefaultsTests.swift`:

```swift
import Testing
import Foundation
@testable import PillDaddy

@Suite struct IdentifierDefaultsTests {
    @Test func medicationsGetDistinctUUIDs() {
        let a = Medication(name: "A")
        let b = Medication(name: "B")
        #expect(a.uuid != b.uuid)
    }

    @Test func medicationRxNormCodeDefaultsEmpty() {
        #expect(Medication(name: "A").rxNormCode == "")
    }

    @Test func doseLogsGetDistinctUUIDs() {
        #expect(DoseLog().uuid != DoseLog().uuid)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/IdentifierDefaultsTests`
Expected: FAIL — compile error, `Medication` has no member `uuid`/`rxNormCode`, `DoseLog` has no member `uuid`.

- [ ] **Step 3: Add the fields to `Medication`**

In `PillDaddy/Models/Medication.swift`, add stored properties just below `var discontinuedAt`:

```swift
    var uuid: UUID = UUID()
    var rxNormCode: String = ""            // RXCUI; empty until RxNorm lookup is wired up
```

Add matching init parameters (end of the parameter list, before `)`):

```swift
         createdAt: Date = .now, discontinuedAt: Date? = nil,
         uuid: UUID = UUID(), rxNormCode: String = "") {
```

And in the init body:

```swift
        self.uuid = uuid
        self.rxNormCode = rxNormCode
```

- [ ] **Step 4: Add the field to `DoseLog`**

In `PillDaddy/Models/DoseLog.swift`, add below `var notes`:

```swift
    var uuid: UUID = UUID()
```

Add init parameter (after `notes: String = ""`):

```swift
                 notes: String = "", uuid: UUID = UUID(),
```

And in the init body (after `self.notes = notes`):

```swift
        self.uuid = uuid
```

- [ ] **Step 5: Regenerate, build, and run the test**

Run: `xcodegen generate`
Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/IdentifierDefaultsTests`
Expected: PASS.

- [ ] **Step 6: Full test suite**

Run the Test command (full). Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add PillDaddy/Models/Medication.swift PillDaddy/Models/DoseLog.swift PillDaddyTests/IdentifierDefaultsTests.swift project.yml PillDaddy.xcodeproj
git commit -m "feat: add stable uuid to Medication/DoseLog and empty rxNormCode to Medication"
```

---

## Task 3: Drop write-only `DoseLog.snapshotBatchColorHex`

**Files:**
- Modify: `PillDaddy/Models/DoseLog.swift`
- Modify: `PillDaddy/Services/DoseLogService.swift:73,110`
- Modify: `PillDaddy/Helpers/SeedData.swift:82,87`

- [ ] **Step 1: Remove the property from `DoseLog`**

In `PillDaddy/Models/DoseLog.swift`:
- Delete the line `var snapshotBatchColorHex: String = ""`.
- Delete `snapshotBatchColorHex: String = "",` from the init parameter list.
- Delete `self.snapshotBatchColorHex = snapshotBatchColorHex` from the init body.

- [ ] **Step 2: Remove the writes in `DoseLogService`**

In `PillDaddy/Services/DoseLogService.swift`:
- In `logPRN` (~line 73), change `snapshotBatchColorHex: "", isPRN: true,` to `isPRN: true,`.
- Delete the assignment line `log.snapshotBatchColorHex = item.batch?.colorHex ?? ""` (~line 110).

- [ ] **Step 3: Remove the writes in `SeedData`**

In `PillDaddy/Helpers/SeedData.swift`, delete both `snapshotBatchColorHex: blue.colorHex,` lines (~82 and ~87).

- [ ] **Step 4: Confirm the field is gone**

Run: `grep -rn "snapshotBatchColorHex" --include="*.swift" .`
Expected: no output.

- [ ] **Step 5: Build and test**

Run the Build command, then the Test command. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add PillDaddy/Models/DoseLog.swift PillDaddy/Services/DoseLogService.swift PillDaddy/Helpers/SeedData.swift
git commit -m "refactor: drop write-only DoseLog.snapshotBatchColorHex"
```

---

## Task 4: Drop `Batch.sortOrder`; sort routines by time of day

**Files:**
- Modify: `PillDaddy/Models/Batch.swift`
- Modify (sort sites): `PillDaddy/Views/Today/TodayView.swift:10`, `PillDaddy/Views/Meds/RegimeView.swift:6`, `PillDaddy/Views/Meds/MedicationEditor.swift:17`, `PillDaddy/Views/Meds/BatchMembershipSheets.swift:11,90`, `PillDaddy/Services/RegimeQuery.swift:18`, `PillDaddy/Views/Today/IndividualAdjustSheet.swift:113`, `PillDaddy/Views/Today/BatchTakenConfirmSheet.swift:125`, `PillDaddy/Views/Today/BatchLogCard.swift:99`
- Modify: `PillDaddy/Helpers/SeedData.swift:19-25`
- Test: `PillDaddyTests/RegimeQueryTests.swift`

> Note: this task is performed while the type is still named `Batch` (the rename is Task 5). `Batch` already has a `uuid` field, used here as the stable tiebreaker.

- [ ] **Step 1: Write the failing ordering test**

In `PillDaddyTests/RegimeQueryTests.swift`, add:

```swift
    @Test @MainActor func activeBatchGroupsSortByTimeOfDay() throws {
        let container = try ModelContainer(
            for: PillDaddySchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        func at(_ h: Int) -> Date { Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)! }
        ctx.insert(Batch(name: "Evening", timeOfDay: at(19)))
        ctx.insert(Batch(name: "Morning", timeOfDay: at(7)))
        ctx.insert(Batch(name: "Midday", timeOfDay: at(12)))
        try ctx.save()

        let names = try RegimeQuery.activeBatchGroups(in: ctx).map { $0.batch.name }
        #expect(names == ["Morning", "Midday", "Evening"])
    }
```

(If `Batch.init` no longer accepts `sortOrder`, that is expected — it is removed in Step 3.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/RegimeQueryTests`
Expected: FAIL (ordering depends on `sortOrder`, which defaults to 0 for all three, so SwiftData returns insertion order, not time order).

- [ ] **Step 3: Remove `sortOrder` from `Batch`**

In `PillDaddy/Models/Batch.swift`:
- Delete `var sortOrder: Int = 0`.
- Delete `sortOrder: Int = 0` from the init parameter list (and the trailing comma fix on the line above).
- Delete `self.sortOrder = sortOrder` from the init body.

- [ ] **Step 4: Update every sort site**

Replace the `@Query`/`FetchDescriptor` sort arrays:

- The five `@Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])` sites (TodayView:10, RegimeView:6, MedicationEditor:17, BatchMembershipSheets:11 and :90) become:

```swift
    @Query(sort: [SortDescriptor(\Batch.timeOfDay), SortDescriptor(\Batch.uuid)])
```

- `RegimeQuery.swift:18` `sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timeOfDay)]` becomes:

```swift
            sortBy: [SortDescriptor(\.timeOfDay), SortDescriptor(\.uuid)]))
```

- The three `FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.sortOrder)])` sites (IndividualAdjustSheet:113, BatchTakenConfirmSheet:125, BatchLogCard:99) become:

```swift
        FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.timeOfDay), SortDescriptor(\.uuid)]))
```

- [ ] **Step 5: Remove `sortOrder` arguments from `SeedData`**

In `PillDaddy/Helpers/SeedData.swift` (~lines 19–25), delete the `, sortOrder: 0/1/2` arguments from the three `Batch(...)` constructions.

- [ ] **Step 6: Update stale comments**

In `RegimeQuery.swift` change the doc comment "ordered by sortOrder then time" to "ordered by time of day". In `DayQuery.swift` the comment "in their stored order" → "in time-of-day order".

- [ ] **Step 7: Confirm `sortOrder` is gone and run the test**

Run: `grep -rn "sortOrder" --include="*.swift" .` — Expected: no output.
Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/RegimeQueryTests`
Expected: PASS.

- [ ] **Step 8: Full test suite**

Run the Test command (full). Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: drop Batch.sortOrder; sort routines by timeOfDay"
```

---

## Task 5: Rename entities `Batch`→`Routine`, `BatchItem`→`RoutineItem`

This task renames the two `@Model` classes and every type/property/keypath reference so the project compiles. Dependent **symbol** names (method names, helper structs, view files, "Regime") are renamed in Task 6.

**Files (definitions — shown in full below):**
- Rename: `PillDaddy/Models/Batch.swift` → `PillDaddy/Models/Routine.swift`
- Rename: `PillDaddy/Models/BatchItem.swift` → `PillDaddy/Models/RoutineItem.swift`
- Modify: `PillDaddy/Models/DoseLog.swift`, `PillDaddy/Models/Medication.swift`, `PillDaddy/Models/PillDaddySchema.swift`
- Modify (references): all files listed by the grep in Step 7.

- [ ] **Step 1: Rename the two model files**

```bash
git mv PillDaddy/Models/Batch.swift PillDaddy/Models/Routine.swift
git mv PillDaddy/Models/BatchItem.swift PillDaddy/Models/RoutineItem.swift
```

- [ ] **Step 2: Rewrite `Routine.swift`**

Full contents (note `items` relationship name is kept; only types/keypaths change):

```swift
import Foundation
import SwiftData

@Model
final class Routine {
    var name: String = ""
    var colorHex: String = "#3B82F6"
    var timeOfDay: Date = Date.now          // only the clock-time component is meaningful
    var mealRelation: String = MealRelation.none.rawValue
    var recurrenceKind: String = RecurrenceKind.daily.rawValue
    var weekdays: [Int]? = nil              // 1...7 when recurrenceKind == "weekdays"
    var uuid: UUID = UUID()

    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine)
    var items: [RoutineItem]? = []

    init(name: String = "", colorHex: String = "#3B82F6", timeOfDay: Date = .now,
         mealRelation: MealRelation = .none, recurrenceKind: RecurrenceKind = .daily,
         weekdays: [Int]? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.timeOfDay = timeOfDay
        self.mealRelation = mealRelation.rawValue
        self.recurrenceKind = recurrenceKind.rawValue
        self.weekdays = weekdays
    }
}
```

- [ ] **Step 3: Rewrite `RoutineItem.swift`**

```swift
import Foundation
import SwiftData

@Model
final class RoutineItem {
    var quantity: Double = 1.0              // fractions allowed (0.5)
    var instructionsOverride: String = ""

    var medication: Medication? = nil
    var routine: Routine? = nil

    @Relationship(deleteRule: .nullify, inverse: \DoseLog.routineItem)
    var doseLogs: [DoseLog]? = []

    init(quantity: Double = 1.0, instructionsOverride: String = "",
         medication: Medication? = nil, routine: Routine? = nil) {
        self.quantity = quantity
        self.instructionsOverride = instructionsOverride
        self.medication = medication
        self.routine = routine
    }
}
```

- [ ] **Step 4: Update `DoseLog.swift`**

Change `var batchItem: BatchItem? = nil` to `var routineItem: RoutineItem? = nil`; rename the `batchItem:` init parameter to `routineItem:` and `self.batchItem = batchItem` to `self.routineItem = routineItem`.

- [ ] **Step 5: Update `Medication.swift`**

Change the relationship to:

```swift
    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.medication)
    var routineItems: [RoutineItem]? = []
```

- [ ] **Step 6: Update the schema**

In `PillDaddy/Models/PillDaddySchema.swift`, change `Batch.self,` → `Routine.self,` and `BatchItem.self,` → `RoutineItem.self,`.

- [ ] **Step 7: Mechanically update all remaining references**

Apply these replacements across the listed files (use the editor's find/replace per file; whole-word where noted):

- `BatchItem` → `RoutineItem` (type)
- `Batch` → `Routine` (type — whole word; do **not** touch `BatchError`, `BatchDay`, `BatchState`, `BatchGroup`, `batchDays`, view/file names, or string literals yet — those are Task 6)
- `.batchItem` → `.routineItem`  •  `batchItem:` → `routineItem:`
- `.batchItems` → `.routineItems`
- `item.batch` → `item.routine`  •  `.batch?` → `.routine?` where the receiver is a `RoutineItem`
- `batchItem` local/param names → `routineItem`

Files to edit (from the codebase grep): `PillDaddy/Services/DoseLogService.swift`, `PillDaddy/Services/RegimeQuery.swift`, `PillDaddy/Services/DayQuery.swift`, `PillDaddy/Services/MedicationService.swift`, `PillDaddy/Services/DoseAllocation.swift`, `PillDaddy/Services/MissedReconciler.swift`, `PillDaddy/Services/ReminderScheduler.swift`, `PillDaddy/Services/ReminderSync.swift`, `PillDaddy/Services/LiveActivityController.swift`, `PillDaddy/PillDaddyApp.swift`, `PillDaddy/Helpers/SeedData.swift`, and the Views under `PillDaddy/Views/Today` and `PillDaddy/Views/Meds` that reference these types, plus every file under `PillDaddyTests/`.

> The `DayQuery.BatchDay.batch` property and `RegimeQuery.BatchGroup.batch` property keep the name `batch` for now (only their **type** becomes `Routine`); they are renamed to `routine` in Task 6. Leaving them avoids touching their call sites twice.

- [ ] **Step 8: Regenerate and verify no stray entity-type references remain**

Run: `xcodegen generate`
Run: `grep -rnw "Batch\|BatchItem" --include="*.swift" PillDaddy/Models`
Expected: no output (model layer fully renamed).

- [ ] **Step 9: Build and test**

Run the Build command, then the Test command. Expected: all pass. (Test bodies still reference `Batch()`/`RegimeQuery` etc.; those compile because only the entity type changed — `Batch` no longer exists, so any remaining `Batch(` in tests must have been replaced with `Routine(` in Step 7. If the build fails on `Batch`, finish those replacements.)

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: rename Batch->Routine and BatchItem->RoutineItem entities"
```

---

## Task 6: Rename dependent symbols and "Regime"→"Routines"

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift`, `PillDaddy/Services/DayQuery.swift`
- Rename: `PillDaddy/Services/RegimeQuery.swift` → `RoutineQuery.swift`; `PillDaddy/Views/Meds/RegimeView.swift` → `RoutinesView.swift`; `PillDaddy/Views/Meds/BatchEditor.swift` → `RoutineEditor.swift`; `PillDaddy/Views/Meds/BatchMembershipSheets.swift` → `RoutineMembershipSheets.swift`; `PillDaddy/Views/Today/BatchLogCard.swift` → `RoutineLogCard.swift`; `PillDaddy/Views/Today/BatchTakenConfirmSheet.swift` → `RoutineTakenConfirmSheet.swift`
- Rename: `PillDaddyTests/BatchRelationshipTests.swift` → `RoutineRelationshipTests.swift`; `PillDaddyTests/RegimeQueryTests.swift` → `RoutineQueryTests.swift`
- Modify: `PillDaddy/Views/Meds/MedsView.swift` and all call sites

- [ ] **Step 1: Rename the files**

```bash
git mv PillDaddy/Services/RegimeQuery.swift PillDaddy/Services/RoutineQuery.swift
git mv PillDaddy/Views/Meds/RegimeView.swift PillDaddy/Views/Meds/RoutinesView.swift
git mv PillDaddy/Views/Meds/BatchEditor.swift PillDaddy/Views/Meds/RoutineEditor.swift
git mv PillDaddy/Views/Meds/BatchMembershipSheets.swift PillDaddy/Views/Meds/RoutineMembershipSheets.swift
git mv PillDaddy/Views/Today/BatchLogCard.swift PillDaddy/Views/Today/RoutineLogCard.swift
git mv PillDaddy/Views/Today/BatchTakenConfirmSheet.swift PillDaddy/Views/Today/RoutineTakenConfirmSheet.swift
git mv PillDaddyTests/BatchRelationshipTests.swift PillDaddyTests/RoutineRelationshipTests.swift
git mv PillDaddyTests/RegimeQueryTests.swift PillDaddyTests/RoutineQueryTests.swift
```

- [ ] **Step 2: Rename `MedicationService` symbols**

In `PillDaddy/Services/MedicationService.swift`: `enum BatchError` → `enum RoutineError`; `case alreadyInBatch` → `case alreadyInRoutine`; `addToBatch` → `addToRoutine`; `removeFromBatch` → `removeFromRoutine`; `moveToBatch` → `moveToRoutine`; `deleteBatch` → `deleteRoutine`. Update any parameter labels `batch:` → `routine:`.

- [ ] **Step 3: Rename `DayQuery` symbols**

In `PillDaddy/Services/DayQuery.swift`: `enum BatchState` → `RoutineState`; `struct BatchDay` → `RoutineDay` with its `let batch: Routine` property → `let routine: Routine` (and `batch.persistentModelID` → `routine.persistentModelID`, `batch.recurrenceKind`/`.weekdays`/`.timeOfDay`/`.items` accessors updated accordingly); `recurs(_ batch:` → `recurs(_ routine:`; `slotDate(for batch:` → `slotDate(for routine:`; `batchDays(from:on:)` → `routineDays(from:on:)`; rename the local `batch` iteration variables to `routine`.

- [ ] **Step 4: Rename `RoutineQuery` symbols**

In `PillDaddy/Services/RoutineQuery.swift` (renamed file): `enum RegimeQuery` → `enum RoutineQuery`; `struct BatchGroup` → `struct RoutineGroup` with `let batch: Routine` → `let routine: Routine` (and `batch.persistentModelID` → `routine.persistentModelID`); `activeBatchGroups` → `activeRoutineGroups`; rename local `batch`/`batches` → `routine`/`routines`.

- [ ] **Step 5: Rename view structs and `MedsView` mode**

- `struct RegimeView` → `struct RoutinesView` (in the renamed file), updating the `editingBatch` state to `editingRoutine` and local `batch(es)` → `routine(s)`.
- `struct BatchEditor` → `struct RoutineEditor`; `struct AddToBatchSheet` → `AddToRoutineSheet`; `struct MoveBatchSheet` → `MoveRoutineSheet`; `struct BatchLogCard` → `RoutineLogCard`; `struct BatchTakenConfirmSheet` → `RoutineTakenConfirmSheet`.
- In `PillDaddy/Views/Meds/MedsView.swift`: `case regime = "Regime"` → `case routines = "Routines"`; rename `mode == .regime` checks to `.routines`; update the `RegimeView()` reference to `RoutinesView()`.

- [ ] **Step 6: Update all call sites for the renamed symbols**

Apply across `PillDaddy/` and `PillDaddyTests/`: `RegimeQuery` → `RoutineQuery`, `BatchGroup` → `RoutineGroup`, `activeBatchGroups` → `activeRoutineGroups`, `BatchDay` → `RoutineDay`, `BatchState` → `RoutineState`, `batchDays` → `routineDays`, `BatchError` → `RoutineError`, `alreadyInBatch` → `alreadyInRoutine`, `addToBatch`→`addToRoutine`, `removeFromBatch`→`removeFromRoutine`, `moveToBatch`→`moveToRoutine`, `deleteBatch`→`deleteRoutine`, `RegimeView`→`RoutinesView`, `BatchEditor`→`RoutineEditor`, `AddToBatchSheet`→`AddToRoutineSheet`, `MoveBatchSheet`→`MoveRoutineSheet`, `BatchLogCard`→`RoutineLogCard`, `BatchTakenConfirmSheet`→`RoutineTakenConfirmSheet`, and `.batch`→`.routine` on `RoutineDay`/`RoutineGroup` receivers, plus locals `editingBatch`→`editingRoutine`, `batchDay`→`routineDay`.

- [ ] **Step 7: Regenerate and build**

Run: `xcodegen generate`
Run the Build command. Expected: BUILD SUCCEEDED. Fix any remaining unresolved symbols until it builds.

- [ ] **Step 8: Add an explicit history-preservation test**

In `PillDaddyTests/RoutineRelationshipTests.swift`, ensure there is a test asserting dose history survives routine deletion:

```swift
    @Test @MainActor func deletingRoutineKeepsDoseLogs() throws {
        let container = try ModelContainer(
            for: PillDaddySchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let med = Medication(name: "Test")
        let routine = Routine(name: "Morning")
        let item = RoutineItem(medication: med, routine: routine)
        let log = DoseLog(status: .taken, medication: med, routineItem: item)
        [med, routine, item, log].forEach { ctx.insert($0) }
        try ctx.save()

        try MedicationService.deleteRoutine(routine, in: ctx)
        try ctx.save()

        let logs = try ctx.fetch(FetchDescriptor<DoseLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.routineItem == nil)
    }
```

(Adjust `DoseLog`/`MedicationService.deleteRoutine` argument labels to match the actual signatures if they differ.)

- [ ] **Step 9: Run the full test suite**

Run the Test command (full). Expected: all pass.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: rename Regime->Routines and Batch-named symbols/views to Routine"
```

---

## Task 7: User-facing copy, deep links, notifications, and Live Activity

**Files:**
- Modify: `PillDaddy/Shared/PillReminderAttributes.swift`
- Modify: `PillDaddyWidgets/PillReminderLiveActivity.swift`
- Modify: `PillDaddy/PillDaddyApp.swift`, `PillDaddy/Services/AppRouter.swift`, `PillDaddy/Services/ReminderScheduler.swift`, `PillDaddy/Services/ReminderSync.swift`, `PillDaddy/Services/LiveActivityController.swift`
- Modify (copy): the Views/Services listed in the design spec's "User-facing copy" section

- [ ] **Step 1: Rename Live Activity attributes**

In `PillDaddy/Shared/PillReminderAttributes.swift`: `let batchID: String` → `let routineID: String`; `let batchName: String` → `let routineName: String`; update the doc comments ("overdue batch" → "overdue routine"). In `PillDaddyWidgets/PillReminderLiveActivity.swift`: `context.attributes.batchName` → `routineName` (both sites), `context.attributes.batchID` → `routineID`, and `URL(string: "pilldaddy://batch/\(...)")` → `"pilldaddy://routine/\(...)"` (both sites).

- [ ] **Step 2: Rename deep-link / notification identifiers**

- `PillDaddy/Services/AppRouter.swift`: `pendingBatchUUID` → `pendingRoutineUUID` (and its doc comment).
- `PillDaddy/PillDaddyApp.swift`: `userInfo["batchUUID"]` → `userInfo["routineUUID"]`; `router.pendingBatchUUID` → `pendingRoutineUUID`; `url.host == "batch"` → `url.host == "routine"`; the comment "focus the batch" → "focus the routine".
- `PillDaddy/Services/ReminderScheduler.swift`: wherever the notification `userInfo` sets `"batchUUID"`, change the key to `"routineUUID"`; update the LiveActivity attribute construction to use `routineID`/`routineName`; update notification body strings (`"\(routine.name) is due"`, `"\(routine.name) coming up"`, `"\(routine.name) still due"`) and the identifier-format string `"\(routine.uuid.uuidString)|..."`.
- `PillDaddy/Services/ReminderSync.swift` and `LiveActivityController.swift`: update any remaining `batch`-named locals and the `routineID`/`routineName` attribute usage.
- Update `TodayView` (the consumer of `pendingRoutineUUID`).

- [ ] **Step 3: Update user-facing strings**

Apply the replacements from the design spec's "User-facing copy" section across the Views and Services (sentence case preserved). Key ones: `"Regime"`→`"Routines"`; `"Add batch"`/`"New batch"`→`"Add routine"`/`"New routine"`; `"Edit batch"`→`"Edit routine"`; `"Delete batch"`/`"Delete this batch?"`→`"Delete routine"`/`"Delete this routine?"`; `"Pills in this batch"`→`"Pills in this routine"`; `"Add to batch…"`/`"Move to another batch…"`/`"Move to batch"`→ routine forms; `"No batches yet — add one from the Meds tab."`→`"No routines yet — add one from the Meds tab."`; `"No other batches to move to."`→`"No other routines to move to."`; `"This medication is already in every batch."`/`"…in that batch."`→ routine; `"Total allocation across batches cannot exceed the daily dose target."`→`"…across routines…"`; `"Schedules notifications and a Live Activity for each batch."`→`"…each routine."`; `"How long after a batch's time before a dose is marked missed."`→`"…a routine's time…"`; `"Converted medication to PRN (cleared scheduled batches)"`→`"…cleared scheduled routines)"`; `"Discontinuing removes this medication from the active regime. Its full history is kept."`→`"…from your active routines. …"`; `"Reactivating restores this medication to the active regime."`→`"…to your active routines."`; `"\(doneCount) of \(batchDays.count) batches done"`→`"\(doneCount) of \(routineDays.count) routines done"`; `"Adjust \(batchDay.batch.name)"`→`"Adjust \(routineDay.routine.name)"`.

- [ ] **Step 4: Verify no residual "batch"/"regime" remain**

Run: `grep -rni "batch\|regime" --include="*.swift" PillDaddy PillDaddyWidgets PillDaddyTests`
Expected: no output. (PRN and all other terminology are unaffected.)

- [ ] **Step 5: Regenerate, build, and test**

Run: `xcodegen generate`
Run the Build command, then the Test command. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename batch->routine in copy, deep links, notifications, and Live Activity"
```

---

## Task 8: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Clean regenerate and full build**

Run: `xcodegen generate`
Run the Build command (app + widget + tests all compile). Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Full test suite on iPhone 17**

Run the Test command. Expected: all tests pass.

- [ ] **Step 3: Destructive-reset smoke test**

In the iPhone 17 simulator: delete the existing PillDaddy app (clears the stale `Batch` store), then run the app from Xcode. Confirm:
- The app launches without the container `fatalError`.
- Seed data loads; the **Routines** segment (formerly "Regime") and Today tab render.
- Creating, editing, and deleting a routine works; deleting a routine with logged doses keeps the dose history.

- [ ] **Step 4: Note CloudKit reset (manual, out of band)**

Reset the CloudKit **development** environment schema in the CloudKit Console so the new `Routine`/`RoutineItem` record types and the new fields are provisioned. (Not automatable from this plan.)

- [ ] **Step 5: Final residual grep**

Run: `grep -rni "batch\|regime" --include="*.swift" .`
Expected: no output across the whole repo.

- [ ] **Step 6: Confirm branch state**

Run: `git log --oneline origin/main..HEAD` (or `git log --oneline -8`) — expected: the spec commit plus Tasks 2–7 commits, tree clean.
```

---

## Self-review notes

- **Spec coverage:** rename (Tasks 5–7), destructive reset (Tasks 5 + 8), `uuid` on Medication/DoseLog + `rxNormCode` (Task 2), drop `snapshotBatchColorHex` (Task 3), drop `sortOrder` + sort by `timeOfDay` (Task 4), history-preservation behavior (Task 6 Step 8), not-changed list respected (PRN/enums/`timeOfDay`/`weekdays` untouched), verification incl. iPhone 17 + delete-reinstall + CloudKit note (Task 8). All covered.
- **Ordering:** additive (Task 2) → removals (Tasks 3–4) → entity rename (Task 5) → symbol/copy renames (Tasks 6–7) keeps the tree compiling and green at every commit.
