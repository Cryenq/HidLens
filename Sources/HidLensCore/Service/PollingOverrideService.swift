import Foundation

public final class PollingOverrideService: @unchecked Sendable {
    private let kext = KextCommunicator()

    public init() {}

    public func listKextDevices() throws -> [KextDeviceInfo] {
        try kext.connect()
        defer { kext.disconnect() }

        let count = try kext.getDeviceCount()
        var devices: [KextDeviceInfo] = []

        for i in 0..<count {
            do {
                let info = try kext.getDeviceInfo(index: i)
                devices.append(info)
            } catch {
                HidLensLog.driver.warning("Failed to get info for device \(i): \(error.localizedDescription)")
            }
        }

        return devices
    }

    public func setPollingRate(deviceIndex: UInt32, targetHz: UInt32) throws {
        try kext.connect()
        defer { kext.disconnect() }
        try kext.setPollingRate(index: deviceIndex, targetHz: targetHz)
    }

    public func resetDevice(deviceIndex: UInt32) throws {
        try kext.connect()
        defer { kext.disconnect() }
        try kext.resetDevice(index: deviceIndex)
    }

    public func getCurrentRate(deviceIndex: UInt32) throws -> (bInterval: UInt8, hz: UInt32) {
        try kext.connect()
        defer { kext.disconnect() }
        return try kext.getCurrentRate(index: deviceIndex)
    }
}
