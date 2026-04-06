import Foundation

public enum CSVExporter {

    public static func export(device: HIDDeviceInfo, statistics: MeasurementStatistics) -> String {
        var lines: [String] = []

        lines.append("field,value")

        lines.append("device_name,\(csvEscape(device.displayName))")
        lines.append("vendor_id,\(device.vendorIDHex)")
        lines.append("product_id,\(device.productIDHex)")
        lines.append("manufacturer,\(csvEscape(device.manufacturer ?? ""))")
        lines.append("transport,\(csvEscape(device.transport ?? ""))")

        lines.append("sample_count,\(statistics.sampleCount)")
        lines.append("duration_seconds,\(String(format: "%.3f", statistics.durationSeconds))")
        lines.append("average_hz,\(String(format: "%.2f", statistics.averageHz))")
        lines.append("effective_hz,\(String(format: "%.2f", statistics.effectivePollingRateHz))")
        lines.append("min_interval_us,\(String(format: "%.2f", statistics.minIntervalMicroseconds))")
        lines.append("max_interval_us,\(String(format: "%.2f", statistics.maxIntervalMicroseconds))")
        lines.append("jitter_stddev_us,\(String(format: "%.2f", statistics.jitterStdDevMicroseconds))")
        lines.append("p50_us,\(String(format: "%.2f", statistics.p50Microseconds))")
        lines.append("p95_us,\(String(format: "%.2f", statistics.p95Microseconds))")
        lines.append("p99_us,\(String(format: "%.2f", statistics.p99Microseconds))")

        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
