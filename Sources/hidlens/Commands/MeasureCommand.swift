import ArgumentParser
import HidLensCore
import Foundation

struct MeasureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "measure",
        abstract: "Measure the actual polling rate of a device"
    )

    @Argument(help: "Device registry ID (from 'hidlens list')")
    var deviceID: UInt64

    @Option(name: .long, help: "Measurement duration in seconds (default: 5)")
    var duration: Double = 5.0

    @Flag(name: .long, help: "Quiet mode — only print final statistics")
    var quiet = false

    func run() async throws {
        let deviceService = DeviceService()
        guard let device = try deviceService.listDevices().first(where: { $0.id == deviceID }) else {
            throw ValidationError("Device with ID \(deviceID) not found. Run 'hidlens list' to see available devices.")
        }

        let measureService = MeasurementService()

        if !quiet {
            print("Measuring polling rate for: \(device.displayName)")
            print("Duration: \(String(format: "%.0f", duration))s — move the device / press buttons to generate reports\n")
        }

        // Install SIGINT handler for graceful shutdown
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN) // Ignore default SIGINT handling
        signalSource.setEventHandler {
            let stats = measureService.stop()
            if !self.quiet {
                print("\n")
            }
            Self.printStatistics(stats, device: device)
            Foundation.exit(0)
        }
        signalSource.resume()

        let liveDisplay = quiet ? nil : LiveDisplay()

        let stats = try measureService.measure(
            vendorID: device.vendorID,
            productID: device.productID,
            duration: duration,
            onUpdate: { intermediateStats in
                liveDisplay?.update(stats: intermediateStats)
            }
        )

        signalSource.cancel()
        signal(SIGINT, SIG_DFL)

        if !quiet {
            print("\n")
        }
        Self.printStatistics(stats, device: device)
    }

    static func printStatistics(_ stats: MeasurementStatistics, device: HIDDeviceInfo) {
        guard stats.sampleCount > 1 else {
            print("Not enough data collected. Make sure the device is generating reports")
            print("(move the mouse / press controller buttons).")
            return
        }

        print("Results for: \(device.displayName)")
        print("═══════════════════════════════════════")
        print("  Samples:         \(stats.sampleCount)")
        print("  Duration:        \(String(format: "%.2f", stats.durationSeconds))s")
        print("  Average Rate:    \(String(format: "%.1f", stats.averageHz)) Hz")
        print("  Effective Rate:  \(String(format: "%.1f", stats.effectivePollingRateHz)) Hz (based on median)")
        print("  Min Interval:    \(String(format: "%.1f", stats.minIntervalMicroseconds)) μs")
        print("  Max Interval:    \(String(format: "%.1f", stats.maxIntervalMicroseconds)) μs")
        print("  Jitter (σ):      \(String(format: "%.1f", stats.jitterStdDevMicroseconds)) μs")
        print("  p50:             \(String(format: "%.1f", stats.p50Microseconds)) μs")
        print("  p95:             \(String(format: "%.1f", stats.p95Microseconds)) μs")
        print("  p99:             \(String(format: "%.1f", stats.p99Microseconds)) μs")

        // Show profile comparison if available
        if let profile = ControllerProfile.find(vendorID: device.vendorID, productID: device.productID) {
            print("")
            print("  Expected default: \(profile.defaultHz) Hz")
            let ratio = stats.averageHz / Double(profile.defaultHz)
            if ratio > 1.5 {
                print("  → Running ABOVE default rate (override active?)")
            } else if ratio < 0.5 {
                print("  → Running BELOW default rate (check connection)")
            } else {
                print("  → Running at expected default rate")
            }
        }
    }
}
