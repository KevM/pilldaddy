# Daily Dose Allocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each medication a prescribed daily-dose target (in unit counts) and a structured strength, so batch allocation can be validated against the target, under/over-allocation is badged, and total medicine received is captured per dose for later reporting.

**Architecture:** `Medication.strength` (free text) is split into `strengthValue: Double` + `strengthUnit: String`, and a `dailyDoseTarget: Double` (counts/day) is added. A pure `DoseAllocation` helper owns the comparison + derived-mg math; `MedicationService` enforces the count cap on mutations; SwiftUI editors and a caution badge mirror that logic. `DoseLog` additionally freezes the numeric strength at log time.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (+ CloudKit), Swift Testing (`import Testing`), XcodeGen.

---

## Build & Test Commands (reference)

This project uses XcodeGen — **after creating or deleting any `.swift` file you MUST regenerate the project** or the new file won't be in the target:

```bash
xcodegen generate
```

Pick an installed iOS 26 simulator once and reuse its name (list them with `xcrun simctl list devices available`). Examples below use `iPhone 16 Pro` — substitute a name that exists on your machine.

```bash
# Full build
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Full test run
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet

# Single test suite (Swift Testing struct)
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:PillDaddyTests/DoseAllocationTests -quiet
```

Editing existing files does **not** require `xcodegen generate`; only adding/removing files does.

---

## File Structure

**New files:**
- `PillDaddy/Services/DoseAllocation.swift` — pure allocation/derived-strength logic (Task 2).
- `PillDaddy/Views/Meds/DoseQuantityField.swift` — reusable stepper/manual-entry input (Task 4).
- `PillDaddy/Views/Meds/DoseAllocationBadge.swift` — caution badge view (Task 8).
- `PillDaddyTests/DoseAllocationTests.swift` — helper tests (Task 2).

**Modified (core):**
- `PillDaddy/Models/Medication.swift` — structured strength + target (Task 1).
- `PillDaddy/Models/DoseLog.swift` — numeric strength snapshot (Task 9).
- `PillDaddy/Services/MedicationService.swift` — signatures + validation (Tasks 1, 3).
- `PillDaddy/Services/DoseLogService.swift` — feed snapshots (Tasks 1, 9).

**Modified (views / display reads):**
- `PillDaddy/Views/Meds/MedicationEditor.swift` (Tasks 1, 5)
- `PillDaddy/Views/Meds/ChangeDoseSheet.swift` (Tasks 1, 7)
- `PillDaddy/Views/Meds/SwapSheet.swift` (Task 1)
- `PillDaddy/Views/Meds/BatchEditor.swift` (Task 6)
- `PillDaddy/Views/Meds/MedicationDetailView.swift` (Tasks 1, 8)
- `PillDaddy/Views/Meds/AllMedsView.swift` (Tasks 1, 8)
- `PillDaddy/Views/Meds/RegimeView.swift` (Tasks 1, 8)
- `PillDaddy/Views/Today/PRNCard.swift` (Task 1)
- `PillDaddy/Helpers/SeedData.swift` (Task 1)

**Modified (tests — constructor/signature updates):**
- `PillDaddyTests/MedicationServiceTests.swift`, `MedicationModelTests.swift`, `DoseLogServiceTests.swift`, `DoseLogServicePRNTests.swift`, `DoseLogTests.swift`, `MedicationChangeEventTests.swift`, `MedicationLineageTests.swift`, `BatchRelationshipTests.swift`, `RegimeQueryTests.swift`, `DayQueryTests.swift`.

---

## Task 1: Structured strength + daily-dose field (breaking refactor)

This is the one atomic, build-breaking task: `Medication.strength` is replaced everywhere. Do all edits, then verify the project builds and **existing** tests still pass. No behavior change yet beyond storing the new fields.

**Files:**
- Modify: `PillDaddy/Models/Medication.swift`
- Modify: `PillDaddy/Services/MedicationService.swift`
- Modify: `PillDaddy/Services/DoseLogService.swift`
- Modify: `PillDaddy/Helpers/SeedData.swift`
- Modify: `PillDaddy/Views/Today/PRNCard.swift`, `Views/Meds/RegimeView.swift`, `Views/Meds/AllMedsView.swift`, `Views/Meds/MedicationDetailView.swift`, `Views/Meds/MedicationEditor.swift`, `Views/Meds/ChangeDoseSheet.swift`, `Views/Meds/SwapSheet.swift`
- Modify tests: all files listed under "Modified (tests)" above

- [ ] **Step 1: Rewrite the Medication model**

Replace the entire body of `PillDaddy/Models/Medication.swift` properties + init with:

```swift
import Foundation
import SwiftData

@Model
final class Medication {
    var name: String = ""
    var strengthValue: Double = 0          // amount per unit, e.g. 30
    var strengthUnit: String = "mg"        // label only; never converted across units
    var dailyDoseTarget: Double = 1        // prescribed units per full dosing day (count)
    var form: String = "tablet"
    var generalNotes: String = ""
    var isActive: Bool = true
    var isPRN: Bool = false                // as-needed; no batch memberships
    var createdAt: Date = Date.now
    var discontinuedAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \BatchItem.medication)
    var batchItems: [BatchItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \DoseLog.medication)
    var doseLogs: [DoseLog]? = []

    @Relationship(deleteRule: .cascade, inverse: \MedicationChangeEvent.medication)
    var changeEvents: [MedicationChangeEvent]? = []

    /// The medication that replaced this one (swap continuity chain).
    var successor: Medication? = nil

    @Relationship(inverse: \Medication.successor)
    var predecessor: Medication? = nil

    /// Display-only formatted strength, e.g. "30 mg". Never used for math.
    var strengthDescription: String { "\(DoseFormat.qty(strengthValue)) \(strengthUnit)" }

    init(name: String = "", strengthValue: Double = 0, strengthUnit: String = "mg",
         dailyDoseTarget: Double = 1, form: String = "tablet",
         generalNotes: String = "", isActive: Bool = true, isPRN: Bool = false,
         createdAt: Date = .now, discontinuedAt: Date? = nil) {
        self.name = name
        self.strengthValue = strengthValue
        self.strengthUnit = strengthUnit
        self.dailyDoseTarget = dailyDoseTarget
        self.form = form
        self.generalNotes = generalNotes
        self.isActive = isActive
        self.isPRN = isPRN
        self.createdAt = createdAt
        self.discontinuedAt = discontinuedAt
    }
}
```

- [ ] **Step 2: Update MedicationService signatures + summaries**

In `PillDaddy/Services/MedicationService.swift`:

Change `addMedication`'s signature and the `Medication(...)` it builds. Replace the `strength: String` parameter with `strengthValue` + `strengthUnit`, and add a `dailyDoseTarget` parameter (default `1`):

```swift
    @discardableResult
    static func addMedication(
        name: String, strengthValue: Double, strengthUnit: String, form: String,
        isPRN: Bool, notes: String, dailyDoseTarget: Double = 1,
        placements: [(batch: Batch, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) -> Medication {
        let med = Medication(name: name, strengthValue: strengthValue, strengthUnit: strengthUnit,
                             dailyDoseTarget: dailyDoseTarget, form: form,
                             generalNotes: notes, isPRN: isPRN)
        context.insert(med)
        // ...unchanged body...
```

In `changeDose`, replace `newStrength: String` with `newStrengthValue: Double, newStrengthUnit: String` and the assignment:

```swift
    static func changeDose(
        _ med: Medication,
        newStrengthValue: Double, newStrengthUnit: String,
        newQuantities: [(item: BatchItem, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)
        let oldSummary = doseSummary(med)
        med.strengthValue = newStrengthValue
        med.strengthUnit = newStrengthUnit
        // ...unchanged...
```

In `swap`, replace `newStrength: String` with `newStrengthValue: Double, newStrengthUnit: String`, and update the new med + summary strings:

```swift
    static func swap(
        _ oldMed: Medication,
        newName: String, newStrengthValue: Double, newStrengthUnit: String, newForm: String,
        inheritSchedule: Bool,
        reason: String,
        in context: ModelContext
    ) throws -> Medication {
        try requireReason(reason)
        let newMed = Medication(name: newName, strengthValue: newStrengthValue,
                                strengthUnit: newStrengthUnit, form: newForm)
        context.insert(newMed)
        // ...inheritSchedule loop unchanged...
        let oldDescription = "\(oldMed.name) \(oldMed.strengthDescription)"
        // ...
        context.insert(MedicationChangeEvent(
            type: .swapped, reasoning: reason,
            oldValue: oldDescription,
            newValue: "\(newName) \(DoseFormat.qty(newStrengthValue)) \(newStrengthUnit)",
            medication: oldMed))
        // ...
```

In `doseSummary`, change the strength interpolation:

```swift
        return "\(med.strengthDescription) — \(schedule)"
```

- [ ] **Step 3: Update DoseLogService snapshot reads**

In `PillDaddy/Services/DoseLogService.swift`, both `snapshotStrength` assignments change from `.strength` to `.strengthDescription`:

- In `logPRN`: `snapshotStrength: med.strengthDescription,`
- In `upsert`: `log.snapshotStrength = item.medication?.strengthDescription ?? ""`

- [ ] **Step 4: Update display reads in views**

Replace `.strength` reads with `.strengthDescription`:
- `PillDaddy/Views/Today/PRNCard.swift:37` → `Text(dose.med.strengthDescription)`
- `PillDaddy/Views/Meds/RegimeView.swift:45` → `Text(med.strengthDescription)`
- `PillDaddy/Views/Meds/RegimeView.swift:69` → `Text(item.medication?.strengthDescription ?? "")`
- `PillDaddy/Views/Meds/AllMedsView.swift:71` → `guard med.isActive else { return med.strengthDescription }`
- `PillDaddy/Views/Meds/AllMedsView.swift:74` → `return med.strengthDescription + suffix`
- `PillDaddy/Views/Meds/MedicationDetailView.swift:20` → `LabeledContent("Strength", value: medication.strengthDescription)`

- [ ] **Step 5: Convert strength entry in the three editors to value + unit**

In `PillDaddy/Views/Meds/MedicationEditor.swift`:
- Replace `@State private var strength = ""` with:
  ```swift
  @State private var strengthValue = 0.0
  @State private var strengthUnit = "mg"
  ```
- Replace the add-mode strength field (the `if isAdd { TextField("Strength (e.g. 30mg)", text: $strength) }`) with:
  ```swift
  if isAdd {
      HStack {
          TextField("Strength", value: $strengthValue, format: .number)
              .keyboardType(.decimalPad)
          TextField("Unit", text: $strengthUnit)
              .frame(maxWidth: 80)
      }
  }
  ```
- In `load()`, replace `strength = med.strength` with:
  ```swift
  strengthValue = med.strengthValue
  strengthUnit = med.strengthUnit
  ```
- In `save()` `.add` case, change the `addMedication` call's `strength: strength` to `strengthValue: strengthValue, strengthUnit: strengthUnit`.

In `PillDaddy/Views/Meds/ChangeDoseSheet.swift`:
- Replace `@State private var strength = ""` with:
  ```swift
  @State private var strengthValue = 0.0
  @State private var strengthUnit = "mg"
  ```
- Replace the `TextField("Strength", text: $strength)` with:
  ```swift
  HStack {
      TextField("Strength", value: $strengthValue, format: .number)
          .keyboardType(.decimalPad)
      TextField("Unit", text: $strengthUnit).frame(maxWidth: 80)
  }
  ```
- Replace `.onAppear { strength = medication.strength }` with:
  ```swift
  .onAppear {
      strengthValue = medication.strengthValue
      strengthUnit = medication.strengthUnit
  }
  ```
- In `save()`, change the `changeDose` call: `newStrength: strength` → `newStrengthValue: strengthValue, newStrengthUnit: strengthUnit`.

In `PillDaddy/Views/Meds/SwapSheet.swift`:
- Replace `@State private var strength = ""` with:
  ```swift
  @State private var strengthValue = 0.0
  @State private var strengthUnit = "mg"
  ```
- Replace `TextField("Strength", text: $strength)` with:
  ```swift
  HStack {
      TextField("Strength", value: $strengthValue, format: .number)
          .keyboardType(.decimalPad)
      TextField("Unit", text: $strengthUnit).frame(maxWidth: 80)
  }
  ```
- In `save()`, change `newStrength: strength` → `newStrengthValue: strengthValue, newStrengthUnit: strengthUnit`.

- [ ] **Step 6: Update SeedData constructors**

In `PillDaddy/Helpers/SeedData.swift`, change each `Medication(...)` call's `strength: "<n><unit>"` to numeric fields. Apply to all four:
- `strength: "30mg"` → `strengthValue: 30, strengthUnit: "mg"`
- `strength: "1000 IU"` → `strengthValue: 1000, strengthUnit: "IU"`
- `strength: "500mg"` → `strengthValue: 500, strengthUnit: "mg"`
- `strength: "25mg"` → `strengthValue: 25, strengthUnit: "mg"`

The `snapshotStrength:` lines (e.g. `snapshotStrength: metoprolol.strength`) become `snapshotStrength: metoprolol.strengthDescription` (same for `vitaminD`, `acetaminophen`).

- [ ] **Step 7: Update all test constructors**

Across the test files, every `Medication(name: ..., strength: "<n><unit>")` becomes `Medication(name: ..., strengthValue: <n>, strengthUnit: "<unit>")`, and every `MedicationService.addMedication(... strength: "<n><unit>" ...)` becomes `... strengthValue: <n>, strengthUnit: "<unit>" ...`. Apply the transformation to these exact occurrences:

- `MedicationServiceTests.swift` — lines 24/43/58/79/93/114/131/156/171/185/200/214/225/238 (`strength: "30mg"`/`"500mg"` → `strengthValue: 30/500, strengthUnit: "mg"`); the `swap(...)` calls at 137/161/175 (`newStrength: "5mg"` → `newStrengthValue: 5, newStrengthUnit: "mg"`).
- `MedicationModelTests.swift` — line 12 (`"30mg"`), and line 20 assertion `#expect(only.strength == "30mg")` → `#expect(only.strengthDescription == "30 mg")`.
- `DoseLogServiceTests.swift` — line 26 (`strength: "10mg"` → `strengthValue: 10, strengthUnit: "mg"`).
- `DoseLogServicePRNTests.swift` — lines 21/35 (`"500mg"`).
- `DoseLogTests.swift` — lines 13/38 (`"30mg"`, `"500mg"`).
- `MedicationChangeEventTests.swift` — lines 13/33/34 (`"30mg"`, `"50mg"`, `"30mg"`).
- `MedicationLineageTests.swift` — lines 19/20/21/44/51/52 (`"25mg"`, `"30mg"`, `"5mg"`, `"1000 IU"`, `"1"` → `strengthValue: 1, strengthUnit: ""`, `"1"`).
- `BatchRelationshipTests.swift` — line 13 (`"30mg"`).
- `RegimeQueryTests.swift` — lines 22/28/42/45 (`"10mg"`, `"10mg"`, `"500mg"`, `"1mg"`).
- `DayQueryTests.swift` — lines 48/52/68/71/91 (`"10mg"`, `"10mg"`, `"1mg"`, `"1mg"`, `"500mg"`).

> Note: the existing `testChangeDoseMutatesQuantityAndWritesEvent` asserts `oldValue == "30mg — Blue 1"` / `newValue == "30mg — Blue 0.5"`. Because `strengthDescription` renders `"30 mg"` (with a space), update those two assertions to `"30 mg — Blue 1"` and `"30 mg — Blue 0.5"`, and update that test's `changeDose` call to `newStrengthValue: 30, newStrengthUnit: "mg"`.

- [ ] **Step 8: Build and run the full test suite**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet
```
Expected: BUILD SUCCEEDED, all existing tests PASS. If any `strength` reference remains, the compiler will name the file/line — fix and rebuild.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(meds): structured strength (value+unit) and dailyDoseTarget field"
```

---

## Task 2: DoseAllocation helper

**Files:**
- Create: `PillDaddy/Services/DoseAllocation.swift`
- Create test: `PillDaddyTests/DoseAllocationTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PillDaddyTests/DoseAllocationTests.swift`:

```swift
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DoseAllocationTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    private func medWithBatches(target: Double, quantities: [Double]) -> Medication {
        let med = Medication(name: "Test", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: target)
        context.insert(med)
        for q in quantities {
            let batch = Batch(name: "B")
            context.insert(batch)
            context.insert(BatchItem(quantity: q, medication: med, batch: batch))
        }
        return med
    }

    @Test func allocatedSumsAllBatchQuantities() {
        let med = medWithBatches(target: 2, quantities: [1.0, 0.5])
        #expect(DoseAllocation.allocated(med) == 1.5)
    }

    @Test func remainingIsTargetMinusAllocatedClampedAtZero() {
        let under = medWithBatches(target: 2, quantities: [0.5])
        #expect(DoseAllocation.remaining(under) == 1.5)
        let over = medWithBatches(target: 1, quantities: [1.0, 0.5])
        #expect(DoseAllocation.remaining(over) == 0)
    }

    @Test func statusReflectsUnderFullOver() {
        #expect(DoseAllocation.status(medWithBatches(target: 2, quantities: [0.5])) == .under)
        #expect(DoseAllocation.status(medWithBatches(target: 2, quantities: [1.0, 1.0])) == .full)
        #expect(DoseAllocation.status(medWithBatches(target: 1, quantities: [1.0, 0.5])) == .over)
    }

    @Test func derivedStrengthMultipliesValueByCount() {
        let med = medWithBatches(target: 2, quantities: [1.0, 1.0])  // 30mg x 2
        #expect(DoseAllocation.allocatedStrength(med) == 60)
        #expect(DoseAllocation.targetStrength(med) == 60)
    }

    @Test func needsAttentionTrueWhenUnderAndScheduled() {
        #expect(DoseAllocation.needsAttention(medWithBatches(target: 2, quantities: [0.5])))
    }

    @Test func needsAttentionFalseWhenFull() {
        #expect(!DoseAllocation.needsAttention(medWithBatches(target: 2, quantities: [1.0, 1.0])))
    }

    @Test func needsAttentionFalseForPRN() {
        let med = Medication(name: "PRN", strengthValue: 500, strengthUnit: "mg",
                             dailyDoseTarget: 1, isPRN: true)
        context.insert(med)
        #expect(!DoseAllocation.needsAttention(med))
    }

    @Test func needsAttentionFalseForDiscontinued() {
        let med = medWithBatches(target: 2, quantities: [0.5])
        med.isActive = false
        #expect(!DoseAllocation.needsAttention(med))
    }
}
```

- [ ] **Step 2: Regenerate project and verify the tests fail**

```bash
xcodegen generate
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:PillDaddyTests/DoseAllocationTests -quiet
```
Expected: FAIL — `cannot find 'DoseAllocation' in scope`.

- [ ] **Step 3: Implement the helper**

Create `PillDaddy/Services/DoseAllocation.swift`:

```swift
import Foundation

/// Single source of truth for daily-dose allocation: how many units/day are
/// allocated to batches vs. the prescribed target, plus derived strength totals.
/// All counts are in units (tablets); strength totals are derived (value x count)
/// and only ever within one medication, so no cross-unit conversion is needed.
enum DoseAllocation {
    enum Status { case under, full, over }

    /// Sum of quantity across all the med's batch items, regardless of recurrence.
    static func allocated(_ med: Medication) -> Double {
        (med.batchItems ?? []).reduce(0) { $0 + $1.quantity }
    }

    /// Units/day still unallocated, clamped at zero.
    static func remaining(_ med: Medication) -> Double {
        max(0, med.dailyDoseTarget - allocated(med))
    }

    static func status(_ med: Medication) -> Status {
        let a = allocated(med)
        if a < med.dailyDoseTarget { return .under }
        if a > med.dailyDoseTarget { return .over }
        return .full
    }

    /// Derived total strength currently allocated, e.g. 30mg x 2 = 60.
    static func allocatedStrength(_ med: Medication) -> Double {
        med.strengthValue * allocated(med)
    }

    /// Derived total strength at the prescribed target.
    static func targetStrength(_ med: Medication) -> Double {
        med.strengthValue * med.dailyDoseTarget
    }

    /// A scheduled, active med whose allocation does not match its target.
    static func needsAttention(_ med: Medication) -> Bool {
        guard med.isActive, !med.isPRN else { return false }
        return status(med) != .full
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:PillDaddyTests/DoseAllocationTests -quiet
```
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(meds): DoseAllocation helper for daily-dose math"
```

---

## Task 3: Service-layer cap validation

Add the over-allocation guard to the mutation layer: a new error, an `addToBatch` method, a `newDailyDoseTarget` parameter + guard on `changeDose`, and a placement-sum guard on `addMedication` (making it throwing).

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift`
- Modify test: `PillDaddyTests/MedicationServiceTests.swift`
- Modify (compile fix): `PillDaddy/Views/Meds/MedicationEditor.swift`, `PillDaddyTests/DoseLogServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `PillDaddyTests/MedicationServiceTests.swift` (inside the struct):

```swift
    @Test
    func testAddToBatchWithinRemainingInserts() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 2,
            placements: [], reason: "", in: context)

        try MedicationService.addToBatch(med, blue, quantity: 1.5, in: context)

        #expect(med.batchItems?.count == 1)
        #expect(DoseAllocation.allocated(med) == 1.5)
    }

    @Test
    func testAddToBatchExceedingRemainingThrows() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [], reason: "", in: context)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addToBatch(med, blue, quantity: 1.5, in: context)
        }
        #expect(med.batchItems?.isEmpty == true)
    }

    @Test
    func testChangeDoseRejectsResultingOverAllocation() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let item = try #require(med.batchItems?.first)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.changeDose(
                med, newStrengthValue: 30, newStrengthUnit: "mg",
                newDailyDoseTarget: 1,
                newQuantities: [(item: item, quantity: 2.0)],
                reason: "bump", in: context)
        }
    }

    @Test
    func testChangeDoseWithRaisedTargetPermitsNewAllocation() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let item = try #require(med.batchItems?.first)

        try MedicationService.changeDose(
            med, newStrengthValue: 30, newStrengthUnit: "mg",
            newDailyDoseTarget: 2,
            newQuantities: [(item: item, quantity: 2.0)],
            reason: "increase", in: context)

        #expect(item.quantity == 2.0)
        #expect(med.dailyDoseTarget == 2)
    }

    @Test
    func testAddMedicationRejectsPlacementsOverTarget() throws {
        let blue = Batch(name: "Blue")
        let green = Batch(name: "Green")
        context.insert(blue); context.insert(green)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addMedication(
                name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
                isPRN: false, notes: "", dailyDoseTarget: 1,
                placements: [(batch: blue, quantity: 1.0), (batch: green, quantity: 1.0)],
                reason: "", in: context)
        }
    }
```

- [ ] **Step 2: Verify the new tests fail to compile/pass**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:PillDaddyTests/MedicationServiceTests -quiet
```
Expected: FAIL — `addToBatch` / `DoseAllocationError` / `newDailyDoseTarget` not found, and `addMedication` not throwing.

- [ ] **Step 3: Implement the service changes**

In `PillDaddy/Services/MedicationService.swift`:

Add the error next to `MedicationServiceError`:

```swift
enum DoseAllocationError: Error, Equatable {
    case exceedsDailyTarget
}
```

Make `addMedication` throwing and guard the placement sum (add `throws`, and the guard before inserting placements):

```swift
    @discardableResult
    static func addMedication(
        name: String, strengthValue: Double, strengthUnit: String, form: String,
        isPRN: Bool, notes: String, dailyDoseTarget: Double = 1,
        placements: [(batch: Batch, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws -> Medication {
        if !isPRN {
            let total = placements.reduce(0) { $0 + $1.quantity }
            if total > dailyDoseTarget { throw DoseAllocationError.exceedsDailyTarget }
        }
        let med = Medication(name: name, strengthValue: strengthValue, strengthUnit: strengthUnit,
                             dailyDoseTarget: dailyDoseTarget, form: form,
                             generalNotes: notes, isPRN: isPRN)
        context.insert(med)
        if !isPRN {
            for placement in placements {
                context.insert(BatchItem(quantity: placement.quantity,
                                         medication: med, batch: placement.batch))
            }
        }
        context.insert(MedicationChangeEvent(type: .added, reasoning: reason, medication: med))
        try? context.save()
        return med
    }
```

Add `addToBatch`:

```swift
    /// Adds a medication to a batch with a chosen quantity, rejecting anything
    /// that would push total allocation past the daily-dose target. Initial
    /// placement needs no reason.
    static func addToBatch(
        _ med: Medication, _ batch: Batch, quantity: Double,
        in context: ModelContext
    ) throws {
        if quantity > DoseAllocation.remaining(med) {
            throw DoseAllocationError.exceedsDailyTarget
        }
        context.insert(BatchItem(quantity: quantity, medication: med, batch: batch))
        try context.save()
    }
```

Update `changeDose` to take `newDailyDoseTarget` and guard the resulting allocation. Apply quantities to a temp dictionary to compute the prospective total before mutating, or mutate then validate and roll back on failure. Use the compute-first approach:

```swift
    static func changeDose(
        _ med: Medication,
        newStrengthValue: Double, newStrengthUnit: String,
        newDailyDoseTarget: Double,
        newQuantities: [(item: BatchItem, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)

        // Prospective total = sum of quantities, using the new value where provided.
        let overrides = Dictionary(uniqueKeysWithValues:
            newQuantities.map { ($0.item.persistentModelID, $0.quantity) })
        let prospective = (med.batchItems ?? []).reduce(0.0) { sum, item in
            sum + (overrides[item.persistentModelID] ?? item.quantity)
        }
        if prospective > newDailyDoseTarget { throw DoseAllocationError.exceedsDailyTarget }

        let oldSummary = doseSummary(med)
        med.strengthValue = newStrengthValue
        med.strengthUnit = newStrengthUnit
        med.dailyDoseTarget = newDailyDoseTarget
        for change in newQuantities { change.item.quantity = change.quantity }
        let newSummary = doseSummary(med)
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: reason,
            oldValue: oldSummary, newValue: newSummary, medication: med))
        try context.save()
    }
```

- [ ] **Step 4: Fix the call sites broken by `addMedication throws` and the new `changeDose` parameter**

These edits keep the build green; the UI specifics are finalized in later tasks.

**`PillDaddy/Views/Meds/MedicationEditor.swift`** `save()` `.add` case — wrap the call and pass `dailyDoseTarget: 1` for now (Task 5 wires the real field):

```swift
        case .add:
            let placements: [(batch: Batch, quantity: Double)] = isPRN ? [] :
                batches
                    .filter { selected.contains($0.persistentModelID) }
                    .map { ($0, quantities[$0.persistentModelID] ?? 1.0) }
            try? MedicationService.addMedication(
                name: name, strengthValue: strengthValue, strengthUnit: strengthUnit, form: form,
                isPRN: isPRN, notes: notes, dailyDoseTarget: 1, placements: placements,
                reason: reason, in: context)
```

**`PillDaddy/Views/Meds/ChangeDoseSheet.swift`** `save()` — `changeDose` now requires `newDailyDoseTarget`; pass the med's current target so the build compiles (Task 7 replaces this with an editable field):

```swift
        try? MedicationService.changeDose(
            medication, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit,
            newDailyDoseTarget: medication.dailyDoseTarget, newQuantities: changes,
            reason: reason, in: context)
```

**`PillDaddyTests/DoseLogServiceTests.swift`** — prefix every `MedicationService.addMedication(` call with `try` (the test functions are already `throws`).

**`PillDaddyTests/MedicationServiceTests.swift`** — for every existing `MedicationService.addMedication(` / `swap(` setup call, prefix `try` (most are already `try` for `swap`/`changeDose`; `addMedication` now needs it too). Set `dailyDoseTarget: 2` on the two setups whose placements sum to 1.5: `testAddScheduledMedicationCreatesBatchItemsAndAddedEvent` (~line 24) and the swap setup in `testSwapInheritsScheduleDiscontinuesOldAndLinksSuccessor` (~lines 130–134). For the two existing `changeDose` calls, add `newDailyDoseTarget: 1`:
- `testChangeDoseMutatesQuantityAndWritesEvent` — `newDailyDoseTarget: 1` (setup target defaults to 1; new total 0.5 ≤ 1).
- `testChangeDoseWithEmptyReasonThrows` — `newDailyDoseTarget: 1` (throws on reason before the target check).

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet
```
Expected: BUILD SUCCEEDED, all tests PASS (existing + 5 new).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(meds): enforce daily-dose cap in MedicationService (addToBatch, changeDose, addMedication)"
```

---

## Task 4: DoseQuantityField reusable input

A row that shows a stepper by default with an `Exact` disclosure that swaps to a typed decimal field. One bound `Double` across both modes; an optional `max` drives an inline over-cap warning.

**Files:**
- Create: `PillDaddy/Views/Meds/DoseQuantityField.swift`
- Create test: `PillDaddyTests/DoseQuantityFieldTests.swift`

- [ ] **Step 1: Write the failing test for the parse helper**

Create `PillDaddyTests/DoseQuantityFieldTests.swift`:

```swift
import Testing
@testable import PillDaddy

struct DoseQuantityFieldTests {
    @Test func parsesPlainDecimal() {
        #expect(DoseQuantityParsing.value(from: "1.25") == 1.25)
    }

    @Test func parsesIntegerString() {
        #expect(DoseQuantityParsing.value(from: "2") == 2)
    }

    @Test func rejectsNonNumeric() {
        #expect(DoseQuantityParsing.value(from: "abc") == nil)
    }

    @Test func rejectsNegative() {
        #expect(DoseQuantityParsing.value(from: "-1") == nil)
    }

    @Test func rejectsZero() {
        #expect(DoseQuantityParsing.value(from: "0") == nil)
    }
}
```

- [ ] **Step 2: Regenerate and verify failure**

```bash
xcodegen generate
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:PillDaddyTests/DoseQuantityFieldTests -quiet
```
Expected: FAIL — `cannot find 'DoseQuantityParsing' in scope`.

- [ ] **Step 3: Implement the component + parse helper**

Create `PillDaddy/Views/Meds/DoseQuantityField.swift`:

```swift
import SwiftUI

/// Pure parsing for manual dose entry: a positive decimal or nil.
enum DoseQuantityParsing {
    static func value(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let v = Double(trimmed), v > 0 else { return nil }
        return v
    }
}

/// A dose-quantity input. Stepper by default (0.5 nudges) with an `Exact`
/// disclosure that swaps to a typed decimal field for arbitrary fractions.
/// `max`, when set, is a soft cap: typing above it shows a warning (the parent
/// owns whether Save is blocked).
struct DoseQuantityField: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0.5...20
    var step: Double = 0.5
    var max: Double? = nil

    @State private var manual = false
    @State private var text = ""

    private var exceedsCap: Bool {
        if let max { return value > max + 0.0001 }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if manual {
                    Text(title)
                    TextField("Amount", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: text) { _, new in
                            if let v = DoseQuantityParsing.value(from: new) { value = v }
                        }
                    Button { manual = false } label: {
                        Label("Steps", systemImage: "chevron.left")
                            .labelStyle(.titleOnly).font(.caption)
                    }
                } else {
                    Stepper(value: $value, in: range, step: step) {
                        Text("\(title): \(DoseFormat.qty(value))")
                    }
                    Button { text = DoseFormat.qty(value); manual = true } label: {
                        Label("Exact", systemImage: "chevron.right")
                            .labelStyle(.titleOnly).font(.caption)
                    }
                }
            }
            if exceedsCap, let max {
                Text("Exceeds daily dose (\(DoseFormat.qty(max)) available)")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }
}
```

- [ ] **Step 4: Run the parse tests**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:PillDaddyTests/DoseQuantityFieldTests -quiet
```
Expected: PASS (5 tests). (The view itself is verified by compilation; behavior is exercised in Tasks 5–7.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(meds): DoseQuantityField input with stepper/manual disclosure"
```

---

## Task 5: MedicationEditor — daily-dose target + capped placements

**Files:**
- Modify: `PillDaddy/Views/Meds/MedicationEditor.swift`

- [ ] **Step 1: Add target state and field**

Add to the `@State` block:

```swift
    @State private var dailyDoseTarget = 1.0
```

In the "Details" section, after the strength fields and only for non-PRN add mode, insert a target field. Change the `Toggle("As needed (PRN)", isOn: $isPRN)` area so the target appears when `isAdd && !isPRN`:

```swift
                if isAdd && !isPRN {
                    DoseQuantityField(title: "Doses per day", value: $dailyDoseTarget)
                }
```

- [ ] **Step 2: Cap the inline batch-assignment steppers and show a running caption**

Add a computed property for already-allocated quantity in the editor's draft selection:

```swift
    private var assignedTotal: Double {
        selected.reduce(0.0) { $0 + (quantities[$1] ?? 1.0) }
    }
```

In `batchAssignRow`, replace the inline `Stepper(...)` with a `DoseQuantityField` bounded so the running sum can't exceed the target. Compute the per-row max as `target - (assignedTotal - thisRowQuantity)`:

```swift
            if isOn {
                let current = quantities[id] ?? 1.0
                let rowMax = max(0.5, dailyDoseTarget - (assignedTotal - current))
                DoseQuantityField(
                    title: "Quantity",
                    value: Binding(get: { quantities[id] ?? 1.0 },
                                   set: { quantities[id] = $0 }),
                    range: 0.5...20, step: 0.5, max: rowMax)
            }
```

Add a caption under the "Add to batches" section header showing both units:

```swift
                    Text("\(DoseFormat.qty(assignedTotal)) of \(DoseFormat.qty(dailyDoseTarget))/day allocated (\(DoseFormat.qty(assignedTotal * strengthValue)) of \(DoseFormat.qty(dailyDoseTarget * strengthValue)) \(strengthUnit))")
                        .font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 3: Block Save when target invalid or over-allocated; pass the target**

Change the Save button's `.disabled` to also require a positive target for non-PRN and no over-allocation:

```swift
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || saveBlocked)
                }
```

Add:

```swift
    private var saveBlocked: Bool {
        guard isAdd, !isPRN else { return false }
        return dailyDoseTarget <= 0 || assignedTotal > dailyDoseTarget
    }
```

In `save()` `.add` case, pass `dailyDoseTarget: dailyDoseTarget` instead of the hardcoded `1`.

- [ ] **Step 4: Build and smoke-test**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet
```
Expected: BUILD SUCCEEDED, all tests PASS.

Manual check (optional, in Simulator): add a non-PRN med, set "Doses per day" to 2, assign two batches — the second batch's quantity caps so the total can't exceed 2, and the caption reads e.g. "2 of 2/day allocated (60 of 60 mg)".

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(meds): daily-dose target + capped batch assignment in add flow"
```

---

## Task 6: BatchEditor — prompted, capped add + audited edit entry

**Files:**
- Modify: `PillDaddy/Views/Meds/BatchEditor.swift`

- [ ] **Step 1: Replace the immediate insert with a quantity prompt**

Add state for the med being added:

```swift
    @State private var addingMed: Medication?
    @State private var addQuantity = 1.0
```

Replace the `Menu("Add medication")` block's button action so it opens a prompt instead of inserting directly:

```swift
                        Menu("Add medication") {
                            ForEach(addableMeds(to: batch)) { med in
                                Button(med.name) {
                                    addingMed = med
                                    addQuantity = min(1.0, max(0.5, DoseAllocation.remaining(med)))
                                }
                                .disabled(DoseAllocation.remaining(med) <= 0)
                            }
                        }
```

> Note: `.disabled` inside a `Menu`'s `Button` greys out fully-allocated meds. If a clearer "Fully allocated" affordance is wanted, render those as a plain disabled `Label` instead; greying is sufficient for v1.

- [ ] **Step 2: Add the quantity prompt sheet**

Add to the view's `.toolbar`/modifiers (e.g. after `.onAppear(perform: load)`):

```swift
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
                                if let batch { try? MedicationService.addToBatch(med, batch, quantity: addQuantity, in: context) }
                                addingMed = nil
                            }
                            .disabled(addQuantity > DoseAllocation.remaining(med))
                        }
                    }
                }
            }
```

- [ ] **Step 3: Make existing item rows open the audited ChangeDoseSheet**

Add state:

```swift
    @State private var editingMed: Medication?
```

Wrap the existing-item row content in a `Button` that sets `editingMed`, and present `ChangeDoseSheet`. Replace the `ForEach(activeItems) { item in HStack { ... } }` body so each row is tappable:

```swift
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
```

And add the sheet:

```swift
            .sheet(item: $editingMed) { ChangeDoseSheet(medication: $0) }
```

- [ ] **Step 4: Build and test**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet
```
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(meds): prompt+cap when adding to a batch; tap an item to change its dose"
```

---

## Task 7: ChangeDoseSheet — target field + per-batch cap validation

**Files:**
- Modify: `PillDaddy/Views/Meds/ChangeDoseSheet.swift`

- [ ] **Step 1: Add target state and field**

Add state:

```swift
    @State private var target = 1.0
```

Set it in `.onAppear` alongside strength:

```swift
            .onAppear {
                strengthValue = medication.strengthValue
                strengthUnit = medication.strengthUnit
                target = medication.dailyDoseTarget
            }
```

Add the target field at the top of the "New dose" section (above the per-batch steppers):

```swift
                    DoseQuantityField(title: "Doses per day", value: $target)
```

- [ ] **Step 2: Convert the per-batch steppers to DoseQuantityField and add a live total caption**

Add a computed prospective total:

```swift
    private var prospectiveTotal: Double {
        (medication.batchItems ?? []).reduce(0.0) { sum, item in
            sum + (quantities[item.persistentModelID] ?? item.quantity)
        }
    }
    private var overAllocated: Bool { prospectiveTotal > target + 0.0001 }
```

Replace the per-item `Stepper(...)` in the `ForEach` with a `DoseQuantityField` (no per-row cap here — the sheet validates the total, since you may be raising the target and re-allocating in one pass):

```swift
                    ForEach(medication.batchItems ?? []) { item in
                        let id = item.persistentModelID
                        DoseQuantityField(
                            title: item.batch?.name ?? "—",
                            value: Binding(get: { quantities[id] ?? item.quantity },
                                           set: { quantities[id] = $0 }))
                    }
                    Text("\(DoseFormat.qty(prospectiveTotal)) of \(DoseFormat.qty(target))/day · \(DoseFormat.qty(prospectiveTotal * strengthValue)) of \(DoseFormat.qty(target * strengthValue)) \(strengthUnit)")
                        .font(.caption)
                        .foregroundStyle(overAllocated ? .red : .secondary)
```

- [ ] **Step 3: Block Save while over-allocated and pass the target**

Change the Save button:

```swift
                    Button("Save") { save() }.disabled(!reasonValid || overAllocated)
```

Update `save()` to pass the new strength + target:

```swift
    private func save() {
        let changes = (medication.batchItems ?? []).compactMap {
            item -> (item: BatchItem, quantity: Double)? in
            guard let q = quantities[item.persistentModelID] else { return nil }
            return (item, q)
        }
        try? MedicationService.changeDose(
            medication, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit,
            newDailyDoseTarget: target, newQuantities: changes,
            reason: reason, in: context)
        dismiss()
    }
```

- [ ] **Step 4: Build and test**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet
```
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(meds): daily-dose target + over-allocation guard in ChangeDoseSheet"
```

---

## Task 8: Caution badge + surfacing

**Files:**
- Create: `PillDaddy/Views/Meds/DoseAllocationBadge.swift`
- Modify: `PillDaddy/Views/Meds/AllMedsView.swift`, `RegimeView.swift`, `MedicationDetailView.swift`

- [ ] **Step 1: Create the badge view**

Create `PillDaddy/Views/Meds/DoseAllocationBadge.swift`:

```swift
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
```

- [ ] **Step 2: Regenerate the project (new file)**

```bash
xcodegen generate
```

- [ ] **Step 3: Surface in AllMedsView**

In `PillDaddy/Views/Meds/AllMedsView.swift` `row(_:)`, add the badge into the trailing area. Replace the `if !med.isActive { ... } else if med.isPRN { ... }` trailing block so the badge shows for active scheduled meds:

```swift
            Spacer()
            if !med.isActive {
                tag("Discontinued")
            } else if med.isPRN {
                tag("PRN")
            } else {
                DoseAllocationBadge(medication: med)
            }
```

- [ ] **Step 4: Surface in RegimeView**

In `PillDaddy/Views/Meds/RegimeView.swift` `row(_:)`, add the badge under the strength caption:

```swift
            VStack(alignment: .leading) {
                Text(item.medication?.name ?? "—")
                Text(item.medication?.strengthDescription ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                if let med = item.medication { DoseAllocationBadge(medication: med) }
            }
```

- [ ] **Step 5: Surface in MedicationDetailView header (with caption)**

In `PillDaddy/Views/Meds/MedicationDetailView.swift`, add to the first `Section` (after the strength/form lines):

```swift
                DoseAllocationBadge(medication: medication, showCaption: true)
```

- [ ] **Step 6: Build and test**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet
```
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(meds): caution badge for under/over-allocated meds across regime + lists"
```

---

## Task 9: DoseLog numeric strength capture (forward-compat for reporting)

Freeze the numeric strength per dose so future "mg received" reporting has accurate history. Data capture only — no display.

**Files:**
- Modify: `PillDaddy/Models/DoseLog.swift`
- Modify: `PillDaddy/Services/DoseLogService.swift`
- Create test: `PillDaddyTests/DoseLogStrengthSnapshotTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/DoseLogStrengthSnapshotTests.swift`:

```swift
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DoseLogStrengthSnapshotTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    @Test func prnLogFreezesNumericStrength() throws {
        let med = Medication(name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg",
                             dailyDoseTarget: 1, isPRN: true)
        context.insert(med)

        let log = DoseLogService.logPRN(med, takenAt: .now, quantity: 2,
                                        note: "", in: context)

        #expect(log.snapshotStrengthValue == 500)
        #expect(log.snapshotStrengthUnit == "mg")

        // Editing the med later must not change the frozen snapshot.
        med.strengthValue = 250
        #expect(log.snapshotStrengthValue == 500)
        // Medicine received = frozen strength x quantity.
        #expect(log.snapshotStrengthValue * log.quantity == 1000)
    }
}
```

- [ ] **Step 2: Regenerate and verify failure**

```bash
xcodegen generate
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:PillDaddyTests/DoseLogStrengthSnapshotTests -quiet
```
Expected: FAIL — `value of type 'DoseLog' has no member 'snapshotStrengthValue'`.

- [ ] **Step 3: Add the fields to DoseLog**

In `PillDaddy/Models/DoseLog.swift`, add two stored properties after `snapshotStrength`:

```swift
    var snapshotStrengthValue: Double = 0
    var snapshotStrengthUnit: String = "mg"
```

And add them to the initializer's parameter list (with defaults) and assignments:

```swift
    init(scheduledDate: Date = .now, takenAt: Date? = nil, status: DoseStatus = .taken,
         quantity: Double = 1.0, notes: String = "",
         snapshotMedName: String = "", snapshotStrength: String = "",
         snapshotStrengthValue: Double = 0, snapshotStrengthUnit: String = "mg",
         snapshotBatchColorHex: String = "",
         medication: Medication? = nil, batchItem: BatchItem? = nil) {
        // ...existing assignments...
        self.snapshotStrengthValue = snapshotStrengthValue
        self.snapshotStrengthUnit = snapshotStrengthUnit
        // ...
    }
```

- [ ] **Step 4: Populate them in DoseLogService**

In `logPRN`, add to the `DoseLog(...)` call:

```swift
            snapshotStrengthValue: med.strengthValue, snapshotStrengthUnit: med.strengthUnit,
```

In `upsert`, after `log.snapshotStrength = ...`:

```swift
        log.snapshotStrengthValue = item.medication?.strengthValue ?? 0
        log.snapshotStrengthUnit = item.medication?.strengthUnit ?? "mg"
```

- [ ] **Step 5: Run the test, then the full suite**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test -only-testing:PillDaddyTests/DoseLogStrengthSnapshotTests -quiet
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet
```
Expected: PASS, then full suite PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(logs): freeze numeric strength per dose for future mg-received reporting"
```

---

## Final verification

- [ ] **Step 1: Regenerate, clean build, full test run**

```bash
xcodegen generate
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' clean build
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -quiet
```
Expected: BUILD SUCCEEDED; all suites pass (`DoseAllocationTests`, `DoseQuantityFieldTests`, `MedicationServiceTests`, `DoseLogStrengthSnapshotTests`, and all pre-existing suites).

- [ ] **Step 2: Confirm no stray `.strength` references remain**

```bash
grep -rn "\.strength\b" PillDaddy PillDaddyTests --include="*.swift" | grep -v "strengthValue\|strengthUnit\|strengthDescription\|snapshotStrength"
```
Expected: no output.

- [ ] **Step 3: Manual dogfood pass (Simulator)**

Add a scheduled med with "Doses per day" = 2 and strength 30 mg; assign 1 tablet to a morning batch → its row shows the amber "Under daily dose" badge with "1 of 2 tablet/day · 30 of 60 mg". Add it to an evening batch at 1 → badge clears. Open the med → "Change dose…" → try to raise a batch to push the total past 2 → Save disables until you raise "Doses per day".

---

## Notes for the implementer

- **No data migration.** Existing seed/manual meds reset to `strengthValue: 0`, `strengthUnit: "mg"`, `dailyDoseTarget: 1` on the model change; the single real user re-enters ~5 meds by hand. Don't write migration code.
- **Counts vs. strength.** All validation is in unit counts; mg is derived (`strengthValue × count`) for display only and never converted across units.
- **Deferred (NOT in this plan):** displaying total medicine received on history/log surfaces — Session 5 (Reporting). This plan only captures the data.
