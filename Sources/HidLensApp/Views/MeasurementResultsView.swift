import SwiftUI
import HidLensCore

struct MeasurementResultsView: View {
    let stats: MeasurementStatistics
    let deviceName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Measurement Results")
                        .font(.title2.bold())
                    Text(deviceName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Hero stat
                    heroSection

                    // Detailed stats grid
                    detailsSection

                    // Percentiles
                    percentilesSection

                    // Interval distribution
                    distributionSection
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 600)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.1f", stats.averageHz))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(rateColor)
            Text("Hz Average")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                statPill("Samples", "\(stats.sampleCount)")
                statPill("Duration", String(format: "%.1fs", stats.durationSeconds))
                statPill("Jitter", String(format: "%.1f us", stats.jitterStdDevMicroseconds))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(rateColor.opacity(0.08))
        .cornerRadius(12)
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rateColor: Color {
        if stats.averageHz >= 900 { return .green }
        if stats.averageHz >= 400 { return .orange }
        return .red
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                resultRow("Average Rate", String(format: "%.1f Hz", stats.averageHz))
                resultRow("Effective Rate (median)", String(format: "%.1f Hz", stats.effectivePollingRateHz))
                resultRow("Min Interval", String(format: "%.1f us", stats.minIntervalMicroseconds))
                resultRow("Max Interval", String(format: "%.1f us", stats.maxIntervalMicroseconds))
                resultRow("Std Dev (jitter)", String(format: "%.1f us", stats.jitterStdDevMicroseconds))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
    }

    // MARK: - Percentiles

    private var percentilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Percentiles")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                resultRow("p50", String(format: "%.1f us (%.0f Hz)", stats.p50Microseconds, hzFrom(stats.p50Microseconds)))
                resultRow("p95", String(format: "%.1f us (%.0f Hz)", stats.p95Microseconds, hzFrom(stats.p95Microseconds)))
                resultRow("p99", String(format: "%.1f us (%.0f Hz)", stats.p99Microseconds, hzFrom(stats.p99Microseconds)))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
    }

    // MARK: - Distribution

    private var distributionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Interval Distribution")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                distributionBar(label: "< 500 us", minUs: 0, maxUs: 500)
                distributionBar(label: "500-1000 us", minUs: 500, maxUs: 1000)
                distributionBar(label: "1000-1500 us", minUs: 1000, maxUs: 1500)
                distributionBar(label: "1500-2000 us", minUs: 1500, maxUs: 2000)
                distributionBar(label: "> 2000 us", minUs: 2000, maxUs: 1_000_000)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
    }

    private func distributionBar(label: String, minUs: Double, maxUs: Double) -> some View {
        // We don't have raw intervals in MeasurementStatistics, so show what we can
        // based on percentiles and min/max
        let pct = estimateBucketPercentage(minUs: minUs, maxUs: maxUs)
        return HStack(spacing: 8) {
            Text(label)
                .font(.caption.monospacedDigit())
                .frame(width: 100, alignment: .trailing)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor(minUs: minUs))
                    .frame(width: max(1, geo.size.width * pct))
            }
            .frame(height: 14)

            Text(String(format: "%.0f%%", pct * 100))
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func barColor(minUs: Double) -> Color {
        if minUs < 1000 { return .green }
        if minUs < 1500 { return .orange }
        return .red
    }

    private func estimateBucketPercentage(minUs: Double, maxUs: Double) -> Double {
        // Rough estimate from available percentile data
        let intervals: [(pctile: Double, us: Double)] = [
            (0.0, stats.minIntervalMicroseconds),
            (0.50, stats.p50Microseconds),
            (0.95, stats.p95Microseconds),
            (0.99, stats.p99Microseconds),
            (1.0, stats.maxIntervalMicroseconds)
        ]
        var inBucket = 0.0
        for i in 0..<(intervals.count - 1) {
            let (p1, u1) = intervals[i]
            let (p2, u2) = intervals[i + 1]
            let rangeWidth = p2 - p1
            if u1 >= minUs && u2 < maxUs {
                inBucket += rangeWidth
            } else if u1 < maxUs && u2 >= minUs {
                // Partial overlap
                let lo = max(u1, Double(minUs))
                let hi = min(u2, Double(maxUs))
                let span = u2 - u1
                if span > 0 {
                    inBucket += rangeWidth * ((hi - lo) / span)
                }
            }
        }
        return max(0, min(1, inBucket))
    }

    // MARK: - Helpers

    private func hzFrom(_ us: Double) -> Double {
        us > 0 ? 1_000_000.0 / us : 0
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .trailing)
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }
}
