import Darwin

public struct TimestampConverter: Sendable {
    public static let shared = TimestampConverter()

    private let numer: UInt64
    private let denom: UInt64

    public init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        numer = UInt64(info.numer)
        denom = UInt64(info.denom)
    }

    // Overflow-safe: split multiplication avoids UInt64 overflow on Apple Silicon (numer=125, denom=3)
    public func nanoseconds(fromMachTime machTime: UInt64) -> UInt64 {
        let wholePart = machTime / denom * numer
        let remainder = machTime % denom * numer / denom
        return wholePart + remainder
    }

    public func microseconds(fromNanoseconds ns: UInt64) -> Double {
        Double(ns) / 1000.0
    }

    public func hertz(fromIntervalNanoseconds ns: UInt64) -> Double {
        guard ns > 0 else { return 0 }
        return 1_000_000_000.0 / Double(ns)
    }
}
