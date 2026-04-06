import ArgumentParser
import HidLensCore
import Foundation

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Show detailed info for a specific device"
    )

    @Argument(help: "Device registry ID (from 'hidlens list')")
    var deviceID: UInt64

    func run() throws {
        let service = DeviceService()
        let (device, profile) = try service.inspectDevice(registryID: deviceID)

        print("Device: \(device.displayName)")
        print("─────────────────────────────────────")
        print("  Registry ID:    \(device.id)")
        print("  Vendor ID:      \(device.vendorIDHex)")
        print("  Product ID:     \(device.productIDHex)")
        print("  Manufacturer:   \(device.manufacturer ?? "N/A")")
        print("  Transport:      \(device.transport ?? "N/A")")
        print("  Serial Number:  \(device.serialNumber ?? "N/A")")
        print("  Max Input Size: \(device.maxInputReportSize.map { "\($0) bytes" } ?? "N/A")")
        print("  Usage Page:     \(device.primaryUsagePage.map { String(format: "0x%04X", $0) } ?? "N/A")")
        print("  Usage:          \(device.primaryUsage.map { String(format: "0x%04X", $0) } ?? "N/A")")

        if let profile {
            print("")
            print("Known Controller Profile:")
            print("  Name:           \(profile.name)")
            print("  USB Speed:      \(profile.usbSpeed.rawValue)")
            print("  Default Rate:   \(profile.defaultHz)Hz (bInterval=\(profile.defaultBInterval))")
            print("  Max Rate:       \(profile.maxPollingHz)Hz")
        }

        // Try to get KEXT info
        if KextInstaller.isKextLoaded() {
            let overrideService = PollingOverrideService()
            do {
                let kextDevices = try overrideService.listKextDevices()
                if let kextDevice = kextDevices.first(where: {
                    $0.vendorID == UInt16(device.vendorID) && $0.productID == UInt16(device.productID)
                }) {
                    print("")
                    print("KEXT Info:")
                    print("  USB Speed:      \(kextDevice.usbSpeedString)")
                    print("  Original Rate:  \(kextDevice.originalHz)Hz (bInterval=\(kextDevice.originalBInterval))")
                    print("  Current Rate:   \(kextDevice.currentHz)Hz (bInterval=\(kextDevice.currentBInterval))")
                    print("  Overridden:     \(kextDevice.isOverridden ? "YES" : "No")")
                }
            } catch {
                // KEXT communication failed — not critical
            }
        }
    }
}
