import Foundation

public enum StatisticsCalculator {

    public static func compute(from samples: [MeasurementSample]) -> MeasurementStatistics {
        let intervals = samples.compactMap { $0.intervalNanoseconds }
        guard !intervals.isEmpty else { return .empty }

        let count = intervals.count
        let sorted = intervals.sorted()

        let durationNs: UInt64
        if let first = samples.first?.timestampNanoseconds,
           let last = samples.last?.timestampNanoseconds {
            durationNs = last - first
        } else {
            durationNs = 0
        }
        let durationSeconds = Double(durationNs) / 1_000_000_000.0

        let sumNs = intervals.reduce(UInt64(0), +)
        let avgIntervalNs = Double(sumNs) / Double(count)
        let avgHz = avgIntervalNs > 0 ? 1_000_000_000.0 / avgIntervalNs : 0

        let minUs = Double(sorted.first!) / 1000.0
        let maxUs = Double(sorted.last!) / 1000.0

        let variance = intervals.reduce(0.0) { acc, val in
            let diff = Double(val) - avgIntervalNs
            return acc + diff * diff
        } / Double(count)
        let jitterUs = variance.squareRoot() / 1000.0

        let p50Us = Double(percentile(sorted: sorted, p: 0.50)) / 1000.0
        let p95Us = Double(percentile(sorted: sorted, p: 0.95)) / 1000.0
        let p99Us = Double(percentile(sorted: sorted, p: 0.99)) / 1000.0

        let p50Ns = percentile(sorted: sorted, p: 0.50)
        let effectiveHz = p50Ns > 0 ? 1_000_000_000.0 / Double(p50Ns) : 0

        return MeasurementStatistics(
            sampleCount: samples.count,
            durationSeconds: durationSeconds,
            averageHz: avgHz,
            minIntervalMicroseconds: minUs,
            maxIntervalMicroseconds: maxUs,
            jitterStdDevMicroseconds: jitterUs,
            p50Microseconds: p50Us,
            p95Microseconds: p95Us,
            p99Microseconds: p99Us,
            effectivePollingRateHz: effectiveHz
        )
    }

    private static func percentile(sorted: [UInt64], p: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[min(index, sorted.count - 1)]
    }
}
