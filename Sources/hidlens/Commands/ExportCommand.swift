import ArgumentParser
import HidLensCore
import Foundation

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Measure and export results as JSON or CSV"
    )

    @Argument(help: "Device registry ID (from 'hidlens list')")
    var deviceID: UInt64

    @Option(name: .long, help: "Export format: json or csv")
    var format: ExportFormat = .json

    @Option(name: .long, help: "Measurement duration in seconds")
    var duration: Double = 5.0

    @Option(name: .shortAndLong, help: "Output file path (default: stdout)")
    var output: String?

    enum ExportFormat: String, ExpressibleByArgument {
        case json, csv
    }

    func run() async throws {
        let deviceService = DeviceService()
        guard let device = try deviceService.listDevices().first(where: { $0.id == deviceID }) else {
            throw ValidationError("Device \(deviceID) not found")
        }

        let measureService = MeasurementService()

        // Measure silently
        let stats = try measureService.measure(
            vendorID: device.vendorID,
            productID: device.productID,
            duration: duration
        )

        guard stats.sampleCount > 1 else {
            throw ValidationError("Not enough data. Move the device during measurement.")
        }

        let result: String
        switch format {
        case .json:
            result = try JSONExporter.exportString(device: device, statistics: stats)
        case .csv:
            result = CSVExporter.export(device: device, statistics: stats)
        }

        if let outputPath = output {
            try result.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("Exported to: \(outputPath)")
        } else {
            print(result)
        }
    }
}
