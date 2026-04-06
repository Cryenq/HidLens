import ArgumentParser
import HidLensCore

struct ResetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset a device to its original polling rate (requires KEXT)"
    )

    @Argument(help: "Device index from KEXT")
    var deviceIndex: UInt32

    func run() throws {
        guard KextInstaller.isKextLoaded() else {
            print("Error: HidLens KEXT is not loaded.")
            throw ExitCode.failure
        }

        let service = PollingOverrideService()

        let devices = try service.listKextDevices()
        guard deviceIndex < devices.count else {
            print("Error: Device index \(deviceIndex) out of range")
            throw ExitCode.failure
        }

        let device = devices[Int(deviceIndex)]
        print("Device: \(device.productName)")
        print("Current rate: \(device.currentHz)Hz")
        print("Restoring original rate: \(device.originalHz)Hz...")

        try service.resetDevice(deviceIndex: deviceIndex)

        print("Success! Rate restored to \(device.originalHz)Hz (bInterval=\(device.originalBInterval))")
    }
}
