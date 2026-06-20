# Session 4 — Medication Change Journal & Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface a lineage-aware reasoning timeline that walks a medication's `successor`/`predecessor` chain and merges every drug's change events into one chronological story, plus the ability to append a free-form retrospective note.

**Architecture:** A pure `MedicationLineage` helper traverses the existing in-memory relationships (no queries, no schema change) to produce the ordered line and a merged, presentation-rule-filtered event stream. `MedicationTimelineView` renders that stream as a pushed `List`; `MedicationDetailView`'s existing preview becomes lineage-aware and gains a "See full history" link. A new `MedicationService.addNote` writes `note` events. Seed data gains a swap chain so the feature is dogfoodable on launch.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, XcodeGen (`project.yml`), Xcode 26.

**Spec:** [`docs/superpowers/specs/2026-06-19-session-4-medication-journal-continuity-design.md`](../specs/2026-06-19-session-4-medication-journal-continuity-design.md)

---

## Conventions for every task

- **Build/test command (full suite):**
  `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Single test class/method:** append e.g.
  `-only-testing:PillDaddyTests/MedicationLineageTests`
- **After creating or deleting any file, regenerate the project first:** `xcodegen generate`
  (XcodeGen includes sources by directory, so new files under `PillDaddy/` and `PillDaddyTests/`
  are picked up automatically — but the `.xcodeproj` must be regenerated before building.)
- Tests follow the existing pattern: `@MainActor final class … : XCTestCase`, container from
  `ModelTestSupport.makeContainer()`, `@testable import PillDaddy`.
- Commit locally at the end of each task (per `AGENTS.md`).

---

## File Structure

**Create:**
- `PillDaddy/Services/MedicationLineage.swift` — pure chain-walk + merged event stream + title helper.
- `PillDaddy/Views/Meds/MedicationTimelineView.swift` — the pushed timeline screen + the reusable `TimelineEventRow`.
- `PillDaddy/Views/Meds/AddNoteSheet.swift` — the commit-or-cancel note input sheet.
- `PillDaddyTests/MedicationLineageTests.swift` — unit tests for the primitive.

**Modify:**
- `PillDaddy/Services/MedicationService.swift` — add `addNote`.
- `PillDaddy/Views/Meds/MedicationDetailView.swift` — lineage-aware preview, reuse `TimelineEventRow`, add "See full history" `NavigationLink`, remove the now-shared `eventTitle`.
- `PillDaddy/Helpers/SeedData.swift` — add an Atenolol → Metoprolol swap chain + a note.
- `PillDaddyTests/MedicationServiceTests.swift` — `addNote` tests.
- `PillDaddyTests/SeedDataTests.swift` — assert the seed chain exists.

---

## Task 1: `MedicationLineage.ordered` — walk the chain

**Files:**
- Create: `PillDaddy/Services/MedicationLineage.swift`
- Test: `PillDaddyTests/MedicationLineageTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/MedicationLineageTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MedicationLineageTests: XCTestCase {

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

    /// Builds A → B → C and returns the three meds in chain order.
    private func makeChain() -> (a: Medication, b: Medication, c: Medication) {
        let a = Medication(name: "Atenolol", strength: "25mg")
        let b = Medication(name: "Metoprolol", strength: "30mg")
        let c = Medication(name: "Bisoprolol", strength: "5mg")
        context.insert(a); context.insert(b); context.insert(c)
        a.successor = b
        b.successor = c
        return (a, b, c)
    }

    func testOrderedFromMidChainReturnsWholeLineOldestFirst() {
        let chain = makeChain()
        let line = MedicationLineage.ordered(from: chain.b)
        XCTAssertEqual(line.map(\.name), ["Atenolol", "Metoprolol", "Bisoprolol"])
    }

    func testOrderedFromTipReturnsWholeLine() {
        let chain = makeChain()
        let line = MedicationLineage.ordered(from: chain.c)
        XCTAssertEqual(line.map(\.name), ["Atenolol", "Metoprolol", "Bisoprolol"])
    }

    func testOrderedForSingleMedIsJustItself() {
        let med = Medication(name: "Vitamin D", strength: "1000 IU")
        context.insert(med)
        XCTAssertEqual(MedicationLineage.ordered(from: med).map(\.name), ["Vitamin D"])
    }

    func testOrderedTerminatesOnCycle() {
        let a = Medication(name: "A", strength: "1")
        let b = Medication(name: "B", strength: "1")
        context.insert(a); context.insert(b)
        a.successor = b
        b.successor = a   // malformed cycle
        let line = MedicationLineage.ordered(from: a)
        // Must terminate and visit each med at most once.
        XCTAssertEqual(Set(line.map(\.name)), ["A", "B"])
        XCTAssertEqual(line.count, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/MedicationLineageTests`
Expected: FAIL to compile — "cannot find 'MedicationLineage' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `PillDaddy/Services/MedicationLineage.swift`:

```swift
import Foundation
import SwiftData

/// Pure helpers for reading a medication's *therapy line* — the chain of drugs
/// connected by swaps (`predecessor`/`successor`) — and merging their change
/// events into one continuous, lineage-aware story. No model or schema changes;
/// traverses in-memory relationships only.
@MainActor
enum MedicationLineage {

    /// The whole therapy line that `med` belongs to, oldest → newest. Walks
    /// `predecessor` back to the root, then `successor` forward to the tip.
    /// Cycle-guarded: every med is visited at most once.
    static func ordered(from med: Medication) -> [Medication] {
        // Walk back to the root.
        var root = med
        var backVisited: Set<PersistentIdentifier> = [med.persistentModelID]
        while let prev = root.predecessor, !backVisited.contains(prev.persistentModelID) {
            backVisited.insert(prev.persistentModelID)
            root = prev
        }
        // Walk forward from the root, collecting the line.
        var line: [Medication] = []
        var seen: Set<PersistentIdentifier> = []
        var node: Medication? = root
        while let current = node, !seen.contains(current.persistentModelID) {
            seen.insert(current.persistentModelID)
            line.append(current)
            node = current.successor
        }
        return line
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/MedicationLineageTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/MedicationLineage.swift PillDaddyTests/MedicationLineageTests.swift PillDaddy.xcodeproj
git commit -m "feat: MedicationLineage.ordered chain walk (cycle-guarded)"
```

---

## Task 2: `MedicationLineage.events` — merged, rule-filtered stream

**Files:**
- Modify: `PillDaddy/Services/MedicationLineage.swift`
- Test: `PillDaddyTests/MedicationLineageTests.swift`

- [ ] **Step 1: Write the failing test**

Append these tests to `MedicationLineageTests`:

```swift
    /// Helper: attach an event with an explicit timestamp.
    private func addEvent(_ type: MedChangeType, to med: Medication,
                          daysAgo: Int, reasoning: String = "",
                          oldValue: String = "", newValue: String = "") {
        let ts = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        context.insert(MedicationChangeEvent(
            timestamp: ts, type: type, reasoning: reasoning,
            oldValue: oldValue, newValue: newValue, medication: med))
    }

    func testEventsMergeChainNewestFirst() {
        let chain = makeChain()
        addEvent(.added, to: chain.a, daysAgo: 150)
        addEvent(.swapped, to: chain.a, daysAgo: 100)
        addEvent(.swapped, to: chain.b, daysAgo: 60)
        addEvent(.doseChanged, to: chain.c, daysAgo: 30)

        let events = MedicationLineage.events(from: chain.c)
        // Newest first; the suppressed `added` on B/C never existed here.
        XCTAssertEqual(events.map { MedChangeType(rawValue: $0.event.eventType) },
                       [.doseChanged, .swapped, .swapped, .added])
    }

    func testEventsSuppressAddedOnSwapBornMeds() {
        let chain = makeChain()
        addEvent(.added, to: chain.a, daysAgo: 100)   // root: kept
        addEvent(.added, to: chain.b, daysAgo: 60)    // swap-born: suppressed
        addEvent(.added, to: chain.c, daysAgo: 30)    // swap-born: suppressed

        let events = MedicationLineage.events(from: chain.c)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.owningMed.name, "Atenolol")
    }

    func testEventsMarkAnchorAndSuccessorName() {
        let chain = makeChain()
        addEvent(.swapped, to: chain.a, daysAgo: 100)   // owned by Atenolol → successor Metoprolol
        addEvent(.doseChanged, to: chain.b, daysAgo: 60) // anchor

        let events = MedicationLineage.events(from: chain.b)
        let swap = try! XCTUnwrap(events.first { $0.event.eventType == MedChangeType.swapped.rawValue })
        XCTAssertEqual(swap.successorName, "Metoprolol")
        XCTAssertFalse(swap.isAnchor)

        let dose = try! XCTUnwrap(events.first { $0.event.eventType == MedChangeType.doseChanged.rawValue })
        XCTAssertTrue(dose.isAnchor)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/MedicationLineageTests`
Expected: FAIL to compile — "type 'MedicationLineage' has no member 'events'" and "no type named 'LineageEvent'".

- [ ] **Step 3: Write minimal implementation**

Add to `PillDaddy/Services/MedicationLineage.swift` (a `LineageEvent` struct above the enum, and an `events` method inside the enum):

```swift
/// One change event positioned within a therapy line, carrying the context the
/// timeline UI needs to render it (which drug it belongs to, whether that drug
/// is the one the timeline was opened from, and the swap destination name).
struct LineageEvent: Identifiable {
    let event: MedicationChangeEvent
    let owningMed: Medication
    let isAnchor: Bool
    let successorName: String?

    var id: PersistentIdentifier { event.persistentModelID }
}
```

Inside `enum MedicationLineage`, add:

```swift
    /// Every change event across the whole line, newest first, with these
    /// presentation rules applied:
    ///   • `added` events on swap-born meds (those with a predecessor) are
    ///     dropped — the preceding "Swapped to …" row is the med's origin.
    /// `isAnchor` is true for events on `med` itself; `successorName` carries the
    /// next drug's name so swap rows can read "Swapped to {name}".
    static func events(from med: Medication) -> [LineageEvent] {
        let line = ordered(from: med)
        let anchorID = med.persistentModelID
        var result: [LineageEvent] = []
        for owner in line {
            for event in owner.changeEvents ?? [] {
                if event.eventType == MedChangeType.added.rawValue && owner.predecessor != nil {
                    continue
                }
                result.append(LineageEvent(
                    event: event,
                    owningMed: owner,
                    isAnchor: owner.persistentModelID == anchorID,
                    successorName: owner.successor?.name))
            }
        }
        return result.sorted { $0.event.timestamp > $1.event.timestamp }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/MedicationLineageTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/MedicationLineage.swift PillDaddyTests/MedicationLineageTests.swift
git commit -m "feat: MedicationLineage.events merged stream with suppression + anchor/successor context"
```

---

## Task 3: `MedicationService.addNote`

**Files:**
- Modify: `PillDaddy/Services/MedicationService.swift`
- Test: `PillDaddyTests/MedicationServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `MedicationServiceTests`:

```swift
    func testAddNoteWritesNoteEvent() throws {
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        try MedicationService.addNote(med, text: "Cardiologist confirmed dose at June visit", in: context)

        let notes = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.note.rawValue }
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.reasoning, "Cardiologist confirmed dose at June visit")
    }

    func testAddNoteWithEmptyTextThrowsAndWritesNothing() throws {
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        XCTAssertThrowsError(
            try MedicationService.addNote(med, text: "   ", in: context)
        ) { XCTAssertEqual($0 as? MedicationServiceError, .reasonRequired) }

        let notes = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.note.rawValue }
        XCTAssertEqual(notes.count, 0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/MedicationServiceTests`
Expected: FAIL to compile — "type 'MedicationService' has no member 'addNote'".

- [ ] **Step 3: Write minimal implementation**

In `PillDaddy/Services/MedicationService.swift`, add after `reactivate(...)` (before the `// MARK: - Internal helpers` section):

```swift
    /// Appends a free-form retrospective note to a medication's journal as a
    /// `note` event. Note text is required (empty/whitespace rejected).
    static func addNote(_ med: Medication, text: String, in context: ModelContext) throws {
        try requireReason(text)
        context.insert(MedicationChangeEvent(type: .note, reasoning: text, medication: med))
        try context.save()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/MedicationServiceTests`
Expected: PASS (all `MedicationServiceTests`, including the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/MedicationService.swift PillDaddyTests/MedicationServiceTests.swift
git commit -m "feat: MedicationService.addNote for retrospective journal notes"
```

---

## Task 4: `MedicationTimelineView` + `TimelineEventRow` + `AddNoteSheet`

This task is UI; verification is a clean build plus a working `#Preview`. No unit test.

**Files:**
- Create: `PillDaddy/Views/Meds/MedicationTimelineView.swift`
- Create: `PillDaddy/Views/Meds/AddNoteSheet.swift`

- [ ] **Step 1: Create the add-note sheet**

Create `PillDaddy/Views/Meds/AddNoteSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// A small commit-or-cancel sheet to append a free-form note to a medication's
/// journal. Matches the ChangeDoseSheet / LifecycleReasonSheet pattern.
struct AddNoteSheet: View {
    let medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("What happened, and why?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Add note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? MedicationService.addNote(medication, text: text, in: context)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return AddNoteSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
```

- [ ] **Step 2: Create the timeline view + row**

Create `PillDaddy/Views/Meds/MedicationTimelineView.swift`:

```swift
import SwiftUI
import SwiftData

/// The full, lineage-aware reasoning timeline for a medication: a single
/// reverse-chronological stream merging change events across the whole therapy
/// line (swap chain). Pushed from MedicationDetailView; add-note lives here.
struct MedicationTimelineView: View {
    let anchor: Medication
    @State private var showAddNote = false

    var body: some View {
        List {
            let events = MedicationLineage.events(from: anchor)
            if events.isEmpty {
                Text("No history yet").foregroundStyle(.secondary)
            } else {
                ForEach(events) { item in
                    TimelineEventRow(item: item)
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddNote = true } label: {
                    Label("Add note", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteSheet(medication: anchor)
        }
    }
}

/// One row in a lineage timeline. Reused by MedicationDetailView's preview.
struct TimelineEventRow: View {
    let item: LineageEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(MedicationLineage.title(for: item)).font(.subheadline).bold()
                if let tag = attributionTag {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Text(item.event.timestamp, format: .dateTime.month().day())
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !item.event.reasoning.isEmpty {
                Text(item.event.reasoning).font(.caption)
            }
            if !item.event.oldValue.isEmpty || !item.event.newValue.isEmpty {
                Text("\(item.event.oldValue) → \(item.event.newValue)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Drug-name tag for non-anchor rows that aren't swaps (swap titles already
    /// name the destination; anchor rows are implicitly "this med").
    private var attributionTag: String? {
        guard !item.isAnchor,
              item.event.eventType != MedChangeType.swapped.rawValue else { return nil }
        return item.owningMed.name
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return NavigationStack {
        MedicationTimelineView(anchor: PreviewSupport.firstMedication(container))
    }
    .modelContainer(container)
}
#endif
```

- [ ] **Step 3: Add the shared title helper**

The row above calls `MedicationLineage.title(for:)`. Add it inside `enum MedicationLineage` in `PillDaddy/Services/MedicationLineage.swift`:

```swift
    /// Human-readable title for a lineage event. Swaps read "Swapped to {next}".
    static func title(for item: LineageEvent) -> String {
        switch MedChangeType(rawValue: item.event.eventType) {
        case .added: return "Added"
        case .doseChanged: return "Dose changed"
        case .instructionsChanged: return "Instructions changed"
        case .swapped:
            if let name = item.successorName { return "Swapped to \(name)" }
            return "Swapped"
        case .discontinued: return "Discontinued"
        case .reactivated: return "Reactivated"
        case .note, .none: return "Note"
        }
    }
```

- [ ] **Step 4: Regenerate, build, and verify**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDS and the full existing test suite still PASSES (no test added this task; this confirms the new views compile and nothing regressed).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Views/Meds/MedicationTimelineView.swift PillDaddy/Views/Meds/AddNoteSheet.swift PillDaddy/Services/MedicationLineage.swift PillDaddy.xcodeproj
git commit -m "feat: MedicationTimelineView, TimelineEventRow, AddNoteSheet"
```

---

## Task 5: Wire the detail view entry point (lineage-aware preview + push)

**Files:**
- Modify: `PillDaddy/Views/Meds/MedicationDetailView.swift`

- [ ] **Step 1: Replace the "Why / history" section to use lineage events + a push link**

In `PillDaddy/Views/Meds/MedicationDetailView.swift`, replace the entire `Section("Why / history") { … }` block (currently lines 48–68) with:

```swift
            Section("Why / history") {
                let events = MedicationLineage.events(from: medication)
                if events.isEmpty {
                    Text("No history yet").foregroundStyle(.secondary)
                } else {
                    ForEach(events.prefix(5)) { item in
                        TimelineEventRow(item: item)
                    }
                    if events.count > 5 {
                        NavigationLink("See full history") {
                            MedicationTimelineView(anchor: medication)
                        }
                    }
                }
            }
```

- [ ] **Step 2: Remove the now-unused local `eventTitle`**

The row rendering and title now live in `TimelineEventRow` / `MedicationLineage.title(for:)`, so the private `eventTitle(_:)` method (currently lines 98–108) is dead code. Delete the entire method:

```swift
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
```

- [ ] **Step 3: Regenerate, build, and verify**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDS, full suite PASSES. (No `xcodegen generate` needed — no files added/removed.)

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Views/Meds/MedicationDetailView.swift
git commit -m "feat: lineage-aware history preview + See full history link in detail view"
```

---

## Task 6: Seed a swap chain so the timeline is dogfoodable

**Files:**
- Modify: `PillDaddy/Helpers/SeedData.swift`
- Test: `PillDaddyTests/SeedDataTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `SeedDataTests`:

```swift
    func testSeedIncludesSwapChainWithContinuousJournal() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        SeedData.seedIfEmpty(context)
        try context.save()

        let atenolol = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Atenolol" })).first)
        // Discontinued predecessor that was swapped to the active Metoprolol.
        XCTAssertFalse(atenolol.isActive)
        XCTAssertEqual(atenolol.successor?.name, "Metoprolol")

        // The merged lineage timeline (anchored on the active Metoprolol) reads
        // across both drugs and includes the swap and a free-form note.
        let metoprolol = try XCTUnwrap(atenolol.successor)
        let events = MedicationLineage.events(from: metoprolol)
        let types = Set(events.map { $0.event.eventType })
        XCTAssertTrue(types.contains(MedChangeType.swapped.rawValue))
        XCTAssertTrue(types.contains(MedChangeType.note.rawValue))
        // The swap-born Metoprolol's `added` is suppressed; the line's only
        // `added` belongs to the root, Atenolol.
        let addedOwners = events
            .filter { $0.event.eventType == MedChangeType.added.rawValue }
            .map { $0.owningMed.name }
        XCTAssertEqual(addedOwners, ["Atenolol"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/SeedDataTests`
Expected: FAIL — Atenolol not found (`XCTUnwrap` throws).

- [ ] **Step 3: Update the seed**

In `PillDaddy/Helpers/SeedData.swift`, replace the existing journal block (currently lines 46–51):

```swift
        // A bit of journal history on Metoprolol
        context.insert(MedicationChangeEvent(
            type: .added, reasoning: "Started for hypertension", medication: metoprolol))
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: "Reduced evening dose after dizziness",
            oldValue: "1 tablet", newValue: "½ tablet", medication: metoprolol))
```

with a swap chain whose journal spans both drugs:

```swift
        // Continuity chain: Atenolol was the original beta blocker, swapped out
        // for Metoprolol. The journal therefore spans both drugs so the
        // lineage timeline has a real cross-drug story to show.
        func daysAgo(_ days: Int) -> Date {
            cal.date(byAdding: .day, value: -days, to: .now) ?? .now
        }

        let atenolol = Medication(name: "Atenolol", strength: "25mg",
                                  isActive: false, discontinuedAt: daysAgo(100))
        context.insert(atenolol)
        atenolol.successor = metoprolol   // links predecessor on Metoprolol too

        context.insert(MedicationChangeEvent(
            timestamp: daysAgo(150), type: .added,
            reasoning: "Started for hypertension after the January check-up",
            medication: atenolol))
        context.insert(MedicationChangeEvent(
            timestamp: daysAgo(100), type: .swapped,
            reasoning: "Persistent cold hands; switched to a more selective blocker",
            oldValue: "Atenolol 25mg", newValue: "Metoprolol 30mg",
            medication: atenolol))
        context.insert(MedicationChangeEvent(
            timestamp: daysAgo(30), type: .doseChanged,
            reasoning: "Reduced evening dose after dizziness",
            oldValue: "1 tablet", newValue: "½ tablet", medication: metoprolol))
        context.insert(MedicationChangeEvent(
            timestamp: daysAgo(5), type: .note,
            reasoning: "Cardiologist confirmed dose at June visit — keep as is",
            medication: metoprolol))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/SeedDataTests`
Expected: PASS — all `SeedDataTests` (existing 3 + new one). The existing `testSeedPopulatesWorkedExampleRegime` still holds: Metoprolol keeps its two batch items, and there is still ≥1 change event.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Helpers/SeedData.swift PillDaddyTests/SeedDataTests.swift
git commit -m "feat: seed an Atenolol->Metoprolol swap chain with a continuous journal"
```

---

## Task 7: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Regenerate and run the entire test suite**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDS, **all** tests pass (PillDaddyTests, including `MedicationLineageTests`, `MedicationServiceTests`, `SeedDataTests`).

- [ ] **Step 2: Confirm the app builds for the app target (no test host issues)**

Run: `xcodebuild build -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDS.

- [ ] **Step 3: Final commit if anything changed during verification**

```bash
git status   # expect clean; commit only if regeneration touched the project file
```

---

## Self-review notes (for the implementer)

- **No model/schema changes** anywhere — confirm you never edited `PillDaddy/Models/` or the entitlements.
- **DRY:** title rendering lives only in `MedicationLineage.title(for:)`; row rendering only in `TimelineEventRow`. The detail view must not re-declare either.
- **The detail view preview and the full timeline use the same `MedicationLineage.events(from:)`** — so suppression and swap titles are consistent in both places.
- The "See full history" link appears only when the lineage has more than 5 events; with ≤5 the preview already shows everything.
