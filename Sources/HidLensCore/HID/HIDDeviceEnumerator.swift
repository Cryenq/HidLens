import Foundation
import IOKit
import IOKit.hid

public final class HIDDeviceEnumerator: @unchecked Sendable {

    public init() {}

    public func enumerateDevices() throws -> [HIDDeviceInfo] {
        let manager = HIDManagerWrapper()
        try manager.open()
        defer { manager.close() }

        let matchingCriteria: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey as String: kHIDUsage_GD_GamePad],
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Joystick],
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey as String: kHIDUsage_GD_MultiAxisController]
        ]

        manager.setDeviceMatching(matchingCriteria)

        let devices = manager.copyDevices()

        return devices.compactMap { device in
            extractDeviceInfo(from: device)
        }.sorted { ($0.product ?? "") < ($1.product ?? "") }
    }

    public func enumerateControllers() throws -> [HIDDeviceInfo] {
        let all = try enumerateDevices()
        let knownVIDs = Set(ControllerProfile.allProfiles.map { $0.vendorID })
        let knownPIDs = Set(ControllerProfile.allProfiles.map { $0.productID })

        return all.filter { device in
            knownVIDs.contains(device.vendorID) && knownPIDs.contains(device.productID)
        }
    }

    public func findDevice(registryID: UInt64) throws -> HIDDeviceInfo? {
        let all = try enumerateDevices()
        return all.first { $0.id == registryID }
    }

    // MARK: - Private

    private func extractDeviceInfo(from device: IOHIDDevice) -> HIDDeviceInfo? {
        let vid = intProperty(device, kIOHIDVendorIDKey) ?? 0
        let pid = intProperty(device, kIOHIDProductIDKey) ?? 0

        var entryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        IORegistryEntryGetRegistryEntryID(service, &entryID)

        return HIDDeviceInfo(
            id: entryID,
            vendorID: vid,
            productID: pid,
            manufacturer: stringProperty(device, kIOHIDManufacturerKey),
            product: stringProperty(device, kIOHIDProductKey),
            transport: stringProperty(device, kIOHIDTransportKey),
            usbSpeed: nil,
            bInterval: nil,
            serialNumber: stringProperty(device, kIOHIDSerialNumberKey),
            maxInputReportSize: intProperty(device, kIOHIDMaxInputReportSizeKey),
            primaryUsagePage: intProperty(device, kIOHIDPrimaryUsagePageKey),
            primaryUsage: intProperty(device, kIOHIDPrimaryUsageKey)
        )
    }

    private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }
}
