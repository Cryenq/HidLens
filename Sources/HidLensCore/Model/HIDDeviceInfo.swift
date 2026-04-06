import Foundation

public struct HIDDeviceInfo: Identifiable, Codable, Sendable, Hashable {
    public let id: UInt64
    public let vendorID: Int
    public let productID: Int
    public let manufacturer: String?
    public let product: String?
    public let transport: String?
    public let usbSpeed: String?
    public let bInterval: Int?
    public let serialNumber: String?
    public let maxInputReportSize: Int?
    public let primaryUsagePage: Int?
    public let primaryUsage: Int?

    public var vendorIDHex: String {
        String(format: "0x%04X", vendorID)
    }

    public var productIDHex: String {
        String(format: "0x%04X", productID)
    }

    public var displayName: String {
        product ?? "\(vendorIDHex):\(productIDHex)"
    }

    public var isAppleInternal: Bool {
        vendorID == 0x05AC || (manufacturer?.lowercased().contains("apple") ?? false)
    }

    public var isKnownController: Bool {
        ControllerProfile.find(vendorID: vendorID, productID: productID) != nil
    }

    public var isDS4Controller: Bool {
        vendorID == 0x054C && (productID == 0x05C4 || productID == 0x09CC)
    }

    public var isExternalGamingDevice: Bool {
        if isAppleInternal { return false }
        if isKnownController { return true }
        if let usage = primaryUsage, (usage == 0x04 || usage == 0x05) { return true }
        if let usage = primaryUsage, usage == 0x02, !isAppleInternal { return true }
        return false
    }
}
