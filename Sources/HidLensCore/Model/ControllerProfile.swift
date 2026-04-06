import Foundation

public struct ControllerProfile: Sendable {
    public let name: String
    public let vendorID: Int
    public let productID: Int
    public let defaultBInterval: Int
    public let usbSpeed: USBSpeed
    public let maxPollingHz: Int

    public enum USBSpeed: String, Sendable, Codable {
        case fullSpeed = "Full-Speed"
        case highSpeed = "High-Speed"
        case superSpeed = "SuperSpeed"
    }

    public var defaultHz: Int {
        switch usbSpeed {
        case .fullSpeed:
            return defaultBInterval > 0 ? 1000 / defaultBInterval : 0
        case .highSpeed, .superSpeed:
            let periodUs = (1 << (defaultBInterval - 1)) * 125
            return 1_000_000 / periodUs
        }
    }
}

extension ControllerProfile {
    public static let playstationControllers: [ControllerProfile] = [
        ControllerProfile(
            name: "DualShock 4 (v1)",
            vendorID: 0x054C, productID: 0x05C4,
            defaultBInterval: 5, usbSpeed: .fullSpeed, maxPollingHz: 1000
        ),
        ControllerProfile(
            name: "DualShock 4 (v2)",
            vendorID: 0x054C, productID: 0x09CC,
            defaultBInterval: 5, usbSpeed: .fullSpeed, maxPollingHz: 1000
        ),
        ControllerProfile(
            name: "DualSense",
            vendorID: 0x054C, productID: 0x0CE6,
            defaultBInterval: 4, usbSpeed: .fullSpeed, maxPollingHz: 1000
        ),
        ControllerProfile(
            name: "DualSense Edge",
            vendorID: 0x054C, productID: 0x0DF2,
            defaultBInterval: 4, usbSpeed: .fullSpeed, maxPollingHz: 1000
        )
    ]

    public static let allProfiles: [ControllerProfile] = playstationControllers

    public static func find(vendorID: Int, productID: Int) -> ControllerProfile? {
        allProfiles.first { $0.vendorID == vendorID && $0.productID == productID }
    }
}
