import Testing
@testable import RoutineDosePlanner

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

    @Test func acceptsZeroIfAllowed() {
        #expect(DoseQuantityParsing.value(from: "0", allowZero: true) == 0.0)
    }
}
