import Foundation

public struct MeasurementSample: Sendable {
    public let timestampNanoseconds: UInt64
    public let intervalNanoseconds: UInt64?

    public init(timestampNanoseconds: UInt64, intervalNanoseconds: UInt64?) {
        self.timestampNanoseconds = timestampNanoseconds
        self.intervalNanoseconds = intervalNanoseconds
    }
}
