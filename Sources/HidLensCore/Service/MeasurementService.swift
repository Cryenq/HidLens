import Foundation

public final class MeasurementService: @unchecked Sendable {
    private let listener = HIDReportListener()

    public init() {}

    public func measure(
        vendorID: Int,
        productID: Int,
        duration: TimeInterval? = nil,
        onUpdate: ((MeasurementStatistics) -> Void)? = nil
    ) throws -> MeasurementStatistics {
        let session = MeasurementSession(estimatedDuration: duration)
        session.onUpdate = onUpdate

        try listener.startListening(vendorID: vendorID, productID: productID, session: session)

        if let duration {
            Thread.sleep(forTimeInterval: duration)
            return listener.stopListening()
        } else {
            return .empty
        }
    }

    public func stop() -> MeasurementStatistics {
        listener.stopListening()
    }

    public var isRunning: Bool {
        listener.listening
    }
}
