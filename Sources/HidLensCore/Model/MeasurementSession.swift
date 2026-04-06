import Foundation

public final class MeasurementSession: @unchecked Sendable {
    public enum State: Sendable {
        case idle
        case running
        case completed
    }

    public private(set) var state: State = .idle
    private var samples: [MeasurementSample] = []
    private var lastTimestampNs: UInt64?
    private let lock = NSLock()

    public var onUpdate: ((MeasurementStatistics) -> Void)?
    public var updateInterval: Int = 50

    public init(estimatedDuration: TimeInterval? = nil, estimatedHz: Int = 500) {
        let capacity = Int(estimatedDuration ?? 10) * estimatedHz
        samples.reserveCapacity(capacity)
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        state = .running
        samples.removeAll(keepingCapacity: true)
        lastTimestampNs = nil
    }

    public func addSample(timestampNanoseconds: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        guard state == .running else { return }

        let interval: UInt64? = lastTimestampNs.map { timestampNanoseconds - $0 }
        let sample = MeasurementSample(
            timestampNanoseconds: timestampNanoseconds,
            intervalNanoseconds: interval
        )
        samples.append(sample)
        lastTimestampNs = timestampNanoseconds

        if samples.count % updateInterval == 0, let onUpdate {
            let stats = StatisticsCalculator.compute(from: samples)
            onUpdate(stats)
        }
    }

    public func stop() -> MeasurementStatistics {
        lock.lock()
        defer { lock.unlock() }
        state = .completed
        return StatisticsCalculator.compute(from: samples)
    }

    public var currentStatistics: MeasurementStatistics {
        lock.lock()
        defer { lock.unlock() }
        return StatisticsCalculator.compute(from: samples)
    }

    public var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }
}
