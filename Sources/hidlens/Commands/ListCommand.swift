import ArgumentParser
import HidLensCore
import Foundation

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List connected HID game controllers and mice"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Flag(name: .long, help: "Show only known PlayStation controllers")
    var controllers = false

    func run() throws {
        let service = DeviceService()
        let devices = try controllers ? service.listControllers() : service.listDevices()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(devices)
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        if devices.isEmpty {
            print("No HID devices found.")
            if !controllers {
                print("Make sure a USB controller or mouse is connected.")
            } else {
                print("No known PlayStation controllers detected. Try 'hidlens list' to see all HID devices.")
            }
            return
        }

        // Check if KEXT is available for additional info
        let kextAvailable = KextInstaller.isKextLoaded()

        print("Found \(devices.count) HID device(s):\n")
        print(TableFormatter.deviceTable(devices, kextAvailable: kextAvailable))

        if !kextAvailable {
            print("\nNote: HidLens KEXT not loaded. Polling override unavailable.")
            print("Run 'hidlens setup' for instructions.")
        }
    }
}
