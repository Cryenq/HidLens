import ArgumentParser
import HidLensCore

struct OverrideCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "override",
        abstract: "Override the USB polling rate for a device (requires KEXT)"
    )

    @Argument(help: "Device index from KEXT (use 'hidlens list' with KEXT loaded)")
    var deviceIndex: UInt32

    @Option(name: .long, help: "Target polling rate in Hz (125, 250, 500, 1000)")
    var rate: UInt32

    func validate() throws {
        let validRates: Set<UInt32> = [125, 250, 500, 1000]
        if !validRates.contains(rate) {
            throw ValidationError("Rate must be one of: 125, 250, 500, 1000 Hz")
        }
    }

    func run() throws {
        guard KextInstaller.isKextLoaded() else {
            print("Error: HidLens KEXT is not loaded.")
            print("Run 'hidlens setup' for installation instructions.")
            throw ExitCode.failure
        }

        let service = PollingOverrideService()

        // Show current state
        let devices = try service.listKextDevices()
        guard deviceIndex < devices.count else {
            print("Error: Device index \(deviceIndex) out of range (0-\(devices.count - 1))")
            throw ExitCode.failure
        }

        let device = devices[Int(deviceIndex)]
        print("Device: \(device.productName)")
        print("Current rate: \(device.currentHz)Hz (bInterval=\(device.currentBInterval))")
        print("Applying override: \(rate)Hz...")

        try service.setPollingRate(deviceIndex: deviceIndex, targetHz: rate)

        // Verify
        let (newBInterval, newHz) = try service.getCurrentRate(deviceIndex: deviceIndex)
        print("Success! New rate: \(newHz)Hz (bInterval=\(newBInterval))")
        print("")
        print("Run 'hidlens measure \(deviceIndex)' to verify the actual polling rate.")
    }
}
