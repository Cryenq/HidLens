import HidLensCore
import Foundation

final class LiveDisplay {
    private var lastLineCount = 0

    init() {}

    func update(stats: MeasurementStatistics) {
        // Move cursor up to overwrite previous output
        if lastLineCount > 0 {
            print("\u{1B}[\(lastLineCount)A", terminator: "")
        }

        var lines: [String] = []
        lines.append("\u{1B}[2K  Samples:     \(stats.sampleCount)")
        lines.append("\u{1B}[2K  Duration:    \(String(format: "%.1f", stats.durationSeconds))s")
        lines.append("\u{1B}[2K  Avg Rate:    \(String(format: "%.1f", stats.averageHz)) Hz")
        lines.append("\u{1B}[2K  Effective:   \(String(format: "%.1f", stats.effectivePollingRateHz)) Hz")
        lines.append("\u{1B}[2K  Jitter (σ):  \(String(format: "%.1f", stats.jitterStdDevMicroseconds)) μs")
        lines.append("\u{1B}[2K  p50:         \(String(format: "%.1f", stats.p50Microseconds)) μs")
        lines.append("\u{1B}[2K  p95:         \(String(format: "%.1f", stats.p95Microseconds)) μs")

        // Simple ASCII bar for Hz
        let bar = hzBar(hz: stats.averageHz, maxHz: 1100)
        lines.append("\u{1B}[2K  [\(bar)] \(String(format: "%.0f", stats.averageHz)) Hz")

        let output = lines.joined(separator: "\n")
        print(output)
        lastLineCount = lines.count
    }

    private func hzBar(hz: Double, maxHz: Double, width: Int = 30) -> String {
        let filled = Int(min(hz / maxHz, 1.0) * Double(width))
        let empty = width - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }
}
