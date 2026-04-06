import XCTest
@testable import HidLensCore

final class StatisticsCalculatorTests: XCTestCase {

    func testEmptySamples() {
        let stats = StatisticsCalculator.compute(from: [])
        XCTAssertEqual(stats.sampleCount, 0)
        XCTAssertEqual(stats.averageHz, 0)
    }

    func testSingleSample() {
        let samples = [MeasurementSample(timestampNanoseconds: 1_000_000, intervalNanoseconds: nil)]
        let stats = StatisticsCalculator.compute(from: samples)
        // Single sample has no intervals, so returns empty stats
        XCTAssertEqual(stats.sampleCount, 0)
        XCTAssertEqual(stats.averageHz, 0)
    }

    func testConstant1000Hz() {
        // 1000Hz = 1ms = 1_000_000 ns intervals
        let intervalNs: UInt64 = 1_000_000
        var samples: [MeasurementSample] = []
        for i in 0..<100 {
            let ts = UInt64(i) * intervalNs
            let interval: UInt64? = i == 0 ? nil : intervalNs
            samples.append(MeasurementSample(timestampNanoseconds: ts, intervalNanoseconds: interval))
        }

        let stats = StatisticsCalculator.compute(from: samples)

        XCTAssertEqual(stats.sampleCount, 100)
        XCTAssertEqual(stats.averageHz, 1000.0, accuracy: 1.0)
        XCTAssertEqual(stats.effectivePollingRateHz, 1000.0, accuracy: 1.0)
        XCTAssertEqual(stats.jitterStdDevMicroseconds, 0, accuracy: 0.001)
        XCTAssertEqual(stats.p50Microseconds, 1000.0, accuracy: 0.1)
        XCTAssertEqual(stats.minIntervalMicroseconds, 1000.0, accuracy: 0.1)
        XCTAssertEqual(stats.maxIntervalMicroseconds, 1000.0, accuracy: 0.1)
    }

    func testConstant200Hz() {
        // 200Hz = 5ms = 5_000_000 ns (DualShock 4 default)
        let intervalNs: UInt64 = 5_000_000
        var samples: [MeasurementSample] = []
        for i in 0..<50 {
            let ts = UInt64(i) * intervalNs
            let interval: UInt64? = i == 0 ? nil : intervalNs
            samples.append(MeasurementSample(timestampNanoseconds: ts, intervalNanoseconds: interval))
        }

        let stats = StatisticsCalculator.compute(from: samples)

        XCTAssertEqual(stats.averageHz, 200.0, accuracy: 1.0)
        XCTAssertEqual(stats.p50Microseconds, 5000.0, accuracy: 0.1)
    }

    func testJitter() {
        // Alternating 900μs and 1100μs intervals (avg 1000μs = 1000Hz but with jitter)
        var samples: [MeasurementSample] = []
        var ts: UInt64 = 0
        samples.append(MeasurementSample(timestampNanoseconds: ts, intervalNanoseconds: nil))

        for i in 1..<100 {
            let intervalNs: UInt64 = i % 2 == 0 ? 900_000 : 1_100_000
            ts += intervalNs
            samples.append(MeasurementSample(timestampNanoseconds: ts, intervalNanoseconds: intervalNs))
        }

        let stats = StatisticsCalculator.compute(from: samples)

        XCTAssertEqual(stats.averageHz, 1000.0, accuracy: 10.0)
        XCTAssert(stats.jitterStdDevMicroseconds > 90.0, "Jitter should be significant")
        XCTAssertEqual(stats.minIntervalMicroseconds, 900.0, accuracy: 0.1)
        XCTAssertEqual(stats.maxIntervalMicroseconds, 1100.0, accuracy: 0.1)
    }

    func testDuration() {
        // 10 samples at 1ms intervals = ~9ms duration
        let intervalNs: UInt64 = 1_000_000
        var samples: [MeasurementSample] = []
        for i in 0..<10 {
            let ts = UInt64(i) * intervalNs
            let interval: UInt64? = i == 0 ? nil : intervalNs
            samples.append(MeasurementSample(timestampNanoseconds: ts, intervalNanoseconds: interval))
        }

        let stats = StatisticsCalculator.compute(from: samples)

        XCTAssertEqual(stats.durationSeconds, 0.009, accuracy: 0.001)
    }

    func testPercentiles() {
        // 100 samples with linearly increasing intervals (1ms to 100ms)
        var samples: [MeasurementSample] = []
        var ts: UInt64 = 0
        samples.append(MeasurementSample(timestampNanoseconds: ts, intervalNanoseconds: nil))

        for i in 1...100 {
            let intervalNs = UInt64(i) * 1_000_000 // 1ms, 2ms, ..., 100ms
            ts += intervalNs
            samples.append(MeasurementSample(timestampNanoseconds: ts, intervalNanoseconds: intervalNs))
        }

        let stats = StatisticsCalculator.compute(from: samples)

        // p50 should be around 50ms = 50000μs
        XCTAssertEqual(stats.p50Microseconds, 50_000, accuracy: 2000)
        // p95 should be around 95ms
        XCTAssertEqual(stats.p95Microseconds, 95_000, accuracy: 2000)
        // p99 should be around 99ms
        XCTAssertEqual(stats.p99Microseconds, 99_000, accuracy: 2000)
    }
}
