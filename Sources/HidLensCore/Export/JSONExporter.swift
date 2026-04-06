import Foundation

public enum JSONExporter {

    public struct ExportData: Codable {
        public let device: HIDDeviceInfo
        public let statistics: MeasurementStatistics
        public let exportedAt: String
        public let toolVersion: String
    }

    public static func export(device: HIDDeviceInfo, statistics: MeasurementStatistics) throws -> Data {
        let iso = ISO8601DateFormatter()
        let exportData = ExportData(
            device: device,
            statistics: statistics,
            exportedAt: iso.string(from: Date()),
            toolVersion: "1.0.0"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportData)
    }

    public static func exportString(device: HIDDeviceInfo, statistics: MeasurementStatistics) throws -> String {
        let data = try export(device: device, statistics: statistics)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
