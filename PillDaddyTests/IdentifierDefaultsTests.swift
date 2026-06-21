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
