import Foundation

public struct MeasurementStatistics: Codable, Sendable {
    public let sampleCount: Int
    public let durationSeconds: Double
    public let averageHz: Double
    public let minIntervalMicroseconds: Double
    public let maxIntervalMicroseconds: Double
    public let jitterStdDevMicroseconds: Double
    public let p50Microseconds: Double
    public let p95Microseconds: Double
    public let p99Microseconds: Double
    public let effectivePollingRateHz: Double

    public static let empty = MeasurementStatistics(
        sampleCount: 0, durationSeconds: 0, averageHz: 0,
        minIntervalMicroseconds: 0, maxIntervalMicroseconds: 0,
        jitterStdDevMicroseconds: 0, p50Microseconds: 0,
        p95Microseconds: 0, p99Microseconds: 0,
        effectivePollingRateHz: 0
    )
}
