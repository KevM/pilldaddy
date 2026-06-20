# Session 7 — Health Auth Visibility, Retroactive Sync & Capture-Screen Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Health tab's add-reading flow feel like a single push instead of two stacked modals, and make Apple Health partial-permission state visible and recoverable — including retroactively syncing readings captured while permission was missing.

**Architecture:** Two independent features over the Session 6 Health stack. **Feature A** (Task 1) collapses the picker + capture sheets into one `NavigationStack` that pushes the capture screen. **Feature B** (Tasks 2–9) adds per-type share-authorization reads to the write-only `HealthKitWriting` layer, a `resyncPending` catch-up pass in `HealthMetricService`, a reusable `HealthSyncStatusView` disclosure, an inline `HealthPermissionNotice` on capture screens, a tappable Health-tab indicator, a Settings entry, and a foreground auto-sync hook.

**Tech Stack:** Swift, SwiftUI, SwiftData (+CloudKit), HealthKit, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-06-20-health-auth-sync-and-capture-nav-design.md`

---

## Conventions (read once before starting)

- **Build:** `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
- **Run one test class:** `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/<ClassName>`
  - The destination needs an **iOS 26** simulator. `iPhone 17` (iOS 26.5) is the installed device on this machine; if it's missing, run `xcrun simctl list devices available` and substitute an available iOS 26 device name.
- **After adding/removing/renaming any `.swift` file you MUST run `xcodegen generate`** before building (sources are folder globs). The generated `PillDaddy.xcodeproj` is **gitignored** — never `git add` it.
- **Services:** `@MainActor enum XxxService` with `static` methods taking `in context: ModelContext`. See `PillDaddy/Services/HealthMetricService.swift`.
- **Tests:** `@MainActor final class XxxTests: XCTestCase`, container via `ModelTestSupport.makeContainer()`. See `PillDaddyTests/HealthMetricServiceTests.swift`.
- **Views:** SwiftUI `Form`/`NavigationStack` with a `#if DEBUG #Preview` using `PreviewSupport.seededContainer()`.
- **Commit** locally at the end of each task.
- **Enums without associated values** (`HealthShareAuthorization`, `HealthAuthState`) get an explicit `: Equatable` so `XCTAssertEqual` works.

---

## File map

**Feature A (view-only; no new files, no `xcodegen`):**
- Modify `PillDaddy/Views/Health/MetricPickerSheet.swift` — `MetricCaptureRoute` becomes `Hashable`; replace `MetricPickerSheet` with `AddMetricFlow` (one `NavigationStack`, root picker, `navigationDestination`).
- Modify `PillDaddy/Views/Health/ScalarCaptureView.swift` — drop inner `NavigationStack`, add `onClose`, hide back button.
- Modify `PillDaddy/Views/Health/VitalsCaptureView.swift` — same.
- Modify `PillDaddy/Views/Health/HealthView.swift` — one `showAdd` sheet presenting `AddMetricFlow`.

**Feature B:**
- Modify `PillDaddy/Services/HealthKitWriting.swift` — `HealthShareAuthorization` enum, protocol method, live impl.
- Modify `PillDaddyTests/HealthKitTestSupport.swift` — fake gains `authorizationByKind` + method.
- Modify `PillDaddy/Services/HealthMetricService.swift` — `HealthAuthState`, `pendingCount`, `overallAuthorization`, `resyncPending`.
- Create `PillDaddyTests/HealthMetricSyncTests.swift`.
- Create `PillDaddy/Views/Health/HealthSyncStatusView.swift`.
- Create `PillDaddy/Views/Health/HealthPermissionNotice.swift`.
- Modify `PillDaddy/Views/Health/ScalarCaptureView.swift` + `VitalsCaptureView.swift` — embed notices (same files as Feature A; Task 6 follows Task 1's output).
- Modify `PillDaddy/Views/Health/HealthView.swift` — tappable `heart.slash` indicator + status sheet.
- Modify `PillDaddy/Views/Settings/SettingsView.swift` — Apple Health section.
- Modify `PillDaddy/PillDaddyApp.swift` — foreground resync.

---

## Task 1: Feature A — single-sheet navigation push

No unit tests (SwiftUI navigation); verification is build + manual smoke. All four files change together so the build stays green only at task end.

**Files:**
- Modify: `PillDaddy/Views/Health/MetricPickerSheet.swift`
- Modify: `PillDaddy/Views/Health/ScalarCaptureView.swift`
- Modify: `PillDaddy/Views/Health/VitalsCaptureView.swift`
- Modify: `PillDaddy/Views/Health/HealthView.swift`

- [ ] **Step 1: Replace `MetricPickerSheet.swift` contents**

The file keeps its name but now hosts `MetricCaptureRoute` (Hashable) and `AddMetricFlow`:

```swift
import SwiftUI

/// The "+" chooser route: Water/Weight → Scalar; Vitals → Vitals. Hashable so it
/// can drive a NavigationStack push (navigationDestination/NavigationLink).
enum MetricCaptureRoute: Hashable {
    case scalar(MetricKind)
    case vitals
}

/// The add-reading flow: one sheet whose root is the metric picker and which pushes
/// the capture screen on selection (list slides off-stage, capture slides in).
/// Selection is committal — the back button is hidden; Cancel/Save close the sheet.
struct AddMetricFlow: View {
    let writer: HealthKitWriting
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row("Water", "drop", .scalar(.water))
                row("Weight", "scalemass", .scalar(.weight))
                row("Vitals", "heart", .vitals, subtitle: "BP · pulse · SpO₂")
            }
            .navigationTitle("New reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(for: MetricCaptureRoute.self) { route in
                switch route {
                case .scalar(let kind):
                    ScalarCaptureView(kind: kind, writer: writer, onClose: { dismiss() })
                case .vitals:
                    VitalsCaptureView(writer: writer, onClose: { dismiss() })
                }
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ route: MetricCaptureRoute,
                     subtitle: String? = nil) -> some View {
        NavigationLink(value: route) {
            HStack {
                Image(systemName: symbol).frame(width: 28)
                VStack(alignment: .leading) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Replace `ScalarCaptureView.swift` contents**

Drops the inner `NavigationStack`, adds `onClose`, hides the back button, routes Cancel/Save through `onClose`, wraps the preview in a `NavigationStack`:

```swift
import SwiftUI
import SwiftData

/// Capture for Weight and Water. Pushed inside AddMetricFlow's NavigationStack, so it
/// has no NavigationStack of its own; `onClose` closes the whole sheet (its own
/// dismiss would only pop back to the picker).
struct ScalarCaptureView: View {
    let kind: MetricKind
    let writer: HealthKitWriting
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    @State private var value: Double = 0
    @State private var customAmount: Double = 0
    @State private var note = ""
    @State private var ctx: CueContext = .empty

    private var def: MetricDefinition { MetricRegistry.definition(for: kind) }
    private var cue: MetricCue { def.cue(value, nil, ctx) }
    private var canSave: Bool { def.plausibleRange.contains(value) }

    var body: some View {
        Form {
            Section {
                Text(MetricFormatter.string(value, unit: def.unit))
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(cue.color)
                if kind == .weight, let prev = ctx.previousValue {
                    Text(deltaText(from: prev)).font(.footnote).foregroundStyle(cue.color)
                }
                if kind == .water, let total = ctx.todayTotal {
                    Text("\(Int(total + value)) oz today")
                        .font(.footnote).foregroundStyle(cue.color)
                }
            }

            if let chips = def.quickAdd {
                Section("Quick add") {
                    HStack {
                        ForEach(chips, id: \.self) { amt in
                            Button("+\(Int(amt))") { value += amt }
                                .buttonStyle(.bordered)
                        }
                    }
                    if def.customAddDefault != nil {
                        HStack {
                            Image(systemName: "pencil")
                            TextField("Custom", value: $customAmount, format: .number)
                                .keyboardType(.numberPad)
                            Text(def.unit).foregroundStyle(.secondary)
                            Button("Add") { value += customAmount }.buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                Section {
                    TextField("Value", value: $value, format: .number)
                        .keyboardType(.decimalPad)
                }
            }

            Section("Note") { TextField("Add a note", text: $note, axis: .vertical) }
        }
        .navigationTitle(def.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onClose() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!canSave)
            }
        }
        .onAppear {
            ctx = HealthMetricService.cueContext(for: kind, in: context)
            customAmount = def.customAddDefault ?? 0
        }
    }

    private func deltaText(from prev: Double) -> String {
        let d = value - prev
        let arrow = d >= 0 ? "▲" : "▼"
        return "\(arrow) \(MetricFormatter.string(abs(d), unit: def.unit)) since last"
    }

    private func save() {
        let v = value, n = note
        Task {
            try? await HealthMetricService.recordScalar(kind: kind, value: v, note: n,
                                                        writer: writer, in: context)
        }
        onClose()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ScalarCaptureView(kind: .water, writer: LiveHealthKitWriter(), onClose: {})
            .modelContainer(PreviewSupport.seededContainer())
    }
}
#endif
```

- [ ] **Step 3: Replace `VitalsCaptureView.swift` contents**

```swift
import SwiftUI
import SwiftData

/// BP + Pulse + SpO₂. Pushed inside AddMetricFlow's NavigationStack; `onClose` closes
/// the whole sheet. Every field optional; BP is both-or-neither.
struct VitalsCaptureView: View {
    let writer: HealthKitWriting
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    @State private var systolic: Double?
    @State private var diastolic: Double?
    @State private var pulse: Double?
    @State private var spo2: Double?
    @State private var note = ""

    private var bpIncomplete: Bool { (systolic == nil) != (diastolic == nil) }
    private var hasAny: Bool { systolic != nil || diastolic != nil || pulse != nil || spo2 != nil }
    private var canSave: Bool { hasAny && !bpIncomplete }

    var body: some View {
        Form {
            Section("Blood pressure (mmHg)") {
                HStack {
                    numberField("Systolic", $systolic)
                    Text("/").foregroundStyle(.secondary)
                    numberField("Diastolic", $diastolic)
                }
                if let s = systolic, let d = diastolic {
                    Text(MetricFormatter.bloodPressure(s, d))
                        .foregroundStyle(MetricRegistry.definition(for: .bloodPressure).cue(s, d, .empty).color)
                }
                if bpIncomplete {
                    Text("Enter both systolic and diastolic.")
                        .font(.footnote).foregroundStyle(.red)
                }
            }
            Section("Pulse (bpm)") {
                cuedField("Pulse", $pulse, kind: .pulse)
            }
            Section("Oxygen (SpO₂ %)") {
                cuedField("SpO₂", $spo2, kind: .oxygenSaturation)
            }
            Section("Note") { TextField("Add a note", text: $note, axis: .vertical) }
        }
        .navigationTitle("Vitals")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onClose() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!canSave)
            }
        }
    }

    private func numberField(_ label: String, _ binding: Binding<Double?>) -> some View {
        TextField(label, value: binding, format: .number).keyboardType(.numberPad)
    }

    @ViewBuilder
    private func cuedField(_ label: String, _ binding: Binding<Double?>, kind: MetricKind) -> some View {
        HStack {
            numberField(label, binding)
            if let v = binding.wrappedValue {
                Circle()
                    .fill(MetricRegistry.definition(for: kind).cue(v, nil, .empty).color)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func save() {
        let s = systolic, d = diastolic, p = pulse, o = spo2, n = note
        Task {
            try? await HealthMetricService.recordVitals(systolic: s, diastolic: d, pulse: p,
                                                        spo2: o, note: n, writer: writer, in: context)
        }
        onClose()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VitalsCaptureView(writer: LiveHealthKitWriter(), onClose: {})
            .modelContainer(PreviewSupport.seededContainer())
    }
}
#endif
```

- [ ] **Step 4: Replace `HealthView.swift` contents**

Collapses the two add-sheets into one `showAdd` sheet presenting `AddMetricFlow`. (The `icloud.slash` indicator is untouched here — Task 7 makes it tappable.)

```swift
import SwiftUI
import SwiftData

/// The Health tab: recent readings (unsynced rows flagged), a "+" chooser that pushes
/// the capture screen, and delete with disclosure.
struct HealthView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HealthMetric.recordedAt, order: .reverse) private var metrics: [HealthMetric]

    @State private var showAdd = false
    @State private var pendingDelete: HealthMetric?

    private let writer: HealthKitWriting = LiveHealthKitWriter()

    var body: some View {
        NavigationStack {
            List {
                ForEach(metrics) { metric in
                    HStack {
                        Text(MetricRegistry.definition(for: metric.metricKind).displayName)
                        Spacer()
                        Text(valueText(metric)).foregroundStyle(.secondary)
                        if !metric.healthKitSynced {
                            Image(systemName: "icloud.slash")
                                .font(.caption).foregroundStyle(.tertiary)
                                .accessibilityLabel("Not synced to Apple Health")
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { pendingDelete = metric } }
                }
            }
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if metrics.isEmpty {
                    ContentUnavailableView("No readings yet", systemImage: "heart",
                                           description: Text("Tap + to record one."))
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMetricFlow(writer: writer)
        }
        .sheet(item: $pendingDelete) { metric in
            DeleteMetricSheet(metric: metric) {
                HealthMetricService.delete(metric, in: context)
            }
        }
    }

    private func valueText(_ m: HealthMetric) -> String {
        if m.metricKind == .bloodPressure, let d = m.secondaryValue {
            return MetricFormatter.bloodPressure(m.value, d) + " mmHg"
        }
        return MetricFormatter.string(m.value, unit: m.unit)
    }
}

#if DEBUG
#Preview {
    HealthView().modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Manual smoke**

Launch the app (seeded via the `-seedTestData` scheme arg). On the Health tab: tap **+** → the picker slides up; tap **Water** → the capture screen pushes in from the right (list slides off-stage left), with **no back chevron**; **Cancel** and **Save** each close the whole sheet. Repeat for **Weight** and **Vitals**.

- [ ] **Step 7: Commit**

```bash
git add PillDaddy/Views/Health/MetricPickerSheet.swift PillDaddy/Views/Health/ScalarCaptureView.swift PillDaddy/Views/Health/VitalsCaptureView.swift PillDaddy/Views/Health/HealthView.swift
git commit -m "feat(health): single-sheet navigation push for add-reading flow"
```

---

## Task 2: Feature B — per-type share authorization (writer layer)

**Files:**
- Modify: `PillDaddy/Services/HealthKitWriting.swift`
- Modify: `PillDaddyTests/HealthKitTestSupport.swift`

- [ ] **Step 1: Add the enum + protocol method + live implementation**

Replace the contents of `PillDaddy/Services/HealthKitWriting.swift` with:

```swift
import Foundation
import HealthKit

enum HealthKitWriteError: Error { case unavailable }

/// Per-metric Apple Health *share* (write) authorization. Readable because the app is
/// write-only — HealthKit only hides *read* authorization.
enum HealthShareAuthorization: Equatable { case authorized, denied, notDetermined }

/// Abstraction over the real HKHealthStore so capture flows are testable with a fake.
protocol HealthKitWriting {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorizationIfNeeded() async
    func save(_ objects: [HKObject]) async throws
    func authorizationStatus(for kind: MetricKind) -> HealthShareAuthorization
}

/// Real implementation. Write-only — we never request read access (keeps the
/// iCloud-storage exemption; see spec "App Store / TestFlight considerations").
final class LiveHealthKitWriter: HealthKitWriting {
    private let store = HKHealthStore()
    private var didRequest = false

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.bodyMass), HKQuantityType(.dietaryWater),
        HKQuantityType(.heartRate), HKQuantityType(.oxygenSaturation),
        HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic),
    ]

    private func sampleTypes(for kind: MetricKind) -> [HKSampleType] {
        switch kind {
        case .weight: return [HKQuantityType(.bodyMass)]
        case .water: return [HKQuantityType(.dietaryWater)]
        case .pulse: return [HKQuantityType(.heartRate)]
        case .oxygenSaturation: return [HKQuantityType(.oxygenSaturation)]
        case .bloodPressure:
            return [HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]
        }
    }

    func requestAuthorizationIfNeeded() async {
        guard isHealthDataAvailable, !didRequest else { return }
        didRequest = true
        try? await store.requestAuthorization(toShare: shareTypes, read: [])
    }

    func save(_ objects: [HKObject]) async throws {
        guard isHealthDataAvailable else { throw HealthKitWriteError.unavailable }
        try await store.save(objects)
    }

    /// A kind is authorized only if every underlying share type is; denied if any is.
    func authorizationStatus(for kind: MetricKind) -> HealthShareAuthorization {
        guard isHealthDataAvailable else { return .notDetermined }
        let statuses = sampleTypes(for: kind).map { store.authorizationStatus(for: $0) }
        if statuses.contains(.sharingDenied) { return .denied }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) { return .authorized }
        return .notDetermined
    }
}
```

- [ ] **Step 2: Update the test fake**

Replace the contents of `PillDaddyTests/HealthKitTestSupport.swift` with:

```swift
import Foundation
import HealthKit
@testable import PillDaddy

/// Configurable HealthKitWriting fake for service tests.
final class FakeHealthKitWriter: HealthKitWriting {
    var isHealthDataAvailable = true
    var shouldThrow = false
    /// Per-kind authorization; unset kinds default to `.authorized` so existing
    /// capture tests (which expect saves to succeed) keep passing.
    var authorizationByKind: [MetricKind: HealthShareAuthorization] = [:]
    private(set) var savedBatches: [[HKObject]] = []
    private(set) var authRequested = false

    func requestAuthorizationIfNeeded() async { authRequested = true }

    func save(_ objects: [HKObject]) async throws {
        if shouldThrow { throw HealthKitWriteError.unavailable }
        savedBatches.append(objects)
    }

    func authorizationStatus(for kind: MetricKind) -> HealthShareAuthorization {
        authorizationByKind[kind] ?? .authorized
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`. (Existing `HealthMetricServiceTests` still compile — the fake's new method defaults to `.authorized`.)

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Services/HealthKitWriting.swift PillDaddyTests/HealthKitTestSupport.swift
git commit -m "feat(health): per-metric Apple Health share authorization status"
```

---

## Task 3: Feature B — sync + status logic in HealthMetricService

**Files:**
- Modify: `PillDaddy/Services/HealthMetricService.swift`
- Test: `PillDaddyTests/HealthMetricSyncTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PillDaddyTests/HealthMetricSyncTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class HealthMetricSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var writer: FakeHealthKitWriter!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
        writer = FakeHealthKitWriter()
    }
    override func tearDown() async throws {
        writer = nil; context = nil; container = nil
        try await super.tearDown()
    }

    private func insertPending(_ kind: MetricKind, _ value: Double, secondary: Double? = nil) {
        let unit = MetricRegistry.definition(for: kind).unit
        context.insert(HealthMetric(kind: kind, value: value, secondaryValue: secondary, unit: unit))
    }

    private func allAuthorized(except denied: Set<MetricKind> = []) -> [MetricKind: HealthShareAuthorization] {
        Dictionary(uniqueKeysWithValues: MetricKind.allCases.map {
            ($0, denied.contains($0) ? .denied : .authorized)
        })
    }

    func testResyncSyncsOnlyAuthorizedKinds() async throws {
        writer.authorizationByKind = [.weight: .authorized, .bloodPressure: .denied]
        insertPending(.weight, 180)
        insertPending(.weight, 181)
        insertPending(.bloodPressure, 150, secondary: 95)
        try context.save()

        let synced = await HealthMetricService.resyncPending(writer: writer, in: context)
        XCTAssertEqual(synced, 2)

        let all = try context.fetch(FetchDescriptor<HealthMetric>())
        XCTAssertTrue(all.filter { $0.metricKind == .weight }.allSatisfy { $0.healthKitSynced })
        let bp = try XCTUnwrap(all.first { $0.metricKind == .bloodPressure })
        XCTAssertFalse(bp.healthKitSynced)
        XCTAssertEqual(writer.savedBatches.count, 2)
    }

    func testResyncIsIdempotentAndDoesNotDuplicate() async throws {
        writer.authorizationByKind = [.weight: .authorized]
        insertPending(.weight, 180)
        try context.save()

        let first = await HealthMetricService.resyncPending(writer: writer, in: context)
        XCTAssertEqual(first, 1)
        let second = await HealthMetricService.resyncPending(writer: writer, in: context)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(writer.savedBatches.count, 1)   // no duplicate save
    }

    func testPendingCount() throws {
        insertPending(.weight, 180)
        insertPending(.water, 16)
        try context.save()
        XCTAssertEqual(HealthMetricService.pendingCount(in: context), 2)
    }

    func testOverallAuthorizationStates() {
        writer.authorizationByKind = allAuthorized()
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .authorized)

        writer.authorizationByKind = Dictionary(uniqueKeysWithValues:
            MetricKind.allCases.map { ($0, .denied) })
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .denied)

        writer.authorizationByKind = Dictionary(uniqueKeysWithValues:
            MetricKind.allCases.map { ($0, .notDetermined) })
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .notDetermined)

        writer.authorizationByKind = allAuthorized(except: [.bloodPressure])
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .partial)
    }

    func testUnavailableWriterReportsUnavailable() {
        writer.isHealthDataAvailable = false
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .unavailable)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/HealthMetricSyncTests`
Expected: FAIL — `resyncPending` / `pendingCount` / `overallAuthorization` / `HealthAuthState` not found.

- [ ] **Step 3: Add the state enum and methods**

In `PillDaddy/Services/HealthMetricService.swift`, add this enum just above the `@MainActor enum HealthMetricService {` declaration (top level, after the imports):

```swift
/// Aggregate Apple Health authorization across all metric kinds.
enum HealthAuthState: Equatable { case unavailable, notDetermined, authorized, partial, denied }
```

Then add these methods inside `HealthMetricService` (after `cueContext(for:now:in:)`, before `private static func commit`):

```swift
    /// Number of locally-saved readings not yet written to Apple Health.
    static func pendingCount(in context: ModelContext) -> Int {
        let fd = FetchDescriptor<HealthMetric>(predicate: #Predicate { $0.healthKitSynced == false })
        return (try? context.fetchCount(fd)) ?? 0
    }

    /// Aggregate authorization across every kind.
    static func overallAuthorization(writer: HealthKitWriting) -> HealthAuthState {
        guard writer.isHealthDataAvailable else { return .unavailable }
        let statuses = MetricKind.allCases.map { writer.authorizationStatus(for: $0) }
        if statuses.allSatisfy({ $0 == .authorized }) { return .authorized }
        if statuses.allSatisfy({ $0 == .denied }) { return .denied }
        if statuses.allSatisfy({ $0 == .notDetermined }) { return .notDetermined }
        return .partial
    }

    /// Catch-up write of previously-unsynced rows whose kind is now authorized.
    /// Does not request authorization (no prompt side-effects) and creates no
    /// duplicates — these rows were never written. Returns the count newly synced.
    @discardableResult
    static func resyncPending(writer: HealthKitWriting, in context: ModelContext) async -> Int {
        guard writer.isHealthDataAvailable else { return 0 }
        let fd = FetchDescriptor<HealthMetric>(predicate: #Predicate { $0.healthKitSynced == false })
        let pending = (try? context.fetch(fd)) ?? []
        var synced = 0
        for row in pending where writer.authorizationStatus(for: row.metricKind) == .authorized {
            let objects = HealthSampleMapper.map(row)
            do {
                try await writer.save(objects)
                row.healthKitSynced = true
                row.healthKitSampleUUID = objects.first?.uuid.uuidString
                synced += 1
            } catch {
                // Leave it pending; a later foreground or manual sync can retry.
            }
        }
        if synced > 0 { try? context.save() }
        return synced
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PillDaddyTests/HealthMetricSyncTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/HealthMetricService.swift PillDaddyTests/HealthMetricSyncTests.swift
git commit -m "feat(health): pendingCount, overallAuthorization, resyncPending"
```

---

## Task 4: Feature B — HealthSyncStatusView (reusable disclosure)

**Files:**
- Create: `PillDaddy/Views/Health/HealthSyncStatusView.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI
import SwiftData
import UIKit

/// Reusable Apple Health authorization + sync disclosure. Pushed from Settings and
/// presented as a sheet from the Health tab's per-row indicator.
struct HealthSyncStatusView: View {
    let writer: HealthKitWriting

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var pending = 0
    @State private var syncMessage: String?
    @State private var isSyncing = false

    private var overall: HealthAuthState { HealthMetricService.overallAuthorization(writer: writer) }

    var body: some View {
        Form {
            Section { headerRow }

            if overall != .unavailable {
                Section("Metrics") {
                    ForEach(MetricKind.allCases) { kind in metricRow(kind) }
                }

                Section {
                    if pending > 0 {
                        Text("\(pending) reading\(pending == 1 ? "" : "s") waiting to sync to Apple Health")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await sync() }
                    } label: {
                        if isSyncing { ProgressView() } else { Text("Sync to Health") }
                    }
                    .disabled(pending == 0 || isSyncing)
                    if let syncMessage {
                        Text(syncMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Open iOS Settings") { openSettings() }
                }
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pending = HealthMetricService.pendingCount(in: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pending = HealthMetricService.pendingCount(in: context) }
        }
    }

    @ViewBuilder private var headerRow: some View {
        switch overall {
        case .authorized:
            Label("Full access", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .partial:
            Label("Partial access", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .denied:
            Label("Not enabled", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .notDetermined:
            Label("Not set up yet", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        case .unavailable:
            Label("Apple Health unavailable on this device", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func metricRow(_ kind: MetricKind) -> some View {
        let status = writer.authorizationStatus(for: kind)
        return HStack {
            Text(MetricRegistry.definition(for: kind).displayName)
            Spacer()
            Text(statusText(status)).font(.subheadline).foregroundStyle(statusColor(status))
        }
    }

    private func statusText(_ s: HealthShareAuthorization) -> String {
        switch s {
        case .authorized: "Sharing"
        case .denied: "Not shared"
        case .notDetermined: "Not set"
        }
    }

    private func statusColor(_ s: HealthShareAuthorization) -> Color {
        switch s {
        case .authorized: .green
        case .denied: .orange
        case .notDetermined: .secondary
        }
    }

    @MainActor private func sync() async {
        isSyncing = true
        let n = await HealthMetricService.resyncPending(writer: writer, in: context)
        pending = HealthMetricService.pendingCount(in: context)
        syncMessage = n > 0 ? "Synced \(n) reading\(n == 1 ? "" : "s")" : "Nothing to sync"
        isSyncing = false
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        HealthSyncStatusView(writer: LiveHealthKitWriter())
            .modelContainer(PreviewSupport.seededContainer())
    }
}
#endif
```

Note: `statusColor` returns `Color`, and `.secondary` resolves to `Color.secondary` here — valid.

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Health/HealthSyncStatusView.swift
git commit -m "feat(health): reusable HealthSyncStatusView disclosure"
```

---

## Task 5: Feature B — HealthPermissionNotice (capture-screen inline notice)

**Files:**
- Create: `PillDaddy/Views/Health/HealthPermissionNotice.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI
import UIKit

/// Compact inline notice shown on a capture screen when the metric being entered isn't
/// authorized to write to Apple Health. Renders nothing when authorized or unavailable.
/// Refreshes when the app returns to the foreground (e.g. after the user grants access).
struct HealthPermissionNotice: View {
    let kind: MetricKind
    let writer: HealthKitWriting

    @Environment(\.scenePhase) private var scenePhase
    @State private var status: HealthShareAuthorization = .authorized   // default avoids a flash
    @State private var showDetails = false

    var body: some View {
        Group {
            if writer.isHealthDataAvailable && status != .authorized {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(MetricRegistry.definition(for: kind).displayName) won't be saved to Apple Health",
                          systemImage: "heart.slash")
                        .font(.footnote).foregroundStyle(.orange)
                    HStack {
                        Button("Open Settings") { openSettings() }.font(.footnote)
                        Spacer()
                        Button("Details") { showDetails = true }.font(.footnote)
                    }
                }
            }
        }
        .onAppear { status = writer.authorizationStatus(for: kind) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { status = writer.authorizationStatus(for: kind) }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack { HealthSyncStatusView(writer: writer) }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Health/HealthPermissionNotice.swift
git commit -m "feat(health): inline HealthPermissionNotice for capture screens"
```

---

## Task 6: Feature B — embed the notice in the capture screens

Builds on Task 1's view code.

**Files:**
- Modify: `PillDaddy/Views/Health/ScalarCaptureView.swift`
- Modify: `PillDaddy/Views/Health/VitalsCaptureView.swift`

- [ ] **Step 1: Add the notice to `ScalarCaptureView`**

In the first `Section` (the value display), add the notice as the last element. Change:

```swift
                if kind == .water, let total = ctx.todayTotal {
                    Text("\(Int(total + value)) oz today")
                        .font(.footnote).foregroundStyle(cue.color)
                }
            }
```

to:

```swift
                if kind == .water, let total = ctx.todayTotal {
                    Text("\(Int(total + value)) oz today")
                        .font(.footnote).foregroundStyle(cue.color)
                }
                HealthPermissionNotice(kind: kind, writer: writer)
            }
```

- [ ] **Step 2: Add per-field notices to `VitalsCaptureView`**

Add a `HealthPermissionNotice` at the end of each metric section. Change the three sections:

```swift
            Section("Blood pressure (mmHg)") {
                HStack {
                    numberField("Systolic", $systolic)
                    Text("/").foregroundStyle(.secondary)
                    numberField("Diastolic", $diastolic)
                }
                if let s = systolic, let d = diastolic {
                    Text(MetricFormatter.bloodPressure(s, d))
                        .foregroundStyle(MetricRegistry.definition(for: .bloodPressure).cue(s, d, .empty).color)
                }
                if bpIncomplete {
                    Text("Enter both systolic and diastolic.")
                        .font(.footnote).foregroundStyle(.red)
                }
                HealthPermissionNotice(kind: .bloodPressure, writer: writer)
            }
            Section("Pulse (bpm)") {
                cuedField("Pulse", $pulse, kind: .pulse)
                HealthPermissionNotice(kind: .pulse, writer: writer)
            }
            Section("Oxygen (SpO₂ %)") {
                cuedField("SpO₂", $spo2, kind: .oxygenSaturation)
                HealthPermissionNotice(kind: .oxygenSaturation, writer: writer)
            }
```

- [ ] **Step 2b: Build**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`. (No `xcodegen` — no files added.)

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Health/ScalarCaptureView.swift PillDaddy/Views/Health/VitalsCaptureView.swift
git commit -m "feat(health): show permission notice on capture screens when unauthorized"
```

---

## Task 7: Feature B — tappable Health-tab indicator

**Files:**
- Modify: `PillDaddy/Views/Health/HealthView.swift`

- [ ] **Step 1: Add a state property for the status sheet**

In `HealthView`, below `@State private var pendingDelete: HealthMetric?`, add:

```swift
    @State private var showSyncStatus = false
```

- [ ] **Step 2: Make the indicator a tappable `heart.slash`**

Replace:

```swift
                        if !metric.healthKitSynced {
                            Image(systemName: "icloud.slash")
                                .font(.caption).foregroundStyle(.tertiary)
                                .accessibilityLabel("Not synced to Apple Health")
                        }
```

with:

```swift
                        if !metric.healthKitSynced {
                            Button {
                                showSyncStatus = true
                            } label: {
                                Image(systemName: "heart.slash")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Not in Apple Health — tap for options")
                        }
```

- [ ] **Step 3: Present the status sheet**

After the existing `.sheet(item: $pendingDelete) { ... }` block, add:

```swift
        .sheet(isPresented: $showSyncStatus) {
            NavigationStack { HealthSyncStatusView(writer: writer) }
        }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Views/Health/HealthView.swift
git commit -m "feat(health): tappable heart.slash indicator opens sync status"
```

---

## Task 8: Feature B — Settings "Apple Health" section

**Files:**
- Modify: `PillDaddy/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Add a writer property**

In `SettingsView`, below `@State private var authStatus: UNAuthorizationStatus = .notDetermined`, add:

```swift
    private let healthWriter: HealthKitWriting = LiveHealthKitWriter()
```

- [ ] **Step 2: Add the section**

In the `Form`, after the `Section(header: Text("Notifications")) { permissionRow }` section, add:

```swift
                Section(header: Text("Apple Health")) {
                    NavigationLink {
                        HealthSyncStatusView(writer: healthWriter)
                    } label: {
                        Label("Apple Health", systemImage: "heart")
                    }
                }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Views/Settings/SettingsView.swift
git commit -m "feat(health): Apple Health status entry in Settings"
```

---

## Task 9: Feature B — foreground auto catch-up sync

**Files:**
- Modify: `PillDaddy/PillDaddyApp.swift`

- [ ] **Step 1: Add a shared health writer**

In `struct PillDaddyApp`, below `private let settings = ReminderSettings()`, add:

```swift
    private let healthWriter: HealthKitWriting = LiveHealthKitWriter()
```

- [ ] **Step 2: Call the sync on foreground**

Replace:

```swift
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { syncReminders() }
                }
```

with:

```swift
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        syncReminders()
                        Task { await syncHealthMetrics() }
                    }
                }
```

- [ ] **Step 3: Add the method**

After the `syncReminders()` method, add:

```swift
    @MainActor
    private func syncHealthMetrics() async {
        await HealthMetricService.resyncPending(writer: healthWriter, in: container.mainContext)
    }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/PillDaddyApp.swift
git commit -m "feat(health): retroactively sync pending readings on foreground"
```

---

## Task 10: Full integration check

**Files:** none (verification only)

- [ ] **Step 1: Regenerate and run the entire test suite**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: `TEST SUCCEEDED` — all prior tests plus `HealthMetricSyncTests` pass.

- [ ] **Step 2: Manual smoke (on a device or simulator with HealthKit)**

- **Capture nav (Feature A):** + → pick a metric → capture screen pushes in, no back chevron, Cancel/Save both close the sheet.
- **Partial permission (Feature B):** On first save, grant only *some* metrics in the HealthKit sheet. Confirm:
  - capture screens for *denied* metrics show the inline "won't be saved to Apple Health" notice with **Open Settings** + **Details**;
  - denied rows show the orange **heart.slash**; tapping it opens the status sheet listing per-metric status, a pending count, **Sync to Health**, and **Open iOS Settings**;
  - **Settings → Apple Health** shows the same disclosure.
- **Retroactive sync:** From the status sheet, tap **Open iOS Settings**, enable a previously-denied metric, return to the app. Confirm the matching rows lose their **heart.slash** (synced on foreground), and that **Sync to Health** reports "Nothing to sync" afterward.

- [ ] **Step 3: Commit (if any tweaks were needed)**

```bash
git add -A
git commit -m "chore(health): session 7 integration verified"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** Feature A nav push (T1); per-type authorization read (T2, spec §1); pendingCount/overallAuthorization/resyncPending (T3, spec §2); `HealthSyncStatusView` (T4, spec §3); `HealthPermissionNotice` + capture-screen wiring (T5–T6, spec §7); tappable `heart.slash` indicator (T7, spec §4); Settings entry (T8, spec §5); foreground auto-sync (T9, spec §6); integration (T10). Out-of-scope items (background sync, Health deletion, per-row retry, Health-tab banner) intentionally omitted.
- **Type consistency:** `HealthShareAuthorization` (T2) and `HealthAuthState` (T3) are defined once and consumed consistently; `authorizationStatus(for:)`, `resyncPending(writer:in:)`, `overallAuthorization(writer:)`, `pendingCount(in:)`, and `ScalarCaptureView(kind:writer:onClose:)` / `VitalsCaptureView(writer:onClose:)` signatures match every call site (`AddMetricFlow`, `HealthSyncStatusView`, `HealthPermissionNotice`, `SettingsView`, `PillDaddyApp`).
- **No placeholders:** every code step contains complete, compilable code and exact commands.
- **Build-green ordering:** T1 changes all four nav files together; T2 updates protocol + fake together; T4/T5 precede their consumers (T6–T8); T3 precedes T4.
