# Session 6 — Health Metrics & HealthKit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a caregiver capture Weight, Water, Blood Pressure, Pulse, and SpO₂ in a Health tab, cue each value green/yellow/red against clinical ranges, and write them one-way to Apple Health on save.

**Architecture:** One generic `HealthMetric` SwiftData model plus a `MetricRegistry` of per-metric definitions (units, plausibility, advisory cue closures, HK breadcrumbs). A pure `HealthSampleMapper` turns a metric into HealthKit objects; a `HealthKitWriting` protocol (live impl + test fake) saves them; `HealthMetricService` orchestrates persist-then-best-effort-write. Two capture surfaces (Scalar, Vitals) reached from a 3-way picker on the Health tab.

**Tech Stack:** Swift, SwiftUI, SwiftData (+CloudKit), HealthKit, XcodeGen, XCTest.

---

## Conventions (read once before starting)

- **Models:** `@Model final class` in `PillDaddy/Models/`. Every stored property has a default (CloudKit requirement). Enums persist as raw `String` and live in `PillDaddy/Models/PillModelEnums.swift`. The schema list is `PillDaddy/Models/PillDaddySchema.swift`.
- **Services:** `@MainActor enum XxxService` with `static` methods taking `in context: ModelContext`; errors are `enum XxxServiceError: Error, Equatable`. See `PillDaddy/Services/MedicationService.swift`.
- **Tests:** `@MainActor final class XxxTests: XCTestCase`, container via `ModelTestSupport.makeContainer()` (in-memory, full schema). See `PillDaddyTests/DoseLogServiceTests.swift`.
- **Views:** SwiftUI `Form`/`NavigationStack` sheets in `PillDaddy/Views/<Area>/`, each with a `#if DEBUG #Preview` using `PreviewSupport.seededContainer()`. See `PillDaddy/Views/Meds/ChangeDoseSheet.swift`.
- **After adding/removing/renaming any `.swift` file you MUST run `xcodegen generate`** (sources are folder globs) before building. Per `AGENTS.md`, the app must always build. The generated `PillDaddy.xcodeproj` is **gitignored** — never `git add` it; commit only source/test/config files.
- **Build:** `xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build`
- **Run one test class:** `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/<ClassName>`
  - The destination needs an **iOS 26** simulator; if `iPhone 16` isn't installed, run `xcrun simctl list devices available` and substitute an available iOS 26 device name.
- **Commit** locally at the end of each task (`AGENTS.md` rule 5).

---

## Task 1: HealthKit capability, usage string, and query scheme

**Files:**
- Modify: `PillDaddy/PillDaddy.entitlements`
- Modify: `project.yml` (app target `info.properties`)

- [ ] **Step 1: Add the HealthKit entitlement**

Edit `PillDaddy/PillDaddy.entitlements`, adding the HealthKit key inside the top-level `<dict>` (alongside the existing iCloud keys):

```xml
	<key>com.apple.developer.healthkit</key>
	<true/>
```

- [ ] **Step 2: Add the usage string and query scheme**

In `project.yml`, under `targets: PillDaddy: info: properties:`, add these two entries (siblings of `UIBackgroundModes`):

```yaml
        NSHealthUpdateUsageDescription: PillDaddy saves the patient's health readings to Apple Health.
        LSApplicationQueriesSchemes:
          - x-apple-health
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`. (Device-signing/HealthKit-capability errors only appear for device builds; the simulator build verifies the plist/entitlement parse.)

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/PillDaddy.entitlements project.yml
git commit -m "feat(health): add HealthKit entitlement, usage string, health query scheme"
```

---

## Task 2: MetricKind enum + HealthMetric model + schema

**Files:**
- Modify: `PillDaddy/Models/PillModelEnums.swift`
- Create: `PillDaddy/Models/HealthMetric.swift`
- Modify: `PillDaddy/Models/PillDaddySchema.swift:5-11`
- Test: `PillDaddyTests/HealthMetricModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/HealthMetricModelTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class HealthMetricModelTests: XCTestCase {
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

    func testInsertAndFetchHealthMetric() throws {
        let m = HealthMetric(kind: .bloodPressure, value: 120, secondaryValue: 80,
                             unit: "mmHg", recordedAt: .now)
        context.insert(m)
        try context.save()

        let all = try context.fetch(FetchDescriptor<HealthMetric>())
        XCTAssertEqual(all.count, 1)
        let fetched = try XCTUnwrap(all.first)
        XCTAssertEqual(fetched.metricKind, .bloodPressure)
        XCTAssertEqual(fetched.value, 120)
        XCTAssertEqual(fetched.secondaryValue, 80)
        XCTAssertFalse(fetched.healthKitSynced)
        XCTAssertNil(fetched.healthKitSampleUUID)
    }

    func testMetricKindFallsBackForUnknownRawString() throws {
        let m = HealthMetric(kind: .weight, value: 1, secondaryValue: nil, unit: "lb", recordedAt: .now)
        m.kind = "garbage"
        XCTAssertEqual(m.metricKind, .weight)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/HealthMetricModelTests`
Expected: FAIL — `HealthMetric`/`MetricKind` not found.

- [ ] **Step 3: Add the MetricKind enum**

Append to `PillDaddy/Models/PillModelEnums.swift`:

```swift
/// A health metric kind. Stored on HealthMetric as a raw String.
enum MetricKind: String, CaseIterable, Identifiable {
    case weight, water, bloodPressure, pulse, oxygenSaturation
    var id: String { rawValue }
}
```

- [ ] **Step 4: Create the HealthMetric model**

Create `PillDaddy/Models/HealthMetric.swift`:

```swift
import Foundation
import SwiftData

/// One health reading. Generic across all metric kinds; `secondaryValue` exists
/// only so Blood Pressure (120/80) is a single row. Written one-way to Apple Health.
@Model
final class HealthMetric {
    var kind: String = MetricKind.weight.rawValue   // MetricKind raw value
    var value: Double = 0                            // primary (systolic for BP)
    var secondaryValue: Double? = nil                // diastolic for BP; nil otherwise
    var unit: String = ""                            // display unit, e.g. "lb"
    var recordedAt: Date = Date.now
    var note: String = ""
    var healthKitSynced: Bool = false                // written to Apple Health yet?
    var healthKitSampleUUID: String? = nil           // traceability / dedup

    var metricKind: MetricKind { MetricKind(rawValue: kind) ?? .weight }

    init(kind: MetricKind = .weight, value: Double = 0, secondaryValue: Double? = nil,
         unit: String = "", recordedAt: Date = .now, note: String = "",
         healthKitSynced: Bool = false, healthKitSampleUUID: String? = nil) {
        self.kind = kind.rawValue
        self.value = value
        self.secondaryValue = secondaryValue
        self.unit = unit
        self.recordedAt = recordedAt
        self.note = note
        self.healthKitSynced = healthKitSynced
        self.healthKitSampleUUID = healthKitSampleUUID
    }
}
```

- [ ] **Step 5: Register it in the schema**

In `PillDaddy/Models/PillDaddySchema.swift`, add `HealthMetric.self` to the `Schema([...])` array (after `MedicationChangeEvent.self`):

```swift
    static let schema = Schema([
        Medication.self,
        Batch.self,
        BatchItem.self,
        DoseLog.self,
        MedicationChangeEvent.self,
        HealthMetric.self,
    ])
```

- [ ] **Step 6: Run it to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/HealthMetricModelTests`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add PillDaddy/Models PillDaddyTests/HealthMetricModelTests.swift
git commit -m "feat(health): add MetricKind enum and HealthMetric model"
```

---

## Task 3: MetricDefinition types, registry, and clinical cues

**Files:**
- Create: `PillDaddy/Models/MetricDefinition.swift`
- Create: `PillDaddy/Models/MetricRegistry.swift`
- Test: `PillDaddyTests/MetricRegistryTests.swift`
- Test: `PillDaddyTests/MetricCueTests.swift`

- [ ] **Step 1: Write the failing registry test**

Create `PillDaddyTests/MetricRegistryTests.swift`:

```swift
import XCTest
@testable import PillDaddy

final class MetricRegistryTests: XCTestCase {
    func testEveryKindHasACompleteDefinition() {
        for kind in MetricKind.allCases {
            let def = MetricRegistry.definition(for: kind)
            XCTAssertEqual(def.kind, kind)
            XCTAssertFalse(def.displayName.isEmpty)
            XCTAssertFalse(def.unit.isEmpty)
            XCTAssertFalse(def.healthAppBreadcrumb.isEmpty)
            XCTAssertLessThan(def.plausibleRange.lowerBound, def.plausibleRange.upperBound)
        }
    }

    func testOnlyWaterHasQuickAddAndCustomDefault() {
        XCTAssertEqual(MetricRegistry.definition(for: .water).quickAdd, [8, 12, 16])
        XCTAssertEqual(MetricRegistry.definition(for: .water).customAddDefault, 32)
        XCTAssertNil(MetricRegistry.definition(for: .weight).quickAdd)
        XCTAssertNil(MetricRegistry.definition(for: .weight).customAddDefault)
    }

    func testOnlyBloodPressureIsPaired() {
        XCTAssertEqual(MetricRegistry.definition(for: .bloodPressure).archetype, .paired)
        XCTAssertNotNil(MetricRegistry.definition(for: .bloodPressure).secondaryPlausibleRange)
        XCTAssertEqual(MetricRegistry.definition(for: .weight).archetype, .scalar)
    }
}
```

- [ ] **Step 2: Write the failing cue test**

Create `PillDaddyTests/MetricCueTests.swift`:

```swift
import XCTest
@testable import PillDaddy

final class MetricCueTests: XCTestCase {
    private func cue(_ kind: MetricKind, _ v: Double, _ s: Double? = nil,
                     _ ctx: CueContext = .empty) -> MetricCue {
        MetricRegistry.definition(for: kind).cue(v, s, ctx)
    }

    func testBloodPressureWorseOfTwoAxes() {
        XCTAssertEqual(cue(.bloodPressure, 110, 75), .normal)
        XCTAssertEqual(cue(.bloodPressure, 120, 78), .caution)   // systolic high
        XCTAssertEqual(cue(.bloodPressure, 110, 95), .caution)   // diastolic high
        XCTAssertEqual(cue(.bloodPressure, 185, 78), .alert)     // systolic crisis
        XCTAssertEqual(cue(.bloodPressure, 150, 125), .alert)    // diastolic crisis
        XCTAssertEqual(cue(.bloodPressure, 88, 58), .caution)    // both low
        XCTAssertEqual(cue(.bloodPressure, 120, 38), .alert)     // diastolic severe-low
    }

    func testPulse() {
        XCTAssertEqual(cue(.pulse, 60), .normal)
        XCTAssertEqual(cue(.pulse, 100), .normal)
        XCTAssertEqual(cue(.pulse, 50), .caution)
        XCTAssertEqual(cue(.pulse, 101), .caution)
        XCTAssertEqual(cue(.pulse, 49), .alert)
        XCTAssertEqual(cue(.pulse, 121), .alert)
    }

    func testOxygen() {
        XCTAssertEqual(cue(.oxygenSaturation, 95), .normal)
        XCTAssertEqual(cue(.oxygenSaturation, 94), .caution)
        XCTAssertEqual(cue(.oxygenSaturation, 90), .alert)
    }

    func testWaterPerEntry() {
        XCTAssertEqual(cue(.water, 32), .normal)
        XCTAssertEqual(cue(.water, 33), .caution)
        XCTAssertEqual(cue(.water, 65), .alert)
    }

    func testWaterDailyTotalWorseOf() {
        func ctx(_ total: Double) -> CueContext {
            CueContext(previousValue: nil, previousDate: nil, todayTotal: total, now: .now)
        }
        XCTAssertEqual(cue(.water, 16, nil, ctx(84)), .normal)   // total 100
        XCTAssertEqual(cue(.water, 16, nil, ctx(90)), .caution)  // total 106
        XCTAssertEqual(cue(.water, 16, nil, ctx(130)), .alert)   // total 146
        XCTAssertEqual(cue(.water, 70, nil, ctx(0)), .alert)     // per-entry alert wins
    }

    func testWeightDelta() {
        func ctx(prev: Double, daysAgo: Double) -> CueContext {
            CueContext(previousValue: prev,
                       previousDate: Date.now.addingTimeInterval(-daysAgo * 86_400),
                       todayTotal: nil, now: .now)
        }
        XCTAssertEqual(cue(.weight, 178, nil, .empty), .normal)              // no prior
        XCTAssertEqual(cue(.weight, 180, nil, ctx(prev: 178, daysAgo: 3)), .normal) // +2/3d
        XCTAssertEqual(cue(.weight, 181, nil, ctx(prev: 178, daysAgo: 5)), .caution) // +3/5d
        XCTAssertEqual(cue(.weight, 173, nil, ctx(prev: 178, daysAgo: 4)), .alert)   // -5/4d
        XCTAssertEqual(cue(.weight, 180, nil, ctx(prev: 178, daysAgo: 1)), .alert)   // +2/1d
    }
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/MetricRegistryTests -only-testing:PillDaddyTests/MetricCueTests`
Expected: FAIL — `MetricRegistry`/`MetricDefinition`/`CueContext` not found.

- [ ] **Step 4: Create the definition types**

Create `PillDaddy/Models/MetricDefinition.swift`:

```swift
import Foundation

/// Advisory severity for a reading → green / yellow / red. Never blocks saving.
enum MetricCue {
    case normal, caution, alert
    var severity: Int { self == .alert ? 2 : (self == .caution ? 1 : 0) }
    static func worst(_ a: MetricCue, _ b: MetricCue) -> MetricCue { a.severity >= b.severity ? a : b }
}

enum MetricArchetype { case scalar, paired }
enum CaptureGroup { case scalar, vitals }

/// History passed to contextual cues (weight Δ, water daily total). Absolute cues ignore it.
struct CueContext {
    let previousValue: Double?
    let previousDate: Date?
    let todayTotal: Double?
    let now: Date
    static let empty = CueContext(previousValue: nil, previousDate: nil, todayTotal: nil, now: .now)
}

/// Everything the UI and writer need for one metric kind. Held in MetricRegistry.
struct MetricDefinition {
    let kind: MetricKind
    let displayName: String
    let archetype: MetricArchetype
    let captureGroup: CaptureGroup
    let unit: String                 // display unit: "lb", "oz", "mmHg", "bpm", "%"
    let secondaryUnit: String?       // "mmHg" for BP; nil otherwise
    let plausibleRange: ClosedRange<Double>          // outside = reject save
    let secondaryPlausibleRange: ClosedRange<Double>?
    let quickAdd: [Double]?          // [8,12,16] for water; nil otherwise
    let customAddDefault: Double?    // 32 for water; nil otherwise
    let cue: (_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue
    let healthAppBreadcrumb: String  // where to find it in the Health app
}
```

- [ ] **Step 5: Create the registry**

Create `PillDaddy/Models/MetricRegistry.swift`:

```swift
import Foundation

/// The single source of per-metric facts and advisory cue thresholds.
enum MetricRegistry {
    static func definition(for kind: MetricKind) -> MetricDefinition {
        switch kind {
        case .weight:
            return MetricDefinition(
                kind: .weight, displayName: "Weight", archetype: .scalar, captureGroup: .scalar,
                unit: "lb", secondaryUnit: nil, plausibleRange: 40...660, secondaryPlausibleRange: nil,
                quickAdd: nil, customAddDefault: nil, cue: weightCue,
                healthAppBreadcrumb: "Browse › Body Measurements › Weight")
        case .water:
            return MetricDefinition(
                kind: .water, displayName: "Water", archetype: .scalar, captureGroup: .scalar,
                unit: "oz", secondaryUnit: nil, plausibleRange: 0...256, secondaryPlausibleRange: nil,
                quickAdd: [8, 12, 16], customAddDefault: 32, cue: waterCue,
                healthAppBreadcrumb: "Browse › Nutrition › Water")
        case .bloodPressure:
            return MetricDefinition(
                kind: .bloodPressure, displayName: "Blood Pressure", archetype: .paired, captureGroup: .vitals,
                unit: "mmHg", secondaryUnit: "mmHg", plausibleRange: 50...300, secondaryPlausibleRange: 20...200,
                quickAdd: nil, customAddDefault: nil, cue: bloodPressureCue,
                healthAppBreadcrumb: "Browse › Heart › Blood Pressure")
        case .pulse:
            return MetricDefinition(
                kind: .pulse, displayName: "Pulse", archetype: .scalar, captureGroup: .vitals,
                unit: "bpm", secondaryUnit: nil, plausibleRange: 20...300, secondaryPlausibleRange: nil,
                quickAdd: nil, customAddDefault: nil, cue: pulseCue,
                healthAppBreadcrumb: "Browse › Heart › Heart Rate")
        case .oxygenSaturation:
            return MetricDefinition(
                kind: .oxygenSaturation, displayName: "Oxygen (SpO₂)", archetype: .scalar, captureGroup: .vitals,
                unit: "%", secondaryUnit: nil, plausibleRange: 50...100, secondaryPlausibleRange: nil,
                quickAdd: nil, customAddDefault: nil, cue: oxygenCue,
                healthAppBreadcrumb: "Browse › Respiratory › Blood Oxygen")
        }
    }

    static var all: [MetricDefinition] { MetricKind.allCases.map(definition(for:)) }

    // MARK: - Cue logic (thresholds: see spec "Validation & clinical cues")

    private static func systolicCue(_ s: Double) -> MetricCue {
        if s < 80 || s >= 180 { return .alert }
        if s < 90 || s >= 120 { return .caution }
        return .normal
    }
    private static func diastolicCue(_ d: Double) -> MetricCue {
        if d < 40 || d >= 120 { return .alert }
        if d < 60 || d >= 80 { return .caution }
        return .normal
    }
    private static func bloodPressureCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        guard let dia = secondary else { return systolicCue(value) }
        return MetricCue.worst(systolicCue(value), diastolicCue(dia))
    }
    private static func pulseCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        if value < 50 || value > 120 { return .alert }
        if value < 60 || value > 100 { return .caution }
        return .normal
    }
    private static func oxygenCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        if value <= 90 { return .alert }
        if value < 95 { return .caution }
        return .normal
    }
    private static func waterCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        let perEntry: MetricCue = value > 64 ? .alert : (value > 32 ? .caution : .normal)
        let total = (ctx.todayTotal ?? 0) + value
        let daily: MetricCue = total > 135 ? .alert : (total > 100 ? .caution : .normal)
        return MetricCue.worst(perEntry, daily)
    }
    private static func weightCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        guard let prev = ctx.previousValue, let prevDate = ctx.previousDate else { return .normal }
        let delta = abs(value - prev)
        let days = max(0, ctx.now.timeIntervalSince(prevDate) / 86_400)
        if days <= 1 && delta >= 2 { return .alert }
        if days <= 7 && delta >= 5 { return .alert }
        if days <= 7 && delta >= 3 { return .caution }
        return .normal
    }
}
```

- [ ] **Step 6: Run them to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/MetricRegistryTests -only-testing:PillDaddyTests/MetricCueTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add PillDaddy/Models PillDaddyTests/MetricRegistryTests.swift PillDaddyTests/MetricCueTests.swift
git commit -m "feat(health): metric definition registry with advisory clinical cues"
```

---

## Task 4: MetricFormatter (localization seam)

**Files:**
- Create: `PillDaddy/Helpers/MetricFormatter.swift`
- Test: `PillDaddyTests/MetricFormatterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/MetricFormatterTests.swift`:

```swift
import XCTest
@testable import PillDaddy

final class MetricFormatterTests: XCTestCase {
    func testWholeNumbersDropDecimal() {
        XCTAssertEqual(MetricFormatter.string(176, unit: "lb"), "176 lb")
    }
    func testFractionsKeepOneDecimal() {
        XCTAssertEqual(MetricFormatter.string(97.5, unit: "%"), "97.5 %")
    }
    func testBloodPressurePair() {
        XCTAssertEqual(MetricFormatter.bloodPressure(120, 80), "120/80")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/MetricFormatterTests`
Expected: FAIL — `MetricFormatter` not found.

- [ ] **Step 3: Implement**

Create `PillDaddy/Helpers/MetricFormatter.swift`:

```swift
import Foundation

/// The single place value+unit strings are produced, so switching display units
/// (localization) is a contained change. See spec "Localization readiness".
enum MetricFormatter {
    static func string(_ value: Double, unit: String) -> String {
        let n = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(n) \(unit)"
    }

    static func bloodPressure(_ systolic: Double, _ diastolic: Double) -> String {
        "\(Int(systolic))/\(Int(diastolic))"
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/MetricFormatterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Helpers/MetricFormatter.swift PillDaddyTests/MetricFormatterTests.swift
git commit -m "feat(health): add MetricFormatter (units single seam)"
```

---

## Task 5: HealthSampleMapper (pure HealthMetric → HealthKit objects)

**Files:**
- Create: `PillDaddy/Services/HealthSampleMapper.swift`
- Test: `PillDaddyTests/HealthSampleMapperTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/HealthSampleMapperTests.swift`:

```swift
import HealthKit
import XCTest
@testable import PillDaddy

final class HealthSampleMapperTests: XCTestCase {
    func testWeightMapsToPoundsQuantity() throws {
        let sample = try XCTUnwrap(
            HealthSampleMapper.map(HealthMetric(kind: .weight, value: 180, unit: "lb")).first
            as? HKQuantitySample)
        XCTAssertEqual(sample.quantityType, HKQuantityType(.bodyMass))
        XCTAssertEqual(sample.quantity.doubleValue(for: .pound()), 180, accuracy: 0.001)
    }

    func testOxygenConvertsPercentToFraction() throws {
        let sample = try XCTUnwrap(
            HealthSampleMapper.map(HealthMetric(kind: .oxygenSaturation, value: 97, unit: "%")).first
            as? HKQuantitySample)
        XCTAssertEqual(sample.quantity.doubleValue(for: .percent()), 0.97, accuracy: 0.0001)
    }

    func testBloodPressureMapsToCorrelationOfTwoSamples() throws {
        let corr = try XCTUnwrap(
            HealthSampleMapper.map(HealthMetric(kind: .bloodPressure, value: 120, secondaryValue: 80, unit: "mmHg")).first
            as? HKCorrelation)
        XCTAssertEqual(corr.correlationType, HKCorrelationType(.bloodPressure))
        XCTAssertEqual(corr.objects.count, 2)
        let sys = try XCTUnwrap(corr.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample)
        XCTAssertEqual(sys.quantity.doubleValue(for: .millimeterOfMercury()), 120, accuracy: 0.001)
        let dia = try XCTUnwrap(corr.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample)
        XCTAssertEqual(dia.quantity.doubleValue(for: .millimeterOfMercury()), 80, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/HealthSampleMapperTests`
Expected: FAIL — `HealthSampleMapper` not found.

- [ ] **Step 3: Implement**

Create `PillDaddy/Services/HealthSampleMapper.swift`:

```swift
import Foundation
import HealthKit

/// Pure mapping from a HealthMetric to the HealthKit object(s) to save.
/// Display value → HK sample; SpO₂ converts % → fraction. No store, no auth.
enum HealthSampleMapper {
    static func map(_ metric: HealthMetric) -> [HKObject] {
        let date = metric.recordedAt
        switch metric.metricKind {
        case .weight:
            return [quantity(.bodyMass, .pound(), metric.value, date)]
        case .water:
            return [quantity(.dietaryWater, .fluidOunceUS(), metric.value, date)]
        case .pulse:
            return [quantity(.heartRate, HKUnit.count().unitDivided(by: .minute()), metric.value, date)]
        case .oxygenSaturation:
            return [quantity(.oxygenSaturation, .percent(), metric.value / 100.0, date)]
        case .bloodPressure:
            let sys = quantity(.bloodPressureSystolic, .millimeterOfMercury(), metric.value, date)
            let dia = quantity(.bloodPressureDiastolic, .millimeterOfMercury(), metric.secondaryValue ?? 0, date)
            let type = HKCorrelationType(.bloodPressure)
            return [HKCorrelation(type: type, start: date, end: date, objects: [sys, dia])]
        }
    }

    private static func quantity(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit,
                                 _ value: Double, _ date: Date) -> HKQuantitySample {
        HKQuantitySample(type: HKQuantityType(id),
                         quantity: HKQuantity(unit: unit, doubleValue: value),
                         start: date, end: date)
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/HealthSampleMapperTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/HealthSampleMapper.swift PillDaddyTests/HealthSampleMapperTests.swift
git commit -m "feat(health): pure HealthSampleMapper to HealthKit objects"
```

---

## Task 6: HealthKitWriting protocol + live writer + test fake

**Files:**
- Create: `PillDaddy/Services/HealthKitWriting.swift`
- Create: `PillDaddyTests/HealthKitTestSupport.swift`

- [ ] **Step 1: Create the protocol and live writer**

Create `PillDaddy/Services/HealthKitWriting.swift`:

```swift
import Foundation
import HealthKit

enum HealthKitWriteError: Error { case unavailable }

/// Abstraction over the real HKHealthStore so capture flows are testable with a fake.
protocol HealthKitWriting {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorizationIfNeeded() async
    func save(_ objects: [HKObject]) async throws
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

    func requestAuthorizationIfNeeded() async {
        guard isHealthDataAvailable, !didRequest else { return }
        didRequest = true
        try? await store.requestAuthorization(toShare: shareTypes, read: [])
    }

    func save(_ objects: [HKObject]) async throws {
        guard isHealthDataAvailable else { throw HealthKitWriteError.unavailable }
        try await store.save(objects)
    }
}
```

- [ ] **Step 2: Create the test fake**

Create `PillDaddyTests/HealthKitTestSupport.swift`:

```swift
import Foundation
import HealthKit
@testable import PillDaddy

/// Configurable HealthKitWriting fake for service tests.
final class FakeHealthKitWriter: HealthKitWriting {
    var isHealthDataAvailable = true
    var shouldThrow = false
    private(set) var savedBatches: [[HKObject]] = []
    private(set) var authRequested = false

    func requestAuthorizationIfNeeded() async { authRequested = true }

    func save(_ objects: [HKObject]) async throws {
        if shouldThrow { throw HealthKitWriteError.unavailable }
        savedBatches.append(objects)
    }
}
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Services/HealthKitWriting.swift PillDaddyTests/HealthKitTestSupport.swift
git commit -m "feat(health): HealthKitWriting protocol, live writer, test fake"
```

---

## Task 7: HealthMetricService (capture, delete, cue context)

**Files:**
- Create: `PillDaddy/Services/HealthMetricService.swift`
- Test: `PillDaddyTests/HealthMetricServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PillDaddyTests/HealthMetricServiceTests.swift`:

```swift
import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class HealthMetricServiceTests: XCTestCase {
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

    private func metrics() throws -> [HealthMetric] {
        try context.fetch(FetchDescriptor<HealthMetric>())
    }

    func testRecordScalarPersistsAndSyncsOnSuccess() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 180, note: "",
                                                   writer: writer, in: context)
        let m = try XCTUnwrap(try metrics().first)
        XCTAssertEqual(m.metricKind, .weight)
        XCTAssertEqual(m.unit, "lb")
        XCTAssertTrue(m.healthKitSynced)
        XCTAssertNotNil(m.healthKitSampleUUID)
        XCTAssertEqual(writer.savedBatches.count, 1)
    }

    func testFailedWriteLeavesRowUnsynced() async throws {
        writer.shouldThrow = true
        try await HealthMetricService.recordScalar(kind: .water, value: 16, note: "",
                                                   writer: writer, in: context)
        let m = try XCTUnwrap(try metrics().first)
        XCTAssertFalse(m.healthKitSynced)        // capture still succeeded
        XCTAssertNil(m.healthKitSampleUUID)
    }

    func testImplausibleScalarThrowsAndPersistsNothing() async throws {
        await XCTAssertThrowsErrorAsync(
            try await HealthMetricService.recordScalar(kind: .oxygenSaturation, value: 130,
                                                       note: "", writer: writer, in: context)
        ) { XCTAssertEqual($0 as? HealthMetricService.ServiceError, .implausible) }
        XCTAssertEqual(try metrics().count, 0)
    }

    func testRecordVitalsWritesOnlyPresentFields() async throws {
        try await HealthMetricService.recordVitals(systolic: 120, diastolic: 80, pulse: 68,
                                                   spo2: nil, note: "", writer: writer, in: context)
        let all = try metrics()
        XCTAssertEqual(all.count, 2)             // BP row + pulse row, no SpO₂
        let bp = try XCTUnwrap(all.first { $0.metricKind == .bloodPressure })
        XCTAssertEqual(bp.value, 120)
        XCTAssertEqual(bp.secondaryValue, 80)
        XCTAssertTrue(all.contains { $0.metricKind == .pulse })
        XCTAssertFalse(all.contains { $0.metricKind == .oxygenSaturation })
    }

    func testVitalsBloodPressureBothOrNeither() async throws {
        await XCTAssertThrowsErrorAsync(
            try await HealthMetricService.recordVitals(systolic: 120, diastolic: nil, pulse: nil,
                                                       spo2: nil, note: "", writer: writer, in: context)
        ) { XCTAssertEqual($0 as? HealthMetricService.ServiceError, .bloodPressureIncomplete) }
        XCTAssertEqual(try metrics().count, 0)
    }

    func testDeleteRemovesRow() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 180, note: "",
                                                   writer: writer, in: context)
        let m = try XCTUnwrap(try metrics().first)
        HealthMetricService.delete(m, in: context)
        XCTAssertEqual(try metrics().count, 0)
    }

    func testCueContextLoadsPreviousWeightAndTodayWaterTotal() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 178, note: "",
                                                   writer: writer, in: context)
        let wctx = HealthMetricService.cueContext(for: .weight, in: context)
        XCTAssertEqual(wctx.previousValue, 178)
        XCTAssertNotNil(wctx.previousDate)

        try await HealthMetricService.recordScalar(kind: .water, value: 20, note: "",
                                                   writer: writer, in: context)
        try await HealthMetricService.recordScalar(kind: .water, value: 30, note: "",
                                                   writer: writer, in: context)
        let actx = HealthMetricService.cueContext(for: .water, in: context)
        XCTAssertEqual(actx.todayTotal, 50)
    }
}

/// Async throwing assertion helper (XCTest has no built-in async variant).
func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error but none thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/HealthMetricServiceTests`
Expected: FAIL — `HealthMetricService` not found.

- [ ] **Step 3: Implement**

Create `PillDaddy/Services/HealthMetricService.swift`:

```swift
import Foundation
import SwiftData

/// Owns capture (persist-then-best-effort-write), deletion, and cue-context
/// assembly. Persist always succeeds locally; the HealthKit write is best-effort.
@MainActor
enum HealthMetricService {
    enum ServiceError: Error, Equatable { case implausible, bloodPressureIncomplete }

    static func recordScalar(kind: MetricKind, value: Double, note: String,
                             recordedAt: Date = .now,
                             writer: HealthKitWriting, in context: ModelContext) async throws {
        let def = MetricRegistry.definition(for: kind)
        guard def.plausibleRange.contains(value) else { throw ServiceError.implausible }
        let metric = HealthMetric(kind: kind, value: value, unit: def.unit,
                                  recordedAt: recordedAt, note: note)
        context.insert(metric)
        try? context.save()
        await commit(metric, writer: writer, in: context)
    }

    static func recordVitals(systolic: Double?, diastolic: Double?, pulse: Double?, spo2: Double?,
                             note: String, recordedAt: Date = .now,
                             writer: HealthKitWriting, in context: ModelContext) async throws {
        if (systolic == nil) != (diastolic == nil) { throw ServiceError.bloodPressureIncomplete }

        var rows: [HealthMetric] = []
        if let s = systolic, let d = diastolic {
            let def = MetricRegistry.definition(for: .bloodPressure)
            guard def.plausibleRange.contains(s),
                  def.secondaryPlausibleRange?.contains(d) ?? true else { throw ServiceError.implausible }
            rows.append(HealthMetric(kind: .bloodPressure, value: s, secondaryValue: d,
                                     unit: def.unit, recordedAt: recordedAt, note: note))
        }
        if let p = pulse {
            let def = MetricRegistry.definition(for: .pulse)
            guard def.plausibleRange.contains(p) else { throw ServiceError.implausible }
            rows.append(HealthMetric(kind: .pulse, value: p, unit: def.unit,
                                     recordedAt: recordedAt, note: note))
        }
        if let o = spo2 {
            let def = MetricRegistry.definition(for: .oxygenSaturation)
            guard def.plausibleRange.contains(o) else { throw ServiceError.implausible }
            rows.append(HealthMetric(kind: .oxygenSaturation, value: o, unit: def.unit,
                                     recordedAt: recordedAt, note: note))
        }

        rows.forEach { context.insert($0) }
        try? context.save()
        for row in rows { await commit(row, writer: writer, in: context) }
    }

    static func delete(_ metric: HealthMetric, in context: ModelContext) {
        context.delete(metric)
        try? context.save()
    }

    /// History for contextual cues: previous weight (weight Δ) or today's water total.
    static func cueContext(for kind: MetricKind, now: Date = .now,
                           in context: ModelContext) -> CueContext {
        switch kind {
        case .weight:
            let raw = MetricKind.weight.rawValue
            var fd = FetchDescriptor<HealthMetric>(
                predicate: #Predicate { $0.kind == raw },
                sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
            fd.fetchLimit = 1
            let prev = (try? context.fetch(fd))?.first
            return CueContext(previousValue: prev?.value, previousDate: prev?.recordedAt,
                              todayTotal: nil, now: now)
        case .water:
            let raw = MetricKind.water.rawValue
            let start = Calendar.current.startOfDay(for: now)
            let fd = FetchDescriptor<HealthMetric>(
                predicate: #Predicate { $0.kind == raw && $0.recordedAt >= start })
            let total = ((try? context.fetch(fd)) ?? []).reduce(0) { $0 + $1.value }
            return CueContext(previousValue: nil, previousDate: nil, todayTotal: total, now: now)
        default:
            return CueContext(previousValue: nil, previousDate: nil, todayTotal: nil, now: now)
        }
    }

    private static func commit(_ metric: HealthMetric, writer: HealthKitWriting,
                               in context: ModelContext) async {
        await writer.requestAuthorizationIfNeeded()
        let objects = HealthSampleMapper.map(metric)
        do {
            try await writer.save(objects)
            metric.healthKitSynced = true
            metric.healthKitSampleUUID = objects.first?.uuid.uuidString
            try? context.save()
        } catch {
            // Best-effort: leave the row unsynced (no retry in MVP).
        }
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/HealthMetricServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Services/HealthMetricService.swift PillDaddyTests/HealthMetricServiceTests.swift
git commit -m "feat(health): HealthMetricService capture, delete, cue context"
```

---

## Task 8: Cue color helper + ScalarCaptureView

**Files:**
- Create: `PillDaddy/Helpers/MetricCueStyle.swift`
- Create: `PillDaddy/Views/Health/ScalarCaptureView.swift`

- [ ] **Step 1: Create the cue→color helper**

Create `PillDaddy/Helpers/MetricCueStyle.swift`:

```swift
import SwiftUI

extension MetricCue {
    var color: Color {
        switch self {
        case .normal: .green
        case .caution: .orange
        case .alert: .red
        }
    }
}
```

- [ ] **Step 2: Create the scalar capture view**

Create `PillDaddy/Views/Health/ScalarCaptureView.swift`:

```swift
import SwiftUI
import SwiftData

/// Capture for Weight and Water. Number + live cue color; Water adds quick-add
/// chips, a custom-amount entry, and a running daily total; Weight shows Δ vs prior.
struct ScalarCaptureView: View {
    let kind: MetricKind
    let writer: HealthKitWriting

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var value: Double = 0
    @State private var customAmount: Double = 0
    @State private var note = ""
    @State private var ctx: CueContext = .empty

    private var def: MetricDefinition { MetricRegistry.definition(for: kind) }
    private var cue: MetricCue { def.cue(value, nil, ctx) }
    private var canSave: Bool { def.plausibleRange.contains(value) }

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear {
                ctx = HealthMetricService.cueContext(for: kind, in: context)
                customAmount = def.customAddDefault ?? 0
            }
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
        dismiss()
    }
}

#if DEBUG
#Preview {
    ScalarCaptureView(kind: .water, writer: LiveHealthKitWriter())
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Helpers/MetricCueStyle.swift PillDaddy/Views/Health/ScalarCaptureView.swift
git commit -m "feat(health): ScalarCaptureView with chips, custom amount, and cues"
```

---

## Task 9: VitalsCaptureView

**Files:**
- Create: `PillDaddy/Views/Health/VitalsCaptureView.swift`

- [ ] **Step 1: Create the vitals capture view**

Create `PillDaddy/Views/Health/VitalsCaptureView.swift`:

```swift
import SwiftUI
import SwiftData

/// One screen for BP + Pulse + SpO₂. Every field optional; only present values are
/// written. BP is both-or-neither. Each value carries its live cue color.
struct VitalsCaptureView: View {
    let writer: HealthKitWriting

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var systolic: Double?
    @State private var diastolic: Double?
    @State private var pulse: Double?
    @State private var spo2: Double?
    @State private var note = ""

    private var bpIncomplete: Bool { (systolic == nil) != (diastolic == nil) }
    private var hasAny: Bool { systolic != nil || diastolic != nil || pulse != nil || spo2 != nil }
    private var canSave: Bool { hasAny && !bpIncomplete }

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
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
        dismiss()
    }
}

#if DEBUG
#Preview {
    VitalsCaptureView(writer: LiveHealthKitWriter())
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
```

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add PillDaddy/Views/Health/VitalsCaptureView.swift
git commit -m "feat(health): VitalsCaptureView (BP/pulse/SpO2, optional, cued)"
```

---

## Task 10: Picker sheet + delete confirmation sheet

**Files:**
- Create: `PillDaddy/Views/Health/MetricPickerSheet.swift`
- Create: `PillDaddy/Views/Health/DeleteMetricSheet.swift`

- [ ] **Step 1: Create the 3-way picker**

Create `PillDaddy/Views/Health/MetricPickerSheet.swift`:

```swift
import SwiftUI

/// The "+" chooser: Water, Weight, or Vitals. Water/Weight route to Scalar; Vitals to Vitals.
enum MetricCaptureRoute: Identifiable {
    case scalar(MetricKind)
    case vitals
    var id: String { switch self { case .scalar(let k): k.rawValue; case .vitals: "vitals" } }
}

struct MetricPickerSheet: View {
    let onPick: (MetricCaptureRoute) -> Void
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
        }
    }

    private func row(_ title: String, _ symbol: String, _ route: MetricCaptureRoute,
                     subtitle: String? = nil) -> some View {
        Button { dismiss(); onPick(route) } label: {
            HStack {
                Image(systemName: symbol).frame(width: 28)
                VStack(alignment: .leading) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }
}
```

- [ ] **Step 2: Create the delete confirmation sheet**

Create `PillDaddy/Views/Health/DeleteMetricSheet.swift`:

```swift
import SwiftUI
import UIKit

/// Custom delete confirmation. For Apple-Health-synced rows it discloses that the
/// reading stays in Health, with an (i) expander, an Open Health action, and the
/// metric's breadcrumb. (A system alert can't host the disclosure.)
struct DeleteMetricSheet: View {
    let metric: HealthMetric
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showWhy = false

    private var def: MetricDefinition { MetricRegistry.definition(for: metric.metricKind) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "trash").font(.largeTitle).foregroundStyle(.red)
                Text("Delete this reading?").font(.headline)
                Text(def.displayName).foregroundStyle(.secondary)

                if metric.healthKitSynced {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.text.square")
                            Text("It will stay in Apple Health").font(.subheadline)
                            Spacer()
                            Button { showWhy.toggle() } label: { Image(systemName: "info.circle") }
                        }
                        if showWhy {
                            Text("PillDaddy can add readings to Apple Health but can't remove them. "
                                 + "To delete it there: \(def.healthAppBreadcrumb).")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Open Health") { openHealth() }.font(.caption)
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }

                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                    Button("Delete", role: .destructive) { dismiss(); onDelete() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .presentationDetents([.medium])
    }

    private func openHealth() {
        guard let url = URL(string: "x-apple-health://"),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Views/Health/MetricPickerSheet.swift PillDaddy/Views/Health/DeleteMetricSheet.swift
git commit -m "feat(health): metric picker and delete-disclosure sheets"
```

---

## Task 11: HealthView and tab wiring

**Files:**
- Create: `PillDaddy/Views/Health/HealthView.swift`
- Modify: `PillDaddy/Views/MainTabView.swift:15-16`

- [ ] **Step 1: Create the Health tab view**

Create `PillDaddy/Views/Health/HealthView.swift`:

```swift
import SwiftUI
import SwiftData

/// The Health tab: recent readings (unsynced rows flagged), a "+" chooser, and
/// delete with disclosure. HealthKit writes go through a single shared writer.
struct HealthView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HealthMetric.recordedAt, order: .reverse) private var metrics: [HealthMetric]

    @State private var showPicker = false
    @State private var route: MetricCaptureRoute?
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
                    Button { showPicker = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if metrics.isEmpty {
                    ContentUnavailableView("No readings yet", systemImage: "heart",
                                           description: Text("Tap + to record one."))
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            MetricPickerSheet { route = $0 }
        }
        .sheet(item: $route) { route in
            switch route {
            case .scalar(let kind): ScalarCaptureView(kind: kind, writer: writer)
            case .vitals: VitalsCaptureView(writer: writer)
            }
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

Note: `HealthMetric` must be `Identifiable` for `sheet(item:)`/`ForEach`. SwiftData `@Model` types conform to `Identifiable` automatically via `persistentModelID`; `sheet(item:)` requires `Identifiable`, which `@Model` provides. No extra work needed.

- [ ] **Step 2: Wire the Health tab**

In `PillDaddy/Views/MainTabView.swift`, replace the Health placeholder (the `PlaceholderTab(title: "Health" …)` line at tag 3) with:

```swift
            HealthView()
                .tabItem { Label("Health", systemImage: "heart") }.tag(3)
```

- [ ] **Step 3: Regenerate, build, and run**

Run: `xcodegen generate && xcodebuild -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`.

Then launch in the simulator and confirm the Health tab lists readings and the "+" picker opens both capture screens. (Manual: simulator HealthKit may prompt for authorization on first save.)

- [ ] **Step 4: Commit**

```bash
git add PillDaddy/Views/Health/HealthView.swift PillDaddy/Views/MainTabView.swift
git commit -m "feat(health): Health tab list + add/delete flows, wired into MainTabView"
```

---

## Task 12: Dev seed data for metrics

**Files:**
- Modify: `PillDaddy/Helpers/SeedData.swift` (end of `seedIfEmpty`, before the final close)
- Modify: `PillDaddyTests/SeedDataTests.swift`

- [ ] **Step 1: Write the failing test**

Add this method to `PillDaddyTests/SeedDataTests.swift` (inside the existing test class):

```swift
    func testSeedIncludesHealthMetricsAcrossKinds() throws {
        let container = try ModelTestSupport.makeContainer()
        SeedData.seedIfEmpty(container.mainContext)
        let metrics = try container.mainContext.fetch(FetchDescriptor<HealthMetric>())
        XCTAssertGreaterThanOrEqual(metrics.count, 4)
        let kinds = Set(metrics.map(\.metricKind))
        XCTAssertTrue(kinds.contains(.weight))
        XCTAssertTrue(kinds.contains(.bloodPressure))
        XCTAssertTrue(metrics.allSatisfy { !$0.healthKitSynced })   // seed never touches Health
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/SeedDataTests/testSeedIncludesHealthMetricsAcrossKinds`
Expected: FAIL — no HealthMetric rows.

- [ ] **Step 3: Add seed metrics**

In `PillDaddy/Helpers/SeedData.swift`, just before the closing brace of `seedIfEmpty`, add:

```swift
        // Health metrics — a few recent readings so the Health tab is exercisable.
        // Local-only; never written to Apple Health by the seed.
        context.insert(HealthMetric(kind: .weight, value: 178, unit: "lb", recordedAt: daysAgo(2)))
        context.insert(HealthMetric(kind: .weight, value: 182, unit: "lb", recordedAt: .now))
        context.insert(HealthMetric(kind: .water, value: 16, unit: "oz", recordedAt: .now))
        context.insert(HealthMetric(kind: .bloodPressure, value: 152, secondaryValue: 96,
                                    unit: "mmHg", recordedAt: .now))
        context.insert(HealthMetric(kind: .pulse, value: 68, unit: "bpm", recordedAt: .now))
        context.insert(HealthMetric(kind: .oxygenSaturation, value: 93, unit: "%", recordedAt: .now))
```

(`daysAgo` is already defined earlier in `seedIfEmpty`.)

- [ ] **Step 4: Run it to verify it passes**

Run: `xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PillDaddyTests/SeedDataTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PillDaddy/Helpers/SeedData.swift PillDaddyTests/SeedDataTests.swift
git commit -m "feat(health): seed sample health metrics for dev"
```

---

## Task 13: Full integration check

**Files:** none (verification only)

- [ ] **Step 1: Regenerate and run the entire test suite**

Run: `xcodegen generate && xcodebuild test -scheme PillDaddy -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `TEST SUCCEEDED` — all existing tests plus the new HealthMetric / registry / cue / formatter / mapper / service / seed tests pass.

- [ ] **Step 2: Manual smoke (dogfood state)**

Launch the app (seeded with `-seedTestData` if running via Xcode scheme args). On the Health tab:
- Tap **+** → **Water**: tap chips and the Custom amount; confirm the value and "today" total recolor green→yellow→red. Save.
- Tap **+** → **Weight**: enter a value; confirm the Δ-vs-previous line appears in the cue color. Save.
- Tap **+** → **Vitals**: enter BP only; pulse only; both; confirm BP requires both fields and values are cue-colored. Save.
- Swipe-delete a synced row → confirm the sheet shows the Apple Health disclosure with the **(i)** expander and **Open Health**; delete an unsynced row → no Health caveat.
- Confirm unsynced rows show the `icloud.slash` icon; synced rows don't.

- [ ] **Step 3: Commit (if any tweaks were needed)**

```bash
git add -A
git commit -m "chore(health): session 6 integration verified"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** generic model + registry (T2–T3), two capture surfaces + 3-way picker (T8–T11), advisory cues incl. per-axis BP / water daily-total / weight delta (T3), plausibility-vs-cue split (T3/T7), write-only mapping + best-effort write (T5–T7), authorization & write-only entitlement (T1/T6), deletion disclosure + Open Health + breadcrumb (T10), not-synced icon (T11), localization seam (T4), DEBUG seed (T12). Future-work items (deferred sync, patient-device gate, proxy app, richer water cues) are intentionally omitted.
- **Type consistency:** `MetricKind`, `MetricDefinition`, `CueContext`, `MetricCue`, `HealthKitWriting`, `HealthMetricService.ServiceError`, and `MetricCaptureRoute` are defined once and used consistently across tasks. `cueContext(for:)`, `recordScalar`, `recordVitals`, `delete`, and `HealthSampleMapper.map` signatures match their call sites in the views and tests.
- **No placeholders:** every code step contains complete, compilable code and exact commands.
