import Testing
import HealthKit
@testable import RoutineDosePlanner

/// Guards the Apple Health *share* authorization mapping. The blood-pressure case is the
/// regression target: the grouped "Blood Pressure" grant lands on the correlation type,
/// while the systolic/diastolic component types stay `.notDetermined` — so reading the
/// components made Settings show "Not set" even after the user enabled sharing.
@Suite struct HealthKitAuthorizationMappingTests {

    @Test func bloodPressureAuthorizationReadsTheCorrelationType() {
        #expect(LiveHealthKitWriter.authorizationTypes(for: .bloodPressure)
            == [HKCorrelationType(.bloodPressure)])
    }

    @Test func scalarKindsMapToTheirSingleQuantityType() {
        #expect(LiveHealthKitWriter.authorizationTypes(for: .weight) == [HKQuantityType(.bodyMass)])
        #expect(LiveHealthKitWriter.authorizationTypes(for: .water) == [HKQuantityType(.dietaryWater)])
        #expect(LiveHealthKitWriter.authorizationTypes(for: .pulse) == [HKQuantityType(.heartRate)])
        #expect(LiveHealthKitWriter.authorizationTypes(for: .oxygenSaturation)
            == [HKQuantityType(.oxygenSaturation)])
    }

    @Test func aggregateAuthorizedWhenAllAuthorized() {
        #expect(LiveHealthKitWriter.aggregate([.sharingAuthorized]) == .authorized)
        #expect(LiveHealthKitWriter.aggregate([.sharingAuthorized, .sharingAuthorized]) == .authorized)
    }

    @Test func aggregateDeniedWhenAnyDenied() {
        #expect(LiveHealthKitWriter.aggregate([.sharingDenied]) == .denied)
        #expect(LiveHealthKitWriter.aggregate([.sharingAuthorized, .sharingDenied]) == .denied)
    }

    @Test func aggregateNotDeterminedOtherwise() {
        #expect(LiveHealthKitWriter.aggregate([.notDetermined]) == .notDetermined)
        #expect(LiveHealthKitWriter.aggregate([.sharingAuthorized, .notDetermined]) == .notDetermined)
        #expect(LiveHealthKitWriter.aggregate([]) == .notDetermined)
    }
}
