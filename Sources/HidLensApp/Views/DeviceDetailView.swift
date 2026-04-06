import SwiftUI
import HidLensCore

struct DeviceDetailView: View {
    let device: HIDDeviceInfo
    @StateObject private var measureVM = MeasurementViewModel()
    @StateObject private var overrideVM = PollingOverrideViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Device Info Section
                deviceInfoSection

                Divider()

                // Controller Profile
                if let profile = ControllerProfile.find(vendorID: device.vendorID, productID: device.productID) {
                    controllerProfileSection(profile)
                    Divider()
                }

                // Polling Override Section
                pollingOverrideSection

                Divider()

                // Measurement Section
                measurementSection
            }
            .padding(24)
        }
        .navigationTitle(device.displayName)
        .sheet(isPresented: $measureVM.showResults) {
            if let stats = measureVM.finalStats {
                MeasurementResultsView(stats: stats, deviceName: device.displayName)
            }
        }
    }

    // MARK: - Device Info

    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Device Info", systemImage: "info.circle")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                infoRow("Name", device.displayName)
                infoRow("Vendor ID", device.vendorIDHex)
                infoRow("Product ID", device.productIDHex)
                infoRow("Manufacturer", device.manufacturer ?? "N/A")
                infoRow("Transport", device.transport ?? "N/A")
                infoRow("Registry ID", "\(device.id)")
            }
        }
    }

    private func controllerProfileSection(_ profile: ControllerProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Controller Profile", systemImage: "gamecontroller")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                infoRow("Profile", profile.name)
                infoRow("USB Speed", profile.usbSpeed.rawValue)
                infoRow("Default Rate", "\(profile.defaultHz) Hz")
                infoRow("Max Rate", "\(profile.maxPollingHz) Hz")
                infoRow("Default bInterval", "\(profile.defaultBInterval)")
            }
        }
    }

    // MARK: - Polling Override

    private var pollingOverrideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Polling Override", systemImage: "bolt.fill")
                .font(.headline)

            if !overrideVM.kextAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("KEXT not loaded. Override unavailable.")
                        .foregroundStyle(.secondary)
                }
                Button("Show Setup Instructions") {
                    overrideVM.showSetupGuide = true
                }
                .sheet(isPresented: $overrideVM.showSetupGuide) {
                    SetupGuideView()
                }
            } else {
                HStack(spacing: 16) {
                    Picker("Target Rate", selection: $overrideVM.selectedRate) {
                        ForEach(PollingProfile.allCases, id: \.self) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)

                    Button("Apply") {
                        overrideVM.applyOverride(deviceVID: device.vendorID, devicePID: device.productID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(overrideVM.isApplying)

                    Button("Reset") {
                        overrideVM.resetDevice(deviceVID: device.vendorID, devicePID: device.productID)
                    }
                    .disabled(overrideVM.isApplying)
                }

                if let message = overrideVM.statusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(overrideVM.isError ? .red : .green)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Measurement

    private var measurementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Polling Rate Measurement", systemImage: "waveform.path.ecg")
                .font(.headline)

            HStack(spacing: 16) {
                Button(measureVM.isRunning ? "Stop" : "Start Measurement") {
                    if measureVM.isRunning {
                        measureVM.stopMeasurement()
                    } else {
                        measureVM.startMeasurement(vendorID: device.vendorID, productID: device.productID)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(measureVM.isRunning ? .red : .blue)

                if measureVM.isRunning {
                    // Circular progress indicator
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 3)
                            .frame(width: 28, height: 28)
                        Circle()
                            .trim(from: 0, to: measureVM.progress)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: measureVM.progress)
                    }

                    Text(String(format: "%.0f%%", measureVM.progress * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36)

                    Text("Move device / press buttons...")
                        .foregroundStyle(.secondary)
                }
            }

            // Live stats while measuring
            if measureVM.isRunning, let stats = measureVM.statistics, stats.sampleCount > 1 {
                HStack(spacing: 20) {
                    liveStatBadge("Samples", "\(stats.sampleCount)")
                    liveStatBadge("Rate", String(format: "%.0f Hz", stats.averageHz))
                    liveStatBadge("Jitter", String(format: "%.1f us", stats.jitterStdDevMicroseconds))
                }
                .padding(10)
                .background(.regularMaterial)
                .cornerRadius(8)
                .transition(.opacity)
            }

            if let error = measureVM.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .animation(.default, value: measureVM.isRunning)
    }

    private func liveStatBadge(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
