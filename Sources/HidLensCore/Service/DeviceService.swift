import Foundation

public final class DeviceService: Sendable {
    private let enumerator = HIDDeviceEnumerator()

    public init() {}

    public func listDevices() throws -> [HIDDeviceInfo] {
        try enumerator.enumerateDevices()
    }

    public func listControllers() throws -> [HIDDeviceInfo] {
        try enumerator.enumerateControllers()
    }

    public func inspectDevice(registryID: UInt64) throws -> (HIDDeviceInfo, ControllerProfile?) {
        guard let device = try enumerator.findDevice(registryID: registryID) else {
            throw HIDError.deviceNotFound
        }
        let profile = ControllerProfile.find(vendorID: device.vendorID, productID: device.productID)
        return (device, profile)
    }
}
