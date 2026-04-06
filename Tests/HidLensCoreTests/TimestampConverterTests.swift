import XCTest
@testable import HidLensCore

final class TimestampConverterTests: XCTestCase {

    func testConversionProducesNonZero() {
        let converter = TimestampConverter()
        let machTime: UInt64 = 1_000_000
        let ns = converter.nanoseconds(fromMachTime: machTime)
        XCTAssert(ns > 0, "Conversion should produce non-zero nanoseconds")
    }

    func testZeroInput() {
        let converter = TimestampConverter()
        XCTAssertEqual(converter.nanoseconds(fromMachTime: 0), 0)
    }

    func testMicrosecondsConversion() {
        let converter = TimestampConverter()
        XCTAssertEqual(converter.microseconds(fromNanoseconds: 1000), 1.0, accuracy: 0.001)
        XCTAssertEqual(converter.microseconds(fromNanoseconds: 5_000_000), 5000.0, accuracy: 0.001)
    }

    func testHertzConversion() {
        let converter = TimestampConverter()
        // 1ms interval = 1000Hz
        XCTAssertEqual(converter.hertz(fromIntervalNanoseconds: 1_000_000), 1000.0, accuracy: 0.1)
        // 5ms interval = 200Hz
        XCTAssertEqual(converter.hertz(fromIntervalNanoseconds: 5_000_000), 200.0, accuracy: 0.1)
        // 0 interval = 0Hz
        XCTAssertEqual(converter.hertz(fromIntervalNanoseconds: 0), 0)
    }

    func testLargeValues() {
        // Test with large mach_absolute_time values to verify overflow safety
        let converter = TimestampConverter()
        let largeMachTime: UInt64 = UInt64.max / 200 // Large but won't overflow with safe math
        let ns = converter.nanoseconds(fromMachTime: largeMachTime)
        XCTAssert(ns > 0, "Large mach time should convert without overflow")
    }
}
