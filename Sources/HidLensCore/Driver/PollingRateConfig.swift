import Foundation

public struct PollingRateConfig: Codable, Sendable {
    public let deviceIndex: UInt32
    public let targetHz: UInt32

    public init(deviceIndex: UInt32, targetHz: UInt32) {
        self.deviceIndex = deviceIndex
        self.targetHz = targetHz
    }
}
