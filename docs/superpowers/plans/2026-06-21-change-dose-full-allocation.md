# Change Dose Full Routine Allocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Change Dose sheet allocate a medication's dose across *all* routines — adding a routine by toggling it on, removing one by toggling it off, and changing quantities — reusing the allocation UI from the Add Medication editor.

**Architecture:** Extract the per-routine toggle/quantity allocation UI from `MedicationEditor` into a shared `RoutineAllocationSection` view. Evolve `MedicationService.changeDose` to accept a full desired set of `(routine, quantity)` placements and reconcile memberships (update / insert / delete) in one atomic save. Rewrite `ChangeDoseSheet` to drive that with the shared view, pre-populated from current memberships.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`). iOS Simulator destination: **iPhone 17**. Project uses **XcodeGen** (`project.yml`); run `xcodegen generate` after adding files.

---

## Reference: existing code

`MedicationService.changeDose` current signature ([MedicationService.swift:60](../../../RoutineDosePlanner/Services/MedicationService.swift)):

```swift
static func changeDose(
    _ med: Medication,
    newStrengthValue: Double, newStrengthUnit: String,
    newDailyDoseTarget: Double,
    newQuantities: [(item: RoutineItem, quantity: Double)],
    reason: String,
    in context: ModelContext
) throws
```

`RoutineItem` initializer ([RoutineItem.swift:15](../../../RoutineDosePlanner/Models/RoutineItem.swift)):

```swift
init(quantity: Double = 1.0, instructionsOverride: String = "", medication: Medication?, routine: Routine?)
```

`MedicationEditor`'s allocation row + section to extract ([MedicationEditor.swift:62-137](../../../RoutineDosePlanner/Views/Meds/MedicationEditor.swift)).

Build/test command used throughout:

```bash
xcodebuild test -scheme RoutineDosePlanner \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RoutineDosePlannerTests/MedicationServiceTests
```

---

## Task 1: `changeDose` reconciles a full placement set

**Files:**
- Modify: `RoutineDosePlanner/Services/MedicationService.swift:60-92`
- Modify (callers, to keep build green): `RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift:82-97`
- Test: `RoutineDosePlannerTests/MedicationServiceTests.swift` (update 4 existing call sites at lines 64, 84, 292, 310; add 2 new tests)

- [ ] **Step 1: Write the failing tests (add + remove a routine via Change Dose)**

Add these two tests to `MedicationServiceTests.swift` (anywhere among the `changeDose` tests):

```swift
@Test
func testChangeDoseAddsNewRoutineMembership() throws {
    let blue = Routine(name: "Blue")
    let green = Routine(name: "Green")
    context.insert(blue); context.insert(green)
    let med = try MedicationService.addMedication(
        name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
        isPRN: false, notes: "", dailyDoseTarget: 2,
        placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)

    try MedicationService.changeDose(
        med, newStrengthValue: 30, newStrengthUnit: "mg", newDailyDoseTarget: 2,
        placements: [(routine: blue, quantity: 1.0), (routine: green, quantity: 1.0)],
        reason: "Split across morning and evening", in: context)

    let byRoutine = Dictionary(uniqueKeysWithValues:
        (med.routineItems ?? []).map { ($0.routine?.name ?? "?", $0.quantity) })
    #expect(byRoutine == ["Blue": 1.0, "Green": 1.0])
    let doseEvents = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.doseChanged.rawValue }
    #expect(doseEvents.count == 1)
}

@Test
func testChangeDoseRemovesOmittedRoutineMembership() throws {
    let blue = Routine(name: "Blue")
    let green = Routine(name: "Green")
    context.insert(blue); context.insert(green)
    let med = try MedicationService.addMedication(
        name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
        isPRN: false, notes: "", dailyDoseTarget: 2,
        placements: [(routine: blue, quantity: 1.0), (routine: green, quantity: 1.0)],
        reason: "", in: context)

    try MedicationService.changeDose(
        med, newStrengthValue: 30, newStrengthUnit: "mg", newDailyDoseTarget: 2,
        placements: [(routine: blue, quantity: 1.0)],
        reason: "Dropped the evening dose", in: context)

    #expect(med.routineItems?.count == 1)
    #expect(med.routineItems?.first?.routine?.name == "Blue")
}
```

Update the **four existing** `changeDose` call sites to the new `placements:` label (routine-based, full desired set):

- Line ~64 (`testChangeDoseMutatesQuantityAndWritesEvent`): replace `newQuantities: [(item: item, quantity: 0.5)]` with `placements: [(routine: blue, quantity: 0.5)]`.
- Line ~84 (`testChangeDoseWithEmptyReasonThrows`): replace `newQuantities: []` with `placements: []`.
- Line ~292 (`testChangeDoseRejectsResultingOverAllocation`): replace `newQuantities: [(item: item, quantity: 2.0)]` with `placements: [(routine: blue, quantity: 2.0)]`.
- Line ~310 (`testChangeDoseWithRaisedTargetPermitsNewAllocation`): replace `newQuantities: [(item: item, quantity: 2.0)]` with `placements: [(routine: blue, quantity: 2.0)]`.

In `testChangeDoseRejectsResultingOverAllocation`, the `let item = try #require(med.routineItems?.first)` line becomes unused — **delete it**. In `testChangeDoseWithRaisedTargetPermitsNewAllocation`, keep that line (its post-condition `#expect(item.quantity == 2.0)` still uses `item`). In `testChangeDoseMutatesQuantityAndWritesEvent`, keep `item` (post-conditions reference it).

- [ ] **Step 2: Run tests to verify they fail (compile failure counts)**

Run the build/test command above.
Expected: FAIL — `changeDose` has no `placements:` parameter / extra argument label `newQuantities:`.

- [ ] **Step 3: Rewrite `changeDose` to reconcile placements**

Replace `MedicationService.changeDose` (lines 60-92) with:

```swift
/// Changes strength and/or the full per-routine allocation on the same medication
/// and records a `doseChanged` event with an old→new summary. `placements` is the
/// complete desired set: existing memberships absent from it are removed, new ones
/// are created, matching ones are updated. Reason required.
static func changeDose(
    _ med: Medication,
    newStrengthValue: Double, newStrengthUnit: String,
    newDailyDoseTarget: Double,
    placements: [(routine: Routine, quantity: Double)],
    reason: String,
    in context: ModelContext
) throws {
    try requireReason(reason)

    let prospective = placements.reduce(0.0) { $0 + $1.quantity }
    if DoseAllocation.isOverTarget(allocated: prospective, target: newDailyDoseTarget) {
        throw DoseAllocationError.exceedsDailyTarget
    }

    let oldSummary = doseSummary(med)
    med.strengthValue = newStrengthValue
    med.strengthUnit = newStrengthUnit
    med.dailyDoseTarget = newDailyDoseTarget

    // Reconcile memberships against the desired placement set.
    let desired = Dictionary(uniqueKeysWithValues:
        placements.map { ($0.routine.persistentModelID, $0.quantity) })
    var existingRoutineIDs = Set<PersistentIdentifier>()
    for item in med.routineItems ?? [] {
        guard let routineID = item.routine?.persistentModelID else { continue }
        if let qty = desired[routineID] {
            item.quantity = qty
            existingRoutineIDs.insert(routineID)
        } else {
            context.delete(item)
        }
    }
    for placement in placements where !existingRoutineIDs.contains(placement.routine.persistentModelID) {
        context.insert(RoutineItem(quantity: placement.quantity,
                                   medication: med, routine: placement.routine))
    }

    let newSummary = doseSummary(med)
    context.insert(MedicationChangeEvent(
        type: .doseChanged, reasoning: reason,
        oldValue: oldSummary, newValue: newSummary, medication: med))
    try context.save()
}
```

- [ ] **Step 4: Update the sole non-test caller to compile (behavior unchanged)**

In `ChangeDoseSheet.save()` ([ChangeDoseSheet.swift:82-97](../../../RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift)), replace the `changes` block and the `changeDose` call with a routine-based, full-set placement built from the medication's *current* memberships (this preserves today's behavior — only existing routines, none deleted):

```swift
private func save() {
    let placements: [(routine: Routine, quantity: Double)] =
        (medication.routineItems ?? []).compactMap { item in
            guard let routine = item.routine else { return nil }
            return (routine, quantities[item.persistentModelID] ?? item.quantity)
        }
    do {
        try MedicationService.changeDose(
            medication, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit,
            newDailyDoseTarget: target, placements: placements,
            reason: reason, in: context)
        dismiss()
    } catch {
        errorMessage = errorMessage(for: error)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the build/test command above.
Expected: PASS — all `MedicationServiceTests` green, including the two new tests.

- [ ] **Step 6: Commit**

```bash
git add RoutineDosePlanner/Services/MedicationService.swift \
        RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift \
        RoutineDosePlannerTests/MedicationServiceTests.swift
git commit -m "Reconcile full placement set in changeDose (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Extract shared `RoutineAllocationSection` view

**Files:**
- Create: `RoutineDosePlanner/Views/Meds/RoutineAllocationSection.swift`
- Modify: `RoutineDosePlanner/Views/Meds/MedicationEditor.swift:62-137`

This task is a pure refactor of the Add Medication UI; it must leave Add Medication behavior identical. There is no unit test for SwiftUI layout — verification is a clean build plus the editor preview.

- [ ] **Step 1: Create the shared view**

Create `RoutineDosePlanner/Views/Meds/RoutineAllocationSection.swift`:

```swift
import SwiftUI
import SwiftData

/// Reusable per-routine allocation editor: a toggle + quantity row for every routine,
/// with a running "X of Y/day allocated" summary that turns red when over target.
/// Used by both the Add Medication editor and the Change Dose sheet.
struct RoutineAllocationSection: View {
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
                Text("Add to routines")
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
                    if on { selected.insert(id); quantities[id] = quantities[id] ?? 1.0 }
                    else { selected.remove(id) }
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
                    value: Binding(get: { quantities[id] ?? 1.0 },
                                   set: { quantities[id] = $0 }),
                    range: 0.5...20, step: 0.5)
            }
        }
    }
}
```

- [ ] **Step 2: Use the shared view in `MedicationEditor`**

In `MedicationEditor.swift`, replace the allocation `Section { … } header: { … }` block (lines 62-83, the `if isAdd && !isPRN { Section { … } … }` that renders routine rows — **keep** the `Section("Why started? (optional)")` block) with:

```swift
if isAdd && !isPRN {
    RoutineAllocationSection(
        routines: routines,
        selected: $selected,
        quantities: $quantities,
        target: dailyDoseTarget,
        strengthValue: strengthValue,
        strengthUnit: strengthUnit)
    Section("Why started? (optional)") {
        TextField("Reason", text: $reason, axis: .vertical)
    }
}
```

Then delete the now-unused `routineAssignRow(_:)` method (lines 110-137) from `MedicationEditor`. Leave `assignedTotal` and `saveBlocked` in `MedicationEditor` — they still gate the Save button.

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: regenerates `RoutineDosePlanner.xcodeproj` including the new file.

- [ ] **Step 4: Build to verify it compiles**

Run:

```bash
xcodebuild build -scheme RoutineDosePlanner \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add RoutineDosePlanner/Views/Meds/RoutineAllocationSection.swift \
        RoutineDosePlanner/Views/Meds/MedicationEditor.swift \
        RoutineDosePlanner.xcodeproj
git commit -m "Extract shared RoutineAllocationSection from editor (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wire Change Dose to full allocation

**Files:**
- Modify: `RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift`

Verification is a clean build plus the `ChangeDoseSheet` preview; the service-level reconciliation is already covered by Task 1's tests.

- [ ] **Step 1: Add routine query + allocation state**

In `ChangeDoseSheet`, add below the existing `@State` declarations (after `@State private var quantities` line):

```swift
@Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
private var allRoutines: [Routine]

@State private var selected: Set<PersistentIdentifier> = []
```

Keep the existing `@State private var quantities: [PersistentIdentifier: Double] = [:]`. Delete the `prospectiveTotal` computed property (the shared view now renders the allocation summary). The `overAllocated` property is redefined in Step 3.

- [ ] **Step 2: Replace the per-item rows with the shared section**

In `body`, replace the `Section("New dose") { … }` block's `ForEach(medication.routineItems ?? [])` rows **and** the trailing summary `Text(...)` with the shared section. The strength + "Doses per day" fields stay. Result:

```swift
Section("New dose") {
    StrengthInputField(value: $strengthValue, unit: $strengthUnit)
    DoseQuantityField(title: "Doses per day", value: $target)
}
if !medication.isPRN {
    RoutineAllocationSection(
        routines: allRoutines,
        selected: $selected,
        quantities: $quantities,
        target: target,
        strengthValue: strengthValue,
        strengthUnit: strengthUnit)
}
Section("Reason (required)") {
    TextField("Why is the dose changing?", text: $reason, axis: .vertical)
}
```

- [ ] **Step 3: Pre-populate from current memberships, and gate Save on over-allocation**

Redefine `overAllocated` so it reads the live allocation state (placing it near `reasonValid`):

```swift
private var overAllocated: Bool {
    let total = selected.reduce(0.0) { $0 + (quantities[$1] ?? 1.0) }
    return DoseAllocation.isOverTarget(allocated: total, target: target)
}
```

Extend the existing `.onAppear` to seed the toggles/quantities from current memberships:

```swift
.onAppear {
    strengthValue = medication.strengthValue
    strengthUnit = medication.strengthUnit
    target = medication.dailyDoseTarget
    for item in medication.routineItems ?? [] {
        guard let routine = item.routine else { continue }
        let id = routine.persistentModelID
        selected.insert(id)
        quantities[id] = item.quantity
    }
}
```

The Save button keeps `.disabled(!reasonValid || overAllocated)` — both properties still exist.

- [ ] **Step 4: Build placements from the selected routines in `save()`**

Replace `save()` (the version from Task 1) so placements come from the selected set rather than existing memberships:

```swift
private func save() {
    let routinesByID = Dictionary(uniqueKeysWithValues:
        allRoutines.map { ($0.persistentModelID, $0) })
    let placements: [(routine: Routine, quantity: Double)] = selected.compactMap { id in
        guard let routine = routinesByID[id] else { return nil }
        return (routine, quantities[id] ?? 1.0)
    }
    do {
        try MedicationService.changeDose(
            medication, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit,
            newDailyDoseTarget: target, placements: placements,
            reason: reason, in: context)
        dismiss()
    } catch {
        errorMessage = errorMessage(for: error)
    }
}
```

- [ ] **Step 5: Build to verify it compiles**

Run:

```bash
xcodebuild build -scheme RoutineDosePlanner \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run the full test suite**

Run:

```bash
xcodebuild test -scheme RoutineDosePlanner \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS — all tests green.

- [ ] **Step 7: Commit**

```bash
git add RoutineDosePlanner/Views/Meds/ChangeDoseSheet.swift
git commit -m "Change Dose allocates across all routines (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Manual verification (after Task 3)

In the iPhone 17 simulator:

1. Open a non-PRN medication that is **fully allocated** across one routine.
2. Tap **Change dose…**. Confirm every routine appears, with the med's current routine(s) toggled on at the right quantity.
3. Lower the existing routine's quantity and toggle on a different routine, set its quantity so the total stays within target. Enter a reason. Save.
4. Confirm the medication now appears in both routines with the new split, and the Why/history shows a single dose-change entry reflecting the new allocation.
5. Re-open Change dose, toggle a routine **off**, save with a reason, and confirm that membership is removed.
6. Confirm a PRN medication's Change dose sheet shows **no** routine allocation section.
