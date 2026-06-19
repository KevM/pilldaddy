# Session 0 — Foundation & Data Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a clean PillDaddy iOS project with a CloudKit-compatible SwiftData schema (Medication, Batch, BatchItem, DoseLog, MedicationChangeEvent), a stubbed tab-bar app skeleton that builds and launches, and DEBUG-only seed data — proving the schema end to end.

**Architecture:** SwiftUI app, iOS 26, XcodeGen-managed project. SwiftData `@Model` types persisted through a CloudKit-backed `ModelContainer`. Medications relate to color-coded time-based `Batch`es through a `BatchItem` join carrying per-batch quantity. Dose history is per-medication with frozen snapshot fields. A self-referential `successor`/`predecessor` link on `Medication` models swap continuity. Model logic is unit-tested against an in-memory container; CloudKit wiring is verified by launching the app.

**Tech Stack:** Swift, SwiftUI, SwiftData, CloudKit, XcodeGen, XCTest.

**Reference spec:** [`docs/superpowers/specs/2026-06-19-session-0-foundation-design.md`](../specs/2026-06-19-session-0-foundation-design.md)

---

## File Structure

**Created:**
- `PillDaddy/Models/PillModelEnums.swift` — string-backed enums (MealRelation, RecurrenceKind, DoseStatus, MedChangeType)
- `PillDaddy/Models/Medication.swift`
- `PillDaddy/Models/Batch.swift`
- `PillDaddy/Models/BatchItem.swift`
- `PillDaddy/Models/DoseLog.swift`
- `PillDaddy/Models/MedicationChangeEvent.swift`
- `PillDaddy/Models/PillDaddySchema.swift` — central schema array reused by app + tests
- `PillDaddy/Helpers/SeedData.swift` — DEBUG-gated test regime seeder
- `PillDaddy/Views/MainTabView.swift` — 5 stub tabs
- `PillDaddyTests/ModelTestSupport.swift` — in-memory container helper
- `PillDaddyTests/MedicationModelTests.swift`
- `PillDaddyTests/BatchRelationshipTests.swift`
- `PillDaddyTests/DoseLogTests.swift`
- `PillDaddyTests/MedicationChangeEventTests.swift`
- `PillDaddyTests/SeedDataTests.swift`

**Modified:**
- `project.yml` — iOS 26 target, CloudKit, test target, scheme test action
- `PillDaddy/PillDaddyApp.swift` — CloudKit ModelContainer + DEBUG seed call
- `PillDaddy/Info.plist` — add remote-notification background mode
- `PillDaddy/PillDaddy.entitlements` — add aps-environment

**Kept (salvaged):** `PillDaddy/Helpers/Color+Extension.swift`, `PillDaddy/Helpers/Theme.swift`

**Deleted (spike):** `PillDaddy/Models/Pill.swift`, `PillColor.swift`, old `DoseLog.swift`, `DoseChangeLog.swift`, `PillShape.swift`; `PillDaddy/Views/PillEditView.swift`, `PillManagerView.swift`, `RegimeView.swift`, `ReportsView.swift`, `ColorManagerView.swift`, `PillImageView.swift`, `PillShapeView.swift`, old `MainTabView.swift`; `PillDaddy/Helpers/MedicationAPIService.swift`

---

## Notes on tooling

- **Build:** `xcodegen generate` regenerates `PillDaddy.xcodeproj` from `project.yml`. Run it after any file add/delete/move (per `AGENTS.md`).
- **Simulator destination:** examples below use `platform=iOS Simulator,name=iPhone 17`. If that device is absent, list installed iOS 26 simulators with `xcrun simctl list devices available` and substitute a real name.
- **Tests run without CloudKit:** the in-memory test container omits CloudKit (CloudKit cannot back an in-memory store). CloudKit wiring is verified only by launching the app (Task 7/8).

---

### Task 1: Reset project to a minimal launching app

Delete the spike sources, replace the app entry point with a minimal one, add a stub tab view, and reconfigure the project for iOS 26 + CloudKit + a test target. End state: empty-but-launching tab-bar app.

**Files:**
- Delete: spike Models/Views/Helpers listed in File Structure above
- Create: `PillDaddy/Views/MainTabView.swift`, `PillDaddyTests/ModelTestSupport.swift`
- Modify: `PillDaddy/PillDaddyApp.swift`, `project.yml`, `PillDaddy/Info.plist`, `PillDaddy/PillDaddy.entitlements`

- [ ] **Step 1: Delete spike source files**

```bash
cd /Users/kevm/github/pilldaddy
git rm -f \
  PillDaddy/Models/Pill.swift \
  PillDaddy/Models/PillColor.swift \
  PillDaddy/Models/DoseLog.swift \
  PillDaddy/Models/DoseChangeLog.swift \
  PillDaddy/Models/PillShape.swift \
  PillDaddy/Views/PillEditView.swift \
  PillDaddy/Views/PillManagerView.swift \
  PillDaddy/Views/RegimeView.swift \
  PillDaddy/Views/ReportsView.swift \
  PillDaddy/Views/ColorManagerView.swift \
  PillDaddy/Views/PillImageView.swift \
  PillDaddy/Views/PillShapeView.swift \
  PillDaddy/Views/MainTabView.swift \
  PillDaddy/Helpers/MedicationAPIService.swift 2>/dev/null; \
  rm -f \
  PillDaddy/Models/Pill.swift PillDaddy/Models/PillColor.swift PillDaddy/Models/DoseLog.swift \
  PillDaddy/Models/DoseChangeLog.swift PillDaddy/Models/PillShape.swift \
  PillDaddy/Views/PillEditView.swift PillDaddy/Views/PillManagerView.swift \
  PillDaddy/Views/RegimeView.swift PillDaddy/Views/ReportsView.swift \
  PillDaddy/Views/ColorManagerView.swift PillDaddy/Views/PillImageView.swift \
  PillDaddy/Views/PillShapeView.swift PillDaddy/Views/MainTabView.swift \
  PillDaddy/Helpers/MedicationAPIService.swift; \
  echo "deleted"
```

(The working tree already has some of these deleted; the second `rm -f` ensures a clean state regardless.)

- [ ] **Step 2: Create the stub tab view**

Create `PillDaddy/Views/MainTabView.swift`:

```swift
import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            PlaceholderTab(title: "Today", systemImage: "checklist")
                .tabItem { Label("Today", systemImage: "checklist") }
            PlaceholderTab(title: "Meds", systemImage: "pills")
                .tabItem { Label("Meds", systemImage: "pills") }
            PlaceholderTab(title: "Reports", systemImage: "chart.bar")
                .tabItem { Label("Reports", systemImage: "chart.bar") }
            PlaceholderTab(title: "Health", systemImage: "heart")
                .tabItem { Label("Health", systemImage: "heart") }
            PlaceholderTab(title: "Settings", systemImage: "gear")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle)
            Text(title).font(.title2)
            Text("Coming soon").foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MainTabView()
}
```

- [ ] **Step 3: Replace the app entry point with a minimal version (no models yet)**

Overwrite `PillDaddy/PillDaddyApp.swift`:

```swift
import SwiftUI

@main
struct PillDaddyApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
```

- [ ] **Step 4: Add remote-notification background mode to Info.plist**

In `PillDaddy/Info.plist`, add this key inside the top-level `<dict>` (e.g. right after the `ITSAppUsesNonExemptEncryption` entry):

```xml
	<key>UIBackgroundModes</key>
	<array>
		<string>remote-notification</string>
	</array>
```

- [ ] **Step 5: Add the push entitlement**

Overwrite `PillDaddy/PillDaddy.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.pilldaddy.PillDaddy</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 6: Reconfigure project.yml for iOS 26, CloudKit, and a test target**

Overwrite `project.yml`:

```yaml
name: PillDaddy
options:
  bundleIdPrefix: com.pilldaddy
settings:
  base:
    DEVELOPMENT_TEAM: 6HQGHHRK87
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    STRING_CATALOG_GENERATE_SYMBOLS: YES
    ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: YES
targets:
  PillDaddy:
    type: application
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - PillDaddy
    info:
      path: PillDaddy/Info.plist
      properties:
        UILaunchScreen:
          StoryboardName: ""
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        ITSAppUsesNonExemptEncryption: false
        UIRequiresFullScreen: true
    settings:
      base:
        CODE_SIGN_ENTITLEMENTS: PillDaddy/PillDaddy.entitlements
  PillDaddyTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - PillDaddyTests
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: PillDaddy
schemes:
  PillDaddy:
    build:
      targets:
        PillDaddy: all
        PillDaddyTests: [test]
    run:
      debugEnabled: true
    test:
      targets:
        - PillDaddyTests
```

- [ ] **Step 7: Create the test support helper (empty container builder, used by later tasks)**

Create `PillDaddyTests/ModelTestSupport.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

enum ModelTestSupport {
    /// An in-memory ModelContainer (no CloudKit) holding the full PillDaddy schema.
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: PillDaddySchema.schema, configurations: config)
    }
}
```

> NOTE: This references `PillDaddySchema.schema`, created in Task 2. The test target will not compile until Task 2 is done; that is expected. This file is placed now so Task 1's app build can proceed (test target is built/compiled in Task 2's first test run).

- [ ] **Step 8: Regenerate the project**

```bash
cd /Users/kevm/github/pilldaddy
mkdir -p PillDaddyTests
xcodegen generate
```
Expected: "Created project at PillDaddy.xcodeproj". (`PillDaddyTests` dir must exist for xcodegen to resolve the test target sources.)

- [ ] **Step 9: Build the app target and verify it launches**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`. (Builds only the app + its deps; the test target's `ModelTestSupport.swift` is not compiled by this command.)

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Reset PillDaddy to minimal iOS 26 launching app + CloudKit/test project config"
```

---

### Task 2: Shared enums + central schema + Medication model

Add the string-backed enums, the central schema array, and the `Medication` model. First model + first test, proving the in-memory test container works.

**Files:**
- Create: `PillDaddy/Models/PillModelEnums.swift`, `PillDaddy/Models/PillDaddySchema.swift`, `PillDaddy/Models/Medication.swift`
- Test: `PillDaddyTests/MedicationModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/MedicationModelTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MedicationModelTests: XCTestCase {
    func testInsertedMedicationHasExpectedDefaults() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strength: "30mg")
        context.insert(med)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(fetched.count, 1)
        let only = try XCTUnwrap(fetched.first)
        XCTAssertEqual(only.name, "Metoprolol")
        XCTAssertEqual(only.strength, "30mg")
        XCTAssertEqual(only.form, "tablet")
        XCTAssertTrue(only.isActive)
        XCTAssertFalse(only.isPRN)
        XCTAssertEqual(only.batchItems ?? [], [])
        XCTAssertNil(only.successor)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails (compile failure — types undefined)**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: build/compile FAILS — `cannot find 'Medication'`, `cannot find 'PillDaddySchema'`.

- [ ] **Step 3: Create the shared enums**

Create `PillDaddy/Models/PillModelEnums.swift`:

```swift
import Foundation

/// Relationship of a batch to a meal. Stored on Batch as a raw String.
enum MealRelation: String, CaseIterable, Identifiable {
    case none, withFood, beforeFood, afterFood
    var id: String { rawValue }
}

/// How often a batch recurs. Stored on Batch as a raw String.
enum RecurrenceKind: String, CaseIterable, Identifiable {
    case daily, weekdays
    var id: String { rawValue }
}

/// Outcome of a scheduled (or PRN) dose. Stored on DoseLog as a raw String.
enum DoseStatus: String, CaseIterable, Identifiable {
    case taken, skipped, missed
    var id: String { rawValue }
}

/// Type of medication lifecycle event. Stored on MedicationChangeEvent as a raw String.
enum MedChangeType: String, CaseIterable, Identifiable {
    case added, doseChanged, instructionsChanged, swapped, discontinued, reactivated, note
    var id: String { rawValue }
}
```

- [ ] **Step 4: Create the Medication model**

Create `PillDaddy/Models/Medication.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Medication {
    var name: String = ""
    var strength: String = ""          // free text, e.g. "30mg"
    var form: String = "tablet"
    var generalNotes: String = ""
    var isActive: Bool = true
    var isPRN: Bool = false            // as-needed; no batch memberships
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

    init(name: String = "", strength: String = "", form: String = "tablet",
         generalNotes: String = "", isActive: Bool = true, isPRN: Bool = false,
         createdAt: Date = .now, discontinuedAt: Date? = nil) {
        self.name = name
        self.strength = strength
        self.form = form
        self.generalNotes = generalNotes
        self.isActive = isActive
        self.isPRN = isPRN
        self.createdAt = createdAt
        self.discontinuedAt = discontinuedAt
    }
}
```

- [ ] **Step 5: Create the central schema**

Create `PillDaddy/Models/PillDaddySchema.swift`:

```swift
import SwiftData

/// Single source of truth for the SwiftData schema, reused by the app container and tests.
enum PillDaddySchema {
    static let schema = Schema([
        Medication.self,
        Batch.self,
        BatchItem.self,
        DoseLog.self,
        MedicationChangeEvent.self,
    ])
}
```

> NOTE: `Batch`, `BatchItem`, `DoseLog`, and `MedicationChangeEvent` are created in Tasks 3–5. Until then this file will not compile. To keep Task 2 self-contained and green, temporarily include only the types that exist, then expand the array as each model lands. For Task 2, use:
>
> ```swift
> static let schema = Schema([Medication.self])
> ```
>
> Each later task updates this array (the task says when). Final array is the five-type version above.

Set the Task-2 version now (just `Medication.self`).

- [ ] **Step 6: Run the test to verify it passes**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `** TEST SUCCEEDED **`, `MedicationModelTests` passing.

- [ ] **Step 7: Regenerate (new files added) and commit**

```bash
xcodegen generate
git add -A
git commit -m "Add Medication model, shared enums, and central schema"
```

---

### Task 3: Batch + BatchItem models (per-batch quantity many-to-many)

Model the color-coded scheduled batch and the join carrying per-batch quantity. Test the Metoprolol worked example: same med in two batches at different quantities.

**Files:**
- Create: `PillDaddy/Models/Batch.swift`, `PillDaddy/Models/BatchItem.swift`
- Modify: `PillDaddy/Models/PillDaddySchema.swift`
- Test: `PillDaddyTests/BatchRelationshipTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/BatchRelationshipTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class BatchRelationshipTests: XCTestCase {
    func testMedicationInTwoBatchesAtDifferentQuantities() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let metoprolol = Medication(name: "Metoprolol", strength: "30mg")
        let blue = Batch(name: "Blue", colorHex: "#3B82F6")
        let green = Batch(name: "Green", colorHex: "#10B981")
        context.insert(metoprolol)
        context.insert(blue)
        context.insert(green)

        let morning = BatchItem(quantity: 1.0, medication: metoprolol, batch: blue)
        let evening = BatchItem(quantity: 0.5, medication: metoprolol, batch: green)
        context.insert(morning)
        context.insert(evening)
        try context.save()

        let fetchedMed = try XCTUnwrap(try context.fetch(FetchDescriptor<Medication>()).first)
        XCTAssertEqual(fetchedMed.batchItems?.count, 2)
        let quantities = (fetchedMed.batchItems ?? []).map(\.quantity).sorted()
        XCTAssertEqual(quantities, [0.5, 1.0])

        let fetchedBlue = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Batch>(
                predicate: #Predicate { $0.name == "Blue" })).first)
        XCTAssertEqual(fetchedBlue.items?.count, 1)
        XCTAssertEqual(fetchedBlue.items?.first?.medication?.name, "Metoprolol")
        XCTAssertEqual(fetchedBlue.items?.first?.quantity, 1.0)
    }

    func testDefaultsForBatch() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        let batch = Batch()
        context.insert(batch)
        try context.save()
        XCTAssertEqual(batch.mealRelation, MealRelation.none.rawValue)
        XCTAssertEqual(batch.recurrenceKind, RecurrenceKind.daily.rawValue)
        XCTAssertEqual(batch.items ?? [], [])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: compile FAILS — `cannot find 'Batch'`, `cannot find 'BatchItem'`.

- [ ] **Step 3: Create the Batch model**

Create `PillDaddy/Models/Batch.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Batch {
    var name: String = ""
    var colorHex: String = "#3B82F6"
    var timeOfDay: Date = Date.now          // only the clock-time component is meaningful
    var mealRelation: String = MealRelation.none.rawValue
    var recurrenceKind: String = RecurrenceKind.daily.rawValue
    var weekdays: [Int]? = nil              // 1...7 when recurrenceKind == "weekdays"
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \BatchItem.batch)
    var items: [BatchItem]? = []

    init(name: String = "", colorHex: String = "#3B82F6", timeOfDay: Date = .now,
         mealRelation: MealRelation = .none, recurrenceKind: RecurrenceKind = .daily,
         weekdays: [Int]? = nil, sortOrder: Int = 0) {
        self.name = name
        self.colorHex = colorHex
        self.timeOfDay = timeOfDay
        self.mealRelation = mealRelation.rawValue
        self.recurrenceKind = recurrenceKind.rawValue
        self.weekdays = weekdays
        self.sortOrder = sortOrder
    }
}
```

- [ ] **Step 4: Create the BatchItem model**

Create `PillDaddy/Models/BatchItem.swift`:

```swift
import Foundation
import SwiftData

@Model
final class BatchItem {
    var quantity: Double = 1.0              // fractions allowed (0.5)
    var instructionsOverride: String = ""

    var medication: Medication? = nil
    var batch: Batch? = nil

    @Relationship(deleteRule: .nullify, inverse: \DoseLog.batchItem)
    var doseLogs: [DoseLog]? = []

    init(quantity: Double = 1.0, instructionsOverride: String = "",
         medication: Medication? = nil, batch: Batch? = nil) {
        self.quantity = quantity
        self.instructionsOverride = instructionsOverride
        self.medication = medication
        self.batch = batch
    }
}
```

- [ ] **Step 5: Add the new models to the schema**

Edit `PillDaddy/Models/PillDaddySchema.swift` so the array is:

```swift
    static let schema = Schema([
        Medication.self,
        Batch.self,
        BatchItem.self,
    ])
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `** TEST SUCCEEDED **` — `BatchRelationshipTests` and `MedicationModelTests` passing.

- [ ] **Step 7: Regenerate and commit**

```bash
xcodegen generate
git add -A
git commit -m "Add Batch and BatchItem models with per-batch quantity"
```

---

### Task 4: DoseLog model (per-medication, snapshot fields, PRN)

Per-medication dose record with frozen snapshot fields and an optional batch link (nil for PRN).

**Files:**
- Create: `PillDaddy/Models/DoseLog.swift`
- Modify: `PillDaddy/Models/PillDaddySchema.swift`
- Test: `PillDaddyTests/DoseLogTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/DoseLogTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class DoseLogTests: XCTestCase {
    func testScheduledDoseLogLinksMedicationAndBatchItem() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strength: "30mg")
        let batch = Batch(name: "Blue", colorHex: "#3B82F6")
        let item = BatchItem(quantity: 1.0, medication: med, batch: batch)
        context.insert(med); context.insert(batch); context.insert(item)

        let log = DoseLog(
            scheduledDate: .now, status: .taken, quantity: 1.0,
            snapshotMedName: "Metoprolol", snapshotStrength: "30mg",
            snapshotBatchColorHex: "#3B82F6", medication: med, batchItem: item)
        context.insert(log)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<DoseLog>()).first)
        XCTAssertEqual(fetched.status, DoseStatus.taken.rawValue)
        XCTAssertEqual(fetched.snapshotMedName, "Metoprolol")
        XCTAssertEqual(fetched.medication?.name, "Metoprolol")
        XCTAssertEqual(fetched.batchItem?.quantity, 1.0)
        XCTAssertEqual(med.doseLogs?.count, 1)
    }

    func testPRNDoseLogHasNoBatchItem() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let prn = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(prn)
        let log = DoseLog(status: .taken, quantity: 2.0,
                          snapshotMedName: "Acetaminophen", medication: prn, batchItem: nil)
        context.insert(log)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<DoseLog>()).first)
        XCTAssertNil(fetched.batchItem)
        XCTAssertEqual(fetched.medication?.name, "Acetaminophen")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: compile FAILS — `cannot find 'DoseLog'`.

- [ ] **Step 3: Create the DoseLog model**

Create `PillDaddy/Models/DoseLog.swift`:

```swift
import Foundation
import SwiftData

@Model
final class DoseLog {
    var scheduledDate: Date = Date.now      // the day/slot this dose belonged to
    var takenAt: Date? = nil
    var status: String = DoseStatus.taken.rawValue
    var quantity: Double = 1.0
    var notes: String = ""

    // snapshot fields, frozen at log time
    var snapshotMedName: String = ""
    var snapshotStrength: String = ""
    var snapshotBatchColorHex: String = ""

    var medication: Medication? = nil
    var batchItem: BatchItem? = nil          // nil for PRN logs

    init(scheduledDate: Date = .now, takenAt: Date? = nil, status: DoseStatus = .taken,
         quantity: Double = 1.0, notes: String = "",
         snapshotMedName: String = "", snapshotStrength: String = "",
         snapshotBatchColorHex: String = "",
         medication: Medication? = nil, batchItem: BatchItem? = nil) {
        self.scheduledDate = scheduledDate
        self.takenAt = takenAt
        self.status = status.rawValue
        self.quantity = quantity
        self.notes = notes
        self.snapshotMedName = snapshotMedName
        self.snapshotStrength = snapshotStrength
        self.snapshotBatchColorHex = snapshotBatchColorHex
        self.medication = medication
        self.batchItem = batchItem
    }
}
```

- [ ] **Step 4: Add DoseLog to the schema**

Edit `PillDaddy/Models/PillDaddySchema.swift` so the array is:

```swift
    static let schema = Schema([
        Medication.self,
        Batch.self,
        BatchItem.self,
        DoseLog.self,
    ])
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `** TEST SUCCEEDED **` — `DoseLogTests` passing.

- [ ] **Step 6: Regenerate and commit**

```bash
xcodegen generate
git add -A
git commit -m "Add DoseLog model with snapshot fields and PRN support"
```

---

### Task 5: MedicationChangeEvent model + swap continuity link

The reasoning journal, plus a test proving the `successor`/`predecessor` swap chain.

**Files:**
- Create: `PillDaddy/Models/MedicationChangeEvent.swift`
- Modify: `PillDaddy/Models/PillDaddySchema.swift`
- Test: `PillDaddyTests/MedicationChangeEventTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/MedicationChangeEventTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MedicationChangeEventTests: XCTestCase {
    func testChangeEventAttachesToMedication() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strength: "30mg")
        context.insert(med)
        let event = MedicationChangeEvent(
            type: .doseChanged, reasoning: "Lowered for low BP",
            oldValue: "30mg", newValue: "15mg", medication: med)
        context.insert(event)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<MedicationChangeEvent>()).first)
        XCTAssertEqual(fetched.eventType, MedChangeType.doseChanged.rawValue)
        XCTAssertEqual(fetched.reasoning, "Lowered for low BP")
        XCTAssertEqual(fetched.medication?.name, "Metoprolol")
        XCTAssertEqual(med.changeEvents?.count, 1)
    }

    func testSwapLinksOldAndNewMedicationBothDirections() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let atenolol = Medication(name: "Atenolol", strength: "50mg")
        let metoprolol = Medication(name: "Metoprolol", strength: "30mg")
        context.insert(atenolol); context.insert(metoprolol)

        // perform a swap: discontinue old, link successor
        atenolol.isActive = false
        atenolol.discontinuedAt = .now
        atenolol.successor = metoprolol
        context.insert(MedicationChangeEvent(
            type: .swapped, reasoning: "Switched beta blocker for better tolerance",
            medication: atenolol))
        try context.save()

        let fetchedAtenolol = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Atenolol" })).first)
        XCTAssertFalse(fetchedAtenolol.isActive)
        XCTAssertEqual(fetchedAtenolol.successor?.name, "Metoprolol")
        XCTAssertEqual(fetchedAtenolol.successor?.predecessor?.name, "Atenolol")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: compile FAILS — `cannot find 'MedicationChangeEvent'`.

- [ ] **Step 3: Create the MedicationChangeEvent model**

Create `PillDaddy/Models/MedicationChangeEvent.swift`:

```swift
import Foundation
import SwiftData

@Model
final class MedicationChangeEvent {
    var timestamp: Date = Date.now
    var eventType: String = MedChangeType.note.rawValue
    var reasoning: String = ""              // mandatory in UX for change/swap (not a DB constraint)
    var oldValue: String = ""
    var newValue: String = ""

    var medication: Medication? = nil

    init(timestamp: Date = .now, type: MedChangeType = .note, reasoning: String = "",
         oldValue: String = "", newValue: String = "", medication: Medication? = nil) {
        self.timestamp = timestamp
        self.eventType = type.rawValue
        self.reasoning = reasoning
        self.oldValue = oldValue
        self.newValue = newValue
        self.medication = medication
    }
}
```

- [ ] **Step 4: Complete the schema (all five models)**

Edit `PillDaddy/Models/PillDaddySchema.swift` so the array is the final version:

```swift
    static let schema = Schema([
        Medication.self,
        Batch.self,
        BatchItem.self,
        DoseLog.self,
        MedicationChangeEvent.self,
    ])
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `** TEST SUCCEEDED **` — all model test classes passing.

- [ ] **Step 6: Regenerate and commit**

```bash
xcodegen generate
git add -A
git commit -m "Add MedicationChangeEvent model and swap continuity link"
```

---

### Task 6: Wire the CloudKit ModelContainer into the app

Replace the minimal app entry point with one that builds a CloudKit-backed container from the shared schema and injects it.

**Files:**
- Modify: `PillDaddy/PillDaddyApp.swift`

- [ ] **Step 1: Replace the app entry point**

Overwrite `PillDaddy/PillDaddyApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct PillDaddyApp: App {
    let container: ModelContainer

    init() {
        do {
            let config = ModelConfiguration(
                schema: PillDaddySchema.schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(for: PillDaddySchema.schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 2: Build and launch on the simulator to verify the CloudKit container initializes**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcrun simctl install booted \
  "$(xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null | awk '/ TARGET_BUILD_DIR /{d=$3} / FULL_PRODUCT_NAME /{n=$3} END{print d"/"n}')"
xcrun simctl launch booted com.pilldaddy.PillDaddy
```
Expected: `** BUILD SUCCEEDED **`, app installs and launches; `simctl launch` prints a PID and does not crash (no `fatalError`). The tab bar appears.

> If install/launch automation is flaky, the acceptable manual fallback is: open `PillDaddy.xcodeproj` in Xcode, Run on an iOS 26 simulator, and confirm the tab bar appears with no crash. The container must initialize without throwing.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Wire CloudKit-backed ModelContainer into the app"
```

---

### Task 7: DEBUG-gated seed data

Add a seeder that loads the worked-example regime into an empty store, tested against an in-memory container, then invoked at app launch under DEBUG only.

**Files:**
- Create: `PillDaddy/Helpers/SeedData.swift`
- Modify: `PillDaddy/PillDaddyApp.swift`
- Test: `PillDaddyTests/SeedDataTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/SeedDataTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class SeedDataTests: XCTestCase {
    func testSeedPopulatesWorkedExampleRegime() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        SeedData.seedIfEmpty(context)
        try context.save()

        // Metoprolol exists in two batches at 1.0 and 0.5
        let metoprolol = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Metoprolol" })).first)
        XCTAssertEqual(metoprolol.batchItems?.count, 2)
        XCTAssertEqual((metoprolol.batchItems ?? []).map(\.quantity).sorted(), [0.5, 1.0])

        // At least one PRN med
        let prnMeds = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isPRN == true }))
        XCTAssertGreaterThanOrEqual(prnMeds.count, 1)

        // At least one change-event in the history
        let events = try context.fetch(FetchDescriptor<MedicationChangeEvent>())
        XCTAssertGreaterThanOrEqual(events.count, 1)
    }

    func testSeedIsIdempotent() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        SeedData.seedIfEmpty(context)
        try context.save()
        let countAfterFirst = try context.fetch(FetchDescriptor<Medication>()).count

        SeedData.seedIfEmpty(context)   // second call must be a no-op
        try context.save()
        let countAfterSecond = try context.fetch(FetchDescriptor<Medication>()).count

        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: compile FAILS — `cannot find 'SeedData'`.

- [ ] **Step 3: Create the seeder**

Create `PillDaddy/Helpers/SeedData.swift`:

```swift
import Foundation
import SwiftData

/// Loads a realistic test regime into an empty store so later sessions can be
/// exercised without manual setup. No-op if any Medication already exists.
enum SeedData {
    @MainActor
    static func seedIfEmpty(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        guard existing.isEmpty else { return }

        let cal = Calendar.current
        func time(_ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }

        // Batches
        let blue = Batch(name: "Blue", colorHex: "#3B82F6",
                         timeOfDay: time(9, 0), mealRelation: .withFood, sortOrder: 0)
        let green = Batch(name: "Green", colorHex: "#10B981",
                          timeOfDay: time(19, 0), mealRelation: .afterFood, sortOrder: 1)
        context.insert(blue)
        context.insert(green)

        // Scheduled meds
        let metoprolol = Medication(name: "Metoprolol", strength: "30mg")
        let vitaminD = Medication(name: "Vitamin D", strength: "1000 IU", form: "capsule")
        context.insert(metoprolol)
        context.insert(vitaminD)
        context.insert(BatchItem(quantity: 1.0, medication: metoprolol, batch: blue))
        context.insert(BatchItem(quantity: 0.5, medication: metoprolol, batch: green))
        context.insert(BatchItem(quantity: 1.0, medication: vitaminD, batch: blue))

        // PRN med
        let acetaminophen = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(acetaminophen)

        // A bit of journal history on Metoprolol
        context.insert(MedicationChangeEvent(
            type: .added, reasoning: "Started for hypertension", medication: metoprolol))
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: "Reduced evening dose after dizziness",
            oldValue: "1 tablet", newValue: "½ tablet", medication: metoprolol))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `** TEST SUCCEEDED **` — `SeedDataTests` passing.

- [ ] **Step 5: Call the seeder at launch under DEBUG**

In `PillDaddy/PillDaddyApp.swift`, add the seed call inside `init()` after the container is created. Replace the `init()` body so it ends like this:

```swift
    init() {
        do {
            let config = ModelConfiguration(
                schema: PillDaddySchema.schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(for: PillDaddySchema.schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedTestData") {
            SeedData.seedIfEmpty(container.mainContext)
            try? container.mainContext.save()
        }
        #endif
    }
```

> Gating on the `-seedTestData` launch argument (set it in the Xcode scheme's Run arguments) keeps seed data opt-in, so it never lands in a real iCloud store unintentionally.

- [ ] **Step 6: Build to confirm the app still compiles with the seed call**

```bash
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Regenerate and commit**

```bash
xcodegen generate
git add -A
git commit -m "Add DEBUG-gated seed data for the test regime"
```

---

### Task 8: Final verification

Confirm the whole session's acceptance criteria in one pass.

- [ ] **Step 1: Clean build + full test run**

```bash
cd /Users/kevm/github/pilldaddy
xcodegen generate
xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `** TEST SUCCEEDED **`; all five test classes (Medication, BatchRelationship, DoseLog, MedicationChangeEvent, SeedData) pass.

- [ ] **Step 2: Launch with seed data and confirm the skeleton + schema**

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null || true
APP="$(xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null | awk '/ TARGET_BUILD_DIR /{d=$3} / FULL_PRODUCT_NAME /{n=$3} END{print d"/"n}')"
xcrun simctl install booted "$APP"
xcrun simctl launch booted --console com.pilldaddy.PillDaddy -seedTestData
```
Expected: app launches to the 5-tab bar (Today/Meds/Reports/Health/Settings), no crash, no `fatalError` in console. (Verifying seeded rows visually waits on Session 1's UI; the `SeedDataTests` already prove the seeder's correctness.)

- [ ] **Step 3: Confirm no spike files remain**

```bash
ls PillDaddy/Models PillDaddy/Views PillDaddy/Helpers
```
Expected: Models = PillModelEnums, PillDaddySchema, Medication, Batch, BatchItem, DoseLog, MedicationChangeEvent. Views = MainTabView. Helpers = Color+Extension, Theme, SeedData. No `Pill.swift`, `PillColor.swift`, `MedicationAPIService.swift`, etc.

- [ ] **Step 4: Final commit (if anything was adjusted)**

```bash
git add -A
git commit -m "Session 0 complete: foundation, schema, skeleton, seed data verified" || echo "nothing to commit"
```

---

## Self-Review

**Spec coverage (against the Session 0 design):**
- Clean project / spike discarded → Task 1 (+ verified Task 8 Step 3). ✅
- iOS 26 target, CloudKit container, entitlements, remote-notification background mode → Tasks 1 & 6. ✅
- `Medication`, `Batch`, `BatchItem`, `DoseLog`, `MedicationChangeEvent` with the exact fields/defaults from the spec → Tasks 2–5. ✅
- CloudKit rules (defaulted/optional props, optional relationships with inverses, no `.unique`, enums as raw `String`) → followed in every model; enums in Task 2. ✅
- Per-batch quantity many-to-many (Metoprolol 1.0 / 0.5) → Task 3 test. ✅
- Per-medication dose logging + snapshot fields + PRN (nil batchItem) → Task 4. ✅
- Swap continuity via `successor`/`predecessor` → Task 5 test (both directions). ✅
- `HealthMetric` deferred → intentionally absent. ✅
- Recurrence daily + weekdays → `RecurrenceKind` enum + `Batch.weekdays`. ✅
- Stubbed 5-tab skeleton → Task 1. ✅
- DEBUG-gated seed data (worked example + PRN + journal history, idempotent, never pollutes production) → Task 7. ✅
- Verification (xcodegen, clean build, launch on iOS 26) → Task 8. ✅
- "Always runnable" — app compiles/launches at every commit boundary (Tasks 1 and 6 build; 2–5 keep the app target building because models compile independently of views). ✅

**Note on the guided change flow:** the spec assigns the *UI* of the atomic guided swap to Session 1; Session 0 only proves the model supports it (Task 5's swap test). No task here builds change-flow UI — correct per scope.

**Placeholder scan:** No TBD/TODO/"handle errors"/"similar to" placeholders. The two intentional schema-evolution NOTEs (Task 1 Step 7, Task 2 Step 5) give the exact interim code to use. ✅

**Type consistency:** `PillDaddySchema.schema` used identically in app + tests. Initializer signatures match every call site: `Medication(...)`, `Batch(... mealRelation: MealRelation ...)`, `BatchItem(quantity:medication:batch:)`, `DoseLog(... status: DoseStatus ...)`, `MedicationChangeEvent(type: MedChangeType ...)`. Enum raw values (`MealRelation`, `RecurrenceKind`, `DoseStatus`, `MedChangeType`) referenced consistently. `SeedData.seedIfEmpty(_:)` signature matches its tests and the app call. ✅
