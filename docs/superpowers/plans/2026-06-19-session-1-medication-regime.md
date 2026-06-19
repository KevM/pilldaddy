# Session 1 — Medication & Regime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the working **Meds** tab — create/edit/delete medications, organize them into color-coded time batches with per-batch quantities, view the regime, and perform guided lifecycle changes (change dose, change instructions, swap, discontinue, reactivate) that always capture reasoning.

**Architecture:** A testable logic layer (`MedicationService`, `RegimeQuery`) owns every multi-step mutation as a single atomic save, kept separate from SwiftUI. Views under `PillDaddy/Views/Meds/` call into it and never hand-roll mutations. The Session 0 SwiftData schema is reused unchanged — no model additions.

**Tech Stack:** Swift, SwiftUI, SwiftData (in-memory containers for tests/previews), XcodeGen, XCTest. Deployment target iOS 26.0.

---

## Conventions used throughout this plan

- **Build command** (compile check, no specific device):

  ```bash
  xcodegen generate && xcodebuild -scheme PillDaddy \
    -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```

- **Test command:**

  ```bash
  xcodebuild test -scheme PillDaddy \
    -destination 'platform=iOS Simulator,name=iPhone 17'
  ```

  If `iPhone 17` is unavailable, run `xcrun simctl list devices available | grep iPhone` and substitute any available iOS 26 simulator name.

- Source files are globbed from the `PillDaddy/` directory and tests from `PillDaddyTests/`, so **run `xcodegen generate` after creating any new file** before building.
- New view files compile as soon as they exist (even before they're referenced); they are wired into navigation in the final tasks. This keeps every task building cleanly.

---

## File Structure

**Create (logic + helpers):**
- `PillDaddy/Helpers/DoseFormat.swift` — formats a `Double` quantity for display ("1", "0.5").
- `PillDaddy/Services/MedicationService.swift` — all guided mutations + `MedicationServiceError`.
- `PillDaddy/Services/RegimeQuery.swift` — active-regime grouping helper.
- `PillDaddy/Helpers/PreviewSupport.swift` — DEBUG seeded in-memory container for `#Preview`s.

**Create (views, under `PillDaddy/Views/Meds/`):**
- `MedsView.swift` — toggle host (Regime ⇄ All Meds) + add menu.
- `RegimeView.swift` — batches with active meds + PRN section.
- `AllMedsView.swift` — flat A–Z list + show/hide discontinued + hard delete.
- `MedicationDetailView.swift` — header, memberships, history, actions.
- `MedicationEditor.swift` — add/edit a medication.
- `BatchEditor.swift` — the color manager (batch properties + contents).
- `ChangeDoseSheet.swift`, `ChangeInstructionsSheet.swift`, `SwapSheet.swift`, `LifecycleReasonSheet.swift` — guided change flows.

**Modify:**
- `PillDaddy/Views/MainTabView.swift` — wire the Meds tab to `MedsView`.

**Create (tests):**
- `PillDaddyTests/MedicationServiceTests.swift`
- `PillDaddyTests/RegimeQueryTests.swift`

---

## Task 1: DoseFormat helper + MedicationService.addMedication

**Files:**
- Create: `PillDaddy/Helpers/DoseFormat.swift`
- Create: `PillDaddy/Services/MedicationService.swift`
- Test: `PillDaddyTests/MedicationServiceTests.swift`

- [ ] **Step 1: Create the DoseFormat helper**

`PillDaddy/Helpers/DoseFormat.swift`:

```swift
import Foundation

/// Formats a dose quantity for display: whole numbers drop the decimal ("1"),
/// fractions keep it ("0.5").
enum DoseFormat {
    static func qty(_ q: Double) -> String {
        q == q.rounded() ? String(Int(q)) : String(q)
    }
}
```

- [ ] **Step 2: Write the failing tests for addMedication**

`PillDaddyTests/MedicationServiceTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MedicationServiceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        try ModelTestSupport.makeContainer().mainContext
    }

    func testAddScheduledMedicationCreatesBatchItemsAndAddedEvent() throws {
        let context = try makeContext()
        let blue = Batch(name: "Blue", colorHex: "#3B82F6")
        let green = Batch(name: "Green", colorHex: "#10B981")
        context.insert(blue)
        context.insert(green)

        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0), (batch: green, quantity: 0.5)],
            reason: "Started for hypertension", in: context)

        XCTAssertEqual(med.batchItems?.count, 2)
        XCTAssertEqual((med.batchItems ?? []).map(\.quantity).sorted(), [0.5, 1.0])
        let events = med.changeEvents ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventType, MedChangeType.added.rawValue)
        XCTAssertEqual(events.first?.reasoning, "Started for hypertension")
    }

    func testAddPRNMedicationIgnoresPlacements() throws {
        let context = try makeContext()
        let blue = Batch(name: "Blue")
        context.insert(blue)

        let med = MedicationService.addMedication(
            name: "Acetaminophen", strength: "500mg", form: "tablet",
            isPRN: true, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)

        XCTAssertEqual(med.batchItems ?? [], [])
        XCTAssertTrue(med.isPRN)
        XCTAssertEqual(med.changeEvents?.count, 1)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run the test command (above).
Expected: FAIL — `MedicationService` is not defined.

- [ ] **Step 4: Implement DoseFormat-independent MedicationService with addMedication**

`PillDaddy/Services/MedicationService.swift`:

```swift
import Foundation
import SwiftData

enum MedicationServiceError: Error, Equatable {
    case reasonRequired
}

/// Owns every multi-step medication mutation as a single atomic save, so the
/// "caregiver can't get it wrong" guarantees live in one unit-testable place.
@MainActor
enum MedicationService {

    /// Creates a medication, its batch memberships (skipped for PRN), and an
    /// `added` change event. Reason is optional on add.
    @discardableResult
    static func addMedication(
        name: String, strength: String, form: String,
        isPRN: Bool, notes: String,
        placements: [(batch: Batch, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) -> Medication {
        let med = Medication(name: name, strength: strength, form: form,
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

    // MARK: - Internal helpers

    /// Human-readable summary of a med's current dose, deterministic (sorted by batch name).
    static func doseSummary(_ med: Medication) -> String {
        let parts = (med.batchItems ?? [])
            .sorted { ($0.batch?.name ?? "") < ($1.batch?.name ?? "") }
            .map { "\($0.batch?.name ?? "?") \(DoseFormat.qty($0.quantity))" }
        let schedule = parts.isEmpty ? "PRN" : parts.joined(separator: ", ")
        return "\(med.strength) — \(schedule)"
    }

    static func requireReason(_ reason: String) throws {
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MedicationServiceError.reasonRequired
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the test command.
Expected: PASS (both `testAdd…` tests).

- [ ] **Step 6: Commit**

```bash
git add PillDaddy/Helpers/DoseFormat.swift PillDaddy/Services/MedicationService.swift PillDaddyTests/MedicationServiceTests.swift
git commit -m "feat: MedicationService.addMedication + DoseFormat helper"
```

---

## Task 2: MedicationService.changeDose

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift`
- Test: `PillDaddyTests/MedicationServiceTests.swift`

- [ ] **Step 1: Add the failing tests**

Add these methods inside `MedicationServiceTests`:

```swift
    func testChangeDoseMutatesQuantityAndWritesEvent() throws {
        let context = try makeContext()
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try XCTUnwrap(med.batchItems?.first)

        try MedicationService.changeDose(
            med, newStrength: "30mg",
            newQuantities: [(item: item, quantity: 0.5)],
            reason: "Reduced after dizziness", in: context)

        XCTAssertEqual(item.quantity, 0.5)
        let doseEvents = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.doseChanged.rawValue }
        XCTAssertEqual(doseEvents.count, 1)
        XCTAssertEqual(doseEvents.first?.oldValue, "30mg — Blue 1")
        XCTAssertEqual(doseEvents.first?.newValue, "30mg — Blue 0.5")
    }

    func testChangeDoseWithEmptyReasonThrows() throws {
        let context = try makeContext()
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        XCTAssertThrowsError(
            try MedicationService.changeDose(med, newStrength: "15mg",
                newQuantities: [], reason: "   ", in: context)
        ) { error in
            XCTAssertEqual(error as? MedicationServiceError, .reasonRequired)
        }
    }
```

- [ ] **Step 2: Run to verify failure**

Run the test command.
Expected: FAIL — `changeDose` not defined.

- [ ] **Step 3: Implement changeDose**

Add to `MedicationService` (before `// MARK: - Internal helpers`):

```swift
    /// Changes strength and/or per-batch quantities on the same medication and
    /// records a `doseChanged` event with an old→new summary. Reason required.
    static func changeDose(
        _ med: Medication,
        newStrength: String,
        newQuantities: [(item: BatchItem, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)
        let oldSummary = doseSummary(med)
        med.strength = newStrength
        for change in newQuantities {
            change.item.quantity = change.quantity
        }
        let newSummary = doseSummary(med)
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: reason,
            oldValue: oldSummary, newValue: newSummary, medication: med))
        try context.save()
    }
```

- [ ] **Step 4: Run to verify pass**

Run the test command.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/MedicationService.swift PillDaddyTests/MedicationServiceTests.swift
git commit -m "feat: MedicationService.changeDose"
```

---

## Task 3: MedicationService.changeInstructions

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift`
- Test: `PillDaddyTests/MedicationServiceTests.swift`

- [ ] **Step 1: Add the failing test**

Add inside `MedicationServiceTests`:

```swift
    func testChangeInstructionsUpdatesItemAndWritesEvent() throws {
        let context = try makeContext()
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try XCTUnwrap(med.batchItems?.first)

        try MedicationService.changeInstructions(
            item, newInstructions: "Take on empty stomach",
            reason: "Per pharmacist", in: context)

        XCTAssertEqual(item.instructionsOverride, "Take on empty stomach")
        let events = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.instructionsChanged.rawValue }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.newValue, "Take on empty stomach")
    }

    func testChangeInstructionsWithEmptyReasonThrows() throws {
        let context = try makeContext()
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let item = try XCTUnwrap(med.batchItems?.first)

        XCTAssertThrowsError(
            try MedicationService.changeInstructions(item, newInstructions: "x", reason: "", in: context)
        ) { XCTAssertEqual($0 as? MedicationServiceError, .reasonRequired) }
    }
```

- [ ] **Step 2: Run to verify failure**

Run the test command. Expected: FAIL — `changeInstructions` not defined.

- [ ] **Step 3: Implement changeInstructions**

Add to `MedicationService`:

```swift
    /// Updates a single membership's instructions and records an
    /// `instructionsChanged` event. Reason required.
    static func changeInstructions(
        _ item: BatchItem,
        newInstructions: String,
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)
        let old = item.instructionsOverride
        item.instructionsOverride = newInstructions
        context.insert(MedicationChangeEvent(
            type: .instructionsChanged, reasoning: reason,
            oldValue: old, newValue: newInstructions, medication: item.medication))
        try context.save()
    }
```

- [ ] **Step 4: Run to verify pass**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/MedicationService.swift PillDaddyTests/MedicationServiceTests.swift
git commit -m "feat: MedicationService.changeInstructions"
```

---

## Task 4: MedicationService.swap

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift`
- Test: `PillDaddyTests/MedicationServiceTests.swift`

- [ ] **Step 1: Add the failing tests**

Add inside `MedicationServiceTests`:

```swift
    func testSwapInheritsScheduleDiscontinuesOldAndLinksSuccessor() throws {
        let context = try makeContext()
        let blue = Batch(name: "Blue")
        let green = Batch(name: "Green")
        context.insert(blue)
        context.insert(green)
        let old = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0), (batch: green, quantity: 0.5)],
            reason: "", in: context)

        let new = try MedicationService.swap(
            old, newName: "Bisoprolol", newStrength: "5mg", newForm: "tablet",
            inheritSchedule: true, reason: "Cardiologist switch", in: context)

        XCTAssertFalse(old.isActive)
        XCTAssertNotNil(old.discontinuedAt)
        XCTAssertEqual(old.successor?.name, "Bisoprolol")
        XCTAssertEqual(new.batchItems?.count, 2)
        XCTAssertEqual((new.batchItems ?? []).map(\.quantity).sorted(), [0.5, 1.0])
        XCTAssertTrue((old.changeEvents ?? []).contains { $0.eventType == MedChangeType.swapped.rawValue })
        XCTAssertTrue((new.changeEvents ?? []).contains { $0.eventType == MedChangeType.added.rawValue })
        // Old med keeps its memberships (discontinue preserves history).
        XCTAssertEqual(old.batchItems?.count, 2)
    }

    func testSwapWithoutInheritLeavesNewUnscheduled() throws {
        let context = try makeContext()
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let old = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)

        let new = try MedicationService.swap(
            old, newName: "Bisoprolol", newStrength: "5mg", newForm: "tablet",
            inheritSchedule: false, reason: "Switch", in: context)

        XCTAssertEqual(new.batchItems ?? [], [])
        XCTAssertEqual(old.batchItems?.count, 1)
    }

    func testSwapWithEmptyReasonThrows() throws {
        let context = try makeContext()
        let old = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        XCTAssertThrowsError(
            try MedicationService.swap(old, newName: "B", newStrength: "5mg",
                newForm: "tablet", inheritSchedule: true, reason: " ", in: context)
        ) { XCTAssertEqual($0 as? MedicationServiceError, .reasonRequired) }
    }
```

- [ ] **Step 2: Run to verify failure**

Run the test command. Expected: FAIL — `swap` not defined.

- [ ] **Step 3: Implement swap**

Add to `MedicationService`:

```swift
    /// Atomically swaps one drug for a new one: create the replacement, optionally
    /// inherit the old drug's batch memberships, link `successor`, discontinue the
    /// old drug, and write a `swapped` event (old) + `added` event (new). Reason required.
    @discardableResult
    static func swap(
        _ oldMed: Medication,
        newName: String, newStrength: String, newForm: String,
        inheritSchedule: Bool,
        reason: String,
        in context: ModelContext
    ) throws -> Medication {
        try requireReason(reason)

        let newMed = Medication(name: newName, strength: newStrength, form: newForm)
        context.insert(newMed)

        if inheritSchedule {
            for item in oldMed.batchItems ?? [] {
                context.insert(BatchItem(
                    quantity: item.quantity,
                    instructionsOverride: item.instructionsOverride,
                    medication: newMed, batch: item.batch))
            }
        }

        let oldDescription = "\(oldMed.name) \(oldMed.strength)"
        oldMed.successor = newMed
        oldMed.isActive = false
        oldMed.discontinuedAt = .now

        context.insert(MedicationChangeEvent(
            type: .swapped, reasoning: reason,
            oldValue: oldDescription, newValue: "\(newName) \(newStrength)",
            medication: oldMed))
        context.insert(MedicationChangeEvent(
            type: .added, reasoning: reason, medication: newMed))

        try context.save()
        return newMed
    }
```

- [ ] **Step 4: Run to verify pass**

Run the test command. Expected: PASS (all three swap tests).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/MedicationService.swift PillDaddyTests/MedicationServiceTests.swift
git commit -m "feat: MedicationService.swap (atomic, guided)"
```

---

## Task 5: MedicationService.discontinue + reactivate

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift`
- Test: `PillDaddyTests/MedicationServiceTests.swift`

- [ ] **Step 1: Add the failing tests**

Add inside `MedicationServiceTests`:

```swift
    func testDiscontinueKeepsMembershipsAndMarksInactive() throws {
        let context = try makeContext()
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)

        try MedicationService.discontinue(med, reason: "No longer needed", in: context)

        XCTAssertFalse(med.isActive)
        XCTAssertNotNil(med.discontinuedAt)
        XCTAssertEqual(med.batchItems?.count, 1) // memberships preserved
        XCTAssertTrue((med.changeEvents ?? []).contains { $0.eventType == MedChangeType.discontinued.rawValue })
    }

    func testReactivateRestoresActiveState() throws {
        let context = try makeContext()
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)
        try MedicationService.discontinue(med, reason: "stop", in: context)

        try MedicationService.reactivate(med, reason: "Restarting", in: context)

        XCTAssertTrue(med.isActive)
        XCTAssertNil(med.discontinuedAt)
        XCTAssertTrue((med.changeEvents ?? []).contains { $0.eventType == MedChangeType.reactivated.rawValue })
    }

    func testDiscontinueWithEmptyReasonThrows() throws {
        let context = try makeContext()
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        XCTAssertThrowsError(
            try MedicationService.discontinue(med, reason: "", in: context)
        ) { XCTAssertEqual($0 as? MedicationServiceError, .reasonRequired) }
    }
```

- [ ] **Step 2: Run to verify failure**

Run the test command. Expected: FAIL — `discontinue`/`reactivate` not defined.

- [ ] **Step 3: Implement discontinue and reactivate**

Add to `MedicationService`:

```swift
    /// Marks a medication discontinued (keeps its memberships and history) and
    /// writes a `discontinued` event. Reason required.
    static func discontinue(_ med: Medication, reason: String, in context: ModelContext) throws {
        try requireReason(reason)
        med.isActive = false
        med.discontinuedAt = .now
        context.insert(MedicationChangeEvent(type: .discontinued, reasoning: reason, medication: med))
        try context.save()
    }

    /// Restores a discontinued medication to the active regime (its memberships
    /// reappear automatically) and writes a `reactivated` event. Reason required.
    static func reactivate(_ med: Medication, reason: String, in context: ModelContext) throws {
        try requireReason(reason)
        med.isActive = true
        med.discontinuedAt = nil
        context.insert(MedicationChangeEvent(type: .reactivated, reasoning: reason, medication: med))
        try context.save()
    }
```

- [ ] **Step 4: Run to verify pass**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/MedicationService.swift PillDaddyTests/MedicationServiceTests.swift
git commit -m "feat: MedicationService.discontinue + reactivate"
```

---

## Task 6: RegimeQuery

**Files:**
- Create: `PillDaddy/Services/RegimeQuery.swift`
- Test: `PillDaddyTests/RegimeQueryTests.swift`

- [ ] **Step 1: Write the failing test**

`PillDaddyTests/RegimeQueryTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class RegimeQueryTests: XCTestCase {

    func testActiveBatchGroupsExcludeDiscontinuedAndPRN() throws {
        let context = try ModelTestSupport.makeContainer().mainContext
        let blue = Batch(name: "Blue", sortOrder: 0)
        context.insert(blue)

        let active = MedicationService.addMedication(
            name: "Active", strength: "10mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        _ = active

        let discontinued = MedicationService.addMedication(
            name: "Stopped", strength: "10mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        try MedicationService.discontinue(discontinued, reason: "stop", in: context)

        let groups = try RegimeQuery.activeBatchGroups(in: context)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.items.count, 1)
        XCTAssertEqual(groups.first?.items.first?.medication?.name, "Active")
    }

    func testActivePRNMedsReturnsOnlyActivePRN() throws {
        let context = try ModelTestSupport.makeContainer().mainContext
        _ = MedicationService.addMedication(
            name: "Tylenol", strength: "500mg", form: "tablet",
            isPRN: true, notes: "", placements: [], reason: "", in: context)
        let scheduled = MedicationService.addMedication(
            name: "Scheduled", strength: "1mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)
        _ = scheduled

        let prn = try RegimeQuery.activePRNMeds(in: context)
        XCTAssertEqual(prn.map(\.name), ["Tylenol"])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run the test command. Expected: FAIL — `RegimeQuery` not defined.

- [ ] **Step 3: Implement RegimeQuery**

`PillDaddy/Services/RegimeQuery.swift`:

```swift
import Foundation
import SwiftData

/// Read helpers that assemble the *active* daily regime from the model.
@MainActor
enum RegimeQuery {

    /// A batch paired with its active, non-PRN memberships (sorted by med name).
    struct BatchGroup: Identifiable {
        let batch: Batch
        let items: [BatchItem]
        var id: PersistentIdentifier { batch.persistentModelIdentifier }
    }

    /// All batches (ordered by sortOrder then time), each with its active meds only.
    static func activeBatchGroups(in context: ModelContext) throws -> [BatchGroup] {
        let batches = try context.fetch(FetchDescriptor<Batch>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timeOfDay)]))
        return batches.map { batch in
            let items = (batch.items ?? [])
                .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
                .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
            return BatchGroup(batch: batch, items: items)
        }
    }

    /// Active PRN (as-needed) medications, sorted by name.
    static func activePRNMeds(in context: ModelContext) throws -> [Medication] {
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isActive && $0.isPRN },
            sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/RegimeQuery.swift PillDaddyTests/RegimeQueryTests.swift
git commit -m "feat: RegimeQuery active-regime helpers"
```

---

## Task 7: PreviewSupport + MedicationEditor

**Files:**
- Create: `PillDaddy/Helpers/PreviewSupport.swift`
- Create: `PillDaddy/Views/Meds/MedicationEditor.swift`

- [ ] **Step 1: Create PreviewSupport**

`PillDaddy/Helpers/PreviewSupport.swift`:

```swift
#if DEBUG
import SwiftData

/// A seeded in-memory container for SwiftUI previews.
@MainActor
enum PreviewSupport {
    static func seededContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: PillDaddySchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        SeedData.seedIfEmpty(container.mainContext)
        try? container.mainContext.save()
        return container
    }

    /// First medication in the seeded store (for detail/editor previews).
    static func firstMedication(_ container: ModelContainer) -> Medication {
        try! container.mainContext.fetch(FetchDescriptor<Medication>()).first!
    }
}
#endif
```

- [ ] **Step 2: Create MedicationEditor**

`PillDaddy/Views/Meds/MedicationEditor.swift`:

```swift
import SwiftUI
import SwiftData

/// Add a new medication (with inline batch assignment + optional reason) or edit
/// an existing one's non-clinical details. Strength/dose changes go through the
/// guided Change-dose flow, not here.
struct MedicationEditor: View {
    enum Mode {
        case add
        case edit(Medication)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var batches: [Batch]

    @State private var name = ""
    @State private var strength = ""
    @State private var form = "tablet"
    @State private var notes = ""
    @State private var isPRN = false
    @State private var reason = ""
    @State private var selected: Set<PersistentIdentifier> = []
    @State private var quantities: [PersistentIdentifier: Double] = [:]

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    if isAdd {
                        TextField("Strength (e.g. 30mg)", text: $strength)
                    }
                    TextField("Form (e.g. tablet)", text: $form)
                    Toggle("As needed (PRN)", isOn: $isPRN)
                    TextField("General notes", text: $notes, axis: .vertical)
                }

                if isAdd && !isPRN {
                    Section("Add to batches") {
                        if batches.isEmpty {
                            Text("No batches yet — add one from the Meds tab.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(batches) { batch in
                            batchAssignRow(batch)
                        }
                    }
                    Section("Why started? (optional)") {
                        TextField("Reason", text: $reason, axis: .vertical)
                    }
                }
            }
            .navigationTitle(isAdd ? "New medication" : "Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private func batchAssignRow(_ batch: Batch) -> some View {
        let id = batch.persistentModelIdentifier
        let isOn = selected.contains(id)
        VStack(alignment: .leading) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { selected.insert(id); quantities[id] = quantities[id] ?? 1.0 }
                    else { selected.remove(id) }
                })) {
                HStack {
                    Circle().fill(Color(hex: batch.colorHex)).frame(width: 12, height: 12)
                    Text(batch.name.isEmpty ? "Batch" : batch.name)
                }
            }
            if isOn {
                Stepper(value: Binding(
                    get: { quantities[id] ?? 1.0 },
                    set: { quantities[id] = $0 }),
                    in: 0.5...20, step: 0.5) {
                    Text("Quantity: \(DoseFormat.qty(quantities[id] ?? 1.0))")
                }
            }
        }
    }

    private func load() {
        guard case .edit(let med) = mode else { return }
        name = med.name
        strength = med.strength
        form = med.form
        notes = med.generalNotes
        isPRN = med.isPRN
    }

    private func save() {
        switch mode {
        case .add:
            let placements: [(batch: Batch, quantity: Double)] = isPRN ? [] :
                batches
                    .filter { selected.contains($0.persistentModelIdentifier) }
                    .map { ($0, quantities[$0.persistentModelIdentifier] ?? 1.0) }
            MedicationService.addMedication(
                name: name, strength: strength, form: form,
                isPRN: isPRN, notes: notes, placements: placements,
                reason: reason, in: context)
        case .edit(let med):
            let wasScheduled = !(med.batchItems ?? []).isEmpty
            med.name = name
            med.form = form
            med.generalNotes = notes
            if isPRN && wasScheduled {
                for item in med.batchItems ?? [] { context.delete(item) }
            }
            med.isPRN = isPRN
            try? context.save()
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    MedicationEditor(mode: .add)
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 3: Generate project and build**

Run the build command.
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Helpers/PreviewSupport.swift PillDaddy/Views/Meds/MedicationEditor.swift PillDaddy.xcodeproj
git commit -m "feat: MedicationEditor + preview support"
```

---

## Task 8: BatchEditor (the color manager)

**Files:**
- Create: `PillDaddy/Views/Meds/BatchEditor.swift`

- [ ] **Step 1: Create BatchEditor**

`PillDaddy/Views/Meds/BatchEditor.swift`:

```swift
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
                        ForEach(MealRelation.allCases) { Text(mealLabel($0)).tag($0) }
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
        let present = Set((batch.items ?? []).compactMap { $0.medication?.persistentModelIdentifier })
        return meds.filter { !present.contains($0.persistentModelIdentifier) }
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
```

- [ ] **Step 2: Generate project and build**

Run the build command.
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Meds/BatchEditor.swift PillDaddy.xcodeproj
git commit -m "feat: BatchEditor (color manager)"
```

---

## Task 9: Guided change sheets

**Files:**
- Create: `PillDaddy/Views/Meds/ChangeDoseSheet.swift`
- Create: `PillDaddy/Views/Meds/ChangeInstructionsSheet.swift`
- Create: `PillDaddy/Views/Meds/SwapSheet.swift`
- Create: `PillDaddy/Views/Meds/LifecycleReasonSheet.swift`

- [ ] **Step 1: Create ChangeDoseSheet**

`PillDaddy/Views/Meds/ChangeDoseSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// Guided dose change: edit strength and per-batch quantities; reason required.
struct ChangeDoseSheet: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var strength = ""
    @State private var quantities: [PersistentIdentifier: Double] = [:]
    @State private var reason = ""

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New dose") {
                    TextField("Strength", text: $strength)
                    ForEach(medication.batchItems ?? []) { item in
                        let id = item.persistentModelIdentifier
                        Stepper(value: Binding(
                            get: { quantities[id] ?? item.quantity },
                            set: { quantities[id] = $0 }),
                            in: 0.5...20, step: 0.5) {
                            Text("\(item.batch?.name ?? "—"): \(DoseFormat.qty(quantities[id] ?? item.quantity))")
                        }
                    }
                }
                Section("Reason (required)") {
                    TextField("Why is the dose changing?", text: $reason, axis: .vertical)
                }
            }
            .navigationTitle("Change dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!reasonValid)
                }
            }
            .onAppear { strength = medication.strength }
        }
    }

    private func save() {
        let changes = (medication.batchItems ?? []).compactMap {
            item -> (item: BatchItem, quantity: Double)? in
            guard let q = quantities[item.persistentModelIdentifier] else { return nil }
            return (item, q)
        }
        try? MedicationService.changeDose(
            medication, newStrength: strength, newQuantities: changes,
            reason: reason, in: context)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return ChangeDoseSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
```

- [ ] **Step 2: Create ChangeInstructionsSheet**

`PillDaddy/Views/Meds/ChangeInstructionsSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// Guided instructions change for one membership; reason required.
struct ChangeInstructionsSheet: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selection: BatchItem?
    @State private var instructions = ""
    @State private var reason = ""

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Membership") {
                    Picker("Batch", selection: $selection) {
                        ForEach(medication.batchItems ?? []) { item in
                            Text(item.batch?.name ?? "—").tag(Optional(item))
                        }
                    }
                }
                Section("Instructions") {
                    TextField("e.g. take on empty stomach", text: $instructions, axis: .vertical)
                }
                Section("Reason (required)") {
                    TextField("Why are instructions changing?", text: $reason, axis: .vertical)
                }
            }
            .navigationTitle("Change instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(selection == nil || !reasonValid)
                }
            }
            .onAppear {
                selection = (medication.batchItems ?? []).first
                instructions = selection?.instructionsOverride ?? ""
            }
            .onChange(of: selection) { _, new in
                instructions = new?.instructionsOverride ?? ""
            }
        }
    }

    private func save() {
        guard let item = selection else { return }
        try? MedicationService.changeInstructions(
            item, newInstructions: instructions, reason: reason, in: context)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return ChangeInstructionsSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
```

- [ ] **Step 3: Create SwapSheet**

`PillDaddy/Views/Meds/SwapSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// Guided atomic swap: name the replacement, optionally inherit the old drug's
/// schedule, give a required reason. The old drug is auto-discontinued on save.
struct SwapSheet: View {
    @Bindable var oldMed: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var strength = ""
    @State private var form = "tablet"
    @State private var inheritSchedule = true
    @State private var reason = ""

    private var canSave: Bool {
        !name.isEmpty && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Replacement drug") {
                    TextField("Name", text: $name)
                    TextField("Strength", text: $strength)
                    TextField("Form", text: $form)
                }
                Section("Schedule") {
                    Toggle("Keep \(oldMed.name)'s schedule", isOn: $inheritSchedule)
                    if inheritSchedule {
                        ForEach(oldMed.batchItems ?? []) { item in
                            HStack {
                                Text(item.batch?.name ?? "—")
                                Spacer()
                                Text("\(DoseFormat.qty(item.quantity)) \(oldMed.form)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Reason (required)") {
                    TextField("Why the swap?", text: $reason, axis: .vertical)
                }
            }
            .navigationTitle("Swap medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save swap") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        _ = try? MedicationService.swap(
            oldMed, newName: name, newStrength: strength, newForm: form,
            inheritSchedule: inheritSchedule, reason: reason, in: context)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return SwapSheet(oldMed: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
```

- [ ] **Step 4: Create LifecycleReasonSheet**

`PillDaddy/Views/Meds/LifecycleReasonSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// Reason-gated discontinue / reactivate flow.
struct LifecycleReasonSheet: View {
    @Bindable var medication: Medication
    let reactivating: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(reactivating
                         ? "Reactivating restores this medication to the active regime."
                         : "Discontinuing removes this medication from the active regime. Its full history is kept.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Reason (required)") {
                    TextField("Reason", text: $reason, axis: .vertical)
                }
            }
            .navigationTitle(reactivating ? "Reactivate" : "Discontinue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(reactivating ? "Reactivate" : "Discontinue", role: reactivating ? .none : .destructive) {
                        save()
                    }
                    .disabled(!reasonValid)
                }
            }
        }
    }

    private func save() {
        if reactivating {
            try? MedicationService.reactivate(medication, reason: reason, in: context)
        } else {
            try? MedicationService.discontinue(medication, reason: reason, in: context)
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return LifecycleReasonSheet(medication: PreviewSupport.firstMedication(container), reactivating: false)
        .modelContainer(container)
}
#endif
```

- [ ] **Step 5: Generate project and build**

Run the build command.
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add PillDaddy/Views/Meds/ChangeDoseSheet.swift PillDaddy/Views/Meds/ChangeInstructionsSheet.swift PillDaddy/Views/Meds/SwapSheet.swift PillDaddy/Views/Meds/LifecycleReasonSheet.swift PillDaddy.xcodeproj
git commit -m "feat: guided change sheets (dose, instructions, swap, lifecycle)"
```

---

## Task 10: MedicationDetailView

**Files:**
- Create: `PillDaddy/Views/Meds/MedicationDetailView.swift`

- [ ] **Step 1: Create MedicationDetailView**

`PillDaddy/Views/Meds/MedicationDetailView.swift`:

```swift
import SwiftUI
import SwiftData

/// Detail for one medication: memberships, a "why/history" preview, and the
/// guided action set. Trivial edits use the editor; meaningful changes are gated.
struct MedicationDetailView: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context

    @State private var sheet: DetailSheet?

    enum DetailSheet: Identifiable {
        case edit, dose, instructions, swap, lifecycle
        var id: Int { hashValue }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Strength", value: medication.strength)
                LabeledContent("Form", value: medication.form)
                if medication.isPRN {
                    Text("As needed (PRN)").foregroundStyle(.secondary)
                }
                if !medication.isActive {
                    Text("Discontinued").foregroundStyle(.secondary)
                }
                if !medication.generalNotes.isEmpty {
                    Text(medication.generalNotes).font(.callout)
                }
            }

            if !(medication.batchItems ?? []).isEmpty {
                Section("Taken in") {
                    ForEach(medication.batchItems ?? []) { item in
                        HStack {
                            Circle().fill(Color(hex: item.batch?.colorHex ?? "#8E8E93"))
                                .frame(width: 10, height: 10)
                            Text(item.batch?.name ?? "—")
                            Spacer()
                            Text("\(DoseFormat.qty(item.quantity)) \(medication.form)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Why / history") {
                let events = (medication.changeEvents ?? [])
                    .sorted { $0.timestamp > $1.timestamp }
                    .prefix(5)
                if events.isEmpty {
                    Text("No history yet").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(events)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eventTitle(event)).font(.subheadline).bold()
                            if !event.reasoning.isEmpty {
                                Text(event.reasoning).font(.caption)
                            }
                            if !event.oldValue.isEmpty || !event.newValue.isEmpty {
                                Text("\(event.oldValue) → \(event.newValue)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Actions") {
                if medication.isActive {
                    Button("Edit details") { sheet = .edit }
                    Button("Change dose…") { sheet = .dose }
                    if !medication.isPRN && !(medication.batchItems ?? []).isEmpty {
                        Button("Change instructions…") { sheet = .instructions }
                    }
                    Button("Swap to another drug…") { sheet = .swap }
                    Button("Discontinue…", role: .destructive) { sheet = .lifecycle }
                } else {
                    Button("Reactivate…") { sheet = .lifecycle }
                    Button("Edit details") { sheet = .edit }
                }
            }
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { which in
            switch which {
            case .edit: MedicationEditor(mode: .edit(medication))
            case .dose: ChangeDoseSheet(medication: medication)
            case .instructions: ChangeInstructionsSheet(medication: medication)
            case .swap: SwapSheet(oldMed: medication)
            case .lifecycle: LifecycleReasonSheet(medication: medication, reactivating: !medication.isActive)
            }
        }
    }

    private func eventTitle(_ event: MedicationChangeEvent) -> String {
        switch MedChangeType(rawValue: event.eventType) {
        case .added: return "Added"
        case .doseChanged: return "Dose changed"
        case .instructionsChanged: return "Instructions changed"
        case .swapped: return "Swapped"
        case .discontinued: return "Discontinued"
        case .reactivated: return "Reactivated"
        case .note, .none: return "Note"
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return NavigationStack {
        MedicationDetailView(medication: PreviewSupport.firstMedication(container))
    }
    .modelContainer(container)
}
#endif
```

- [ ] **Step 2: Generate project and build**

Run the build command.
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Meds/MedicationDetailView.swift PillDaddy.xcodeproj
git commit -m "feat: MedicationDetailView with guided actions"
```

---

## Task 11: RegimeView + AllMedsView

**Files:**
- Create: `PillDaddy/Views/Meds/RegimeView.swift`
- Create: `PillDaddy/Views/Meds/AllMedsView.swift`

- [ ] **Step 1: Create RegimeView**

`PillDaddy/Views/Meds/RegimeView.swift`:

```swift
import SwiftUI
import SwiftData

/// Active regime grouped under color batches, with a trailing PRN section.
struct RegimeView: View {
    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var batches: [Batch]
    @Query(filter: #Predicate<Medication> { $0.isActive && $0.isPRN }, sort: \Medication.name)
    private var prnMeds: [Medication]

    @State private var editingBatch: Batch?

    var body: some View {
        List {
            ForEach(batches) { batch in
                Section {
                    let items = activeItems(batch)
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
                    header(batch)
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
                                Text(med.strength).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editingBatch) { BatchEditor(batch: $0) }
    }

    private func header(_ batch: Batch) -> some View {
        HStack {
            Circle().fill(Color(hex: batch.colorHex)).frame(width: 12, height: 12)
            Text(batch.name.isEmpty ? "Batch" : batch.name)
            Text(batch.timeOfDay, style: .time)
            Spacer()
            Button("Edit") { editingBatch = batch }.font(.caption)
        }
    }

    private func row(_ item: BatchItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.medication?.name ?? "—")
                Text(item.medication?.strength ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(DoseFormat.qty(item.quantity)) \(item.medication?.form ?? "")")
                .foregroundStyle(.secondary)
        }
    }

    private func activeItems(_ batch: Batch) -> [BatchItem] {
        (batch.items ?? [])
            .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
            .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
    }
}

#if DEBUG
#Preview {
    NavigationStack { RegimeView() }
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 2: Create AllMedsView**

`PillDaddy/Views/Meds/AllMedsView.swift`:

```swift
import SwiftUI
import SwiftData

/// Flat A–Z list of medications with show/hide-discontinued and a guarded hard delete.
struct AllMedsView: View {
    @Query(sort: \Medication.name) private var allMeds: [Medication]
    @Environment(\.modelContext) private var context

    @State private var showDiscontinued = false
    @State private var pendingDelete: Medication?

    private var visibleMeds: [Medication] {
        showDiscontinued ? allMeds : allMeds.filter { $0.isActive }
    }

    var body: some View {
        List {
            Toggle("Show discontinued", isOn: $showDiscontinued)
            ForEach(visibleMeds) { med in
                NavigationLink {
                    MedicationDetailView(medication: med)
                } label: {
                    row(med)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDelete = med }
                }
            }
        }
        .confirmationDialog(
            "Permanently delete this medication and its history? This can't be undone. To stop a med while keeping its history, use Discontinue instead.",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                if let med = pendingDelete {
                    context.delete(med)
                    try? context.save()
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func row(_ med: Medication) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(med.name)
                Text(subtitle(med)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !med.isActive {
                tag("Discontinued")
            } else if med.isPRN {
                tag("PRN")
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2))
            .clipShape(Capsule())
    }

    private func subtitle(_ med: Medication) -> String {
        let batches = (med.batchItems ?? []).compactMap { $0.batch?.name }.sorted()
        let suffix = batches.isEmpty ? "" : " · " + batches.joined(separator: ", ")
        return med.strength + suffix
    }
}

#if DEBUG
#Preview {
    NavigationStack { AllMedsView() }
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 3: Generate project and build**

Run the build command.
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Views/Meds/RegimeView.swift PillDaddy/Views/Meds/AllMedsView.swift PillDaddy.xcodeproj
git commit -m "feat: RegimeView + AllMedsView"
```

---

## Task 12: MedsView + tab wiring + full verification

**Files:**
- Create: `PillDaddy/Views/Meds/MedsView.swift`
- Modify: `PillDaddy/Views/MainTabView.swift`

- [ ] **Step 1: Create MedsView**

`PillDaddy/Views/Meds/MedsView.swift`:

```swift
import SwiftUI
import SwiftData

/// Host for the Meds tab: Regime ⇄ All Meds toggle and an add menu.
struct MedsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case regime = "Regime"
        case allMeds = "All Meds"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .regime
    @State private var showingAddMed = false
    @State private var showingAddBatch = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .regime: RegimeView()
                case .allMeds: AllMedsView()
                }
            }
            .navigationTitle("Meds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add medication") { showingAddMed = true }
                        Button("Add batch") { showingAddBatch = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMed) { MedicationEditor(mode: .add) }
            .sheet(isPresented: $showingAddBatch) { BatchEditor(batch: nil) }
        }
    }
}

#if DEBUG
#Preview {
    MedsView()
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 2: Wire the Meds tab in MainTabView**

In `PillDaddy/Views/MainTabView.swift`, replace this line:

```swift
            PlaceholderTab(title: "Meds", systemImage: "pills")
                .tabItem { Label("Meds", systemImage: "pills") }
```

with:

```swift
            MedsView()
                .tabItem { Label("Meds", systemImage: "pills") }
```

- [ ] **Step 3: Generate project and build**

Run the build command.
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full test suite**

Run the test command.
Expected: All tests pass (MedicationServiceTests, RegimeQueryTests, and the existing Session 0 model tests).

- [ ] **Step 5: Manual dogfood verification (simulator)**

Launch the app with seed data:

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; true
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build build
xcrun simctl install booted "$(find build/Build/Products -name 'PillDaddy.app' -maxdepth 2 | head -1)"
xcrun simctl launch booted com.pilldaddy.PillDaddy -seedTestData
```

Then in the simulator confirm:
1. **Meds tab** opens to the **Regime** view: Blue @ 9:00 (Metoprolol 1 tab, Vitamin D 1 cap) and Green @ 19:00 (Metoprolol ½ tab); an **As needed (PRN)** section with Acetaminophen.
2. **Toggle to All Meds** shows the A–Z list; **Show discontinued** is off by default.
3. **Add medication** (+ menu) → create a med, assign to Blue with quantity, Save → it appears in Regime.
4. **Tap Metoprolol → Change dose…** → Save is disabled until a reason is typed; change ½→1, Save → quantity updates and a "Dose changed" row appears in Why/history.
5. **Swap to another drug…** → enter a replacement, keep schedule, add reason, Save → old med leaves the regime, replacement appears with inherited quantities.
6. **Discontinue…** a med (reason required) → it leaves Regime; toggle **Show discontinued** in All Meds → it appears with a Discontinued tag; open it → **Reactivate…** → it returns to Regime.
7. **Tap a batch header → Edit** → change its color → Regime reflects the new color.

- [ ] **Step 6: Final commit**

```bash
git add PillDaddy/Views/Meds/MedsView.swift PillDaddy/Views/MainTabView.swift PillDaddy.xcodeproj
git commit -m "feat: wire Meds tab (Regime/All Meds toggle, add menu)"
```

---

## Done criteria

- `xcodegen generate` + `xcodebuild build` succeed; the full test bundle passes.
- The Meds tab is fully usable: regime view, all-meds list, add/edit medication, batch/color editing, and all four guided change flows, each writing the correct `MedicationChangeEvent` and gating empty reasons.
- No model changes were made; the Session 0 schema is reused as-is.
