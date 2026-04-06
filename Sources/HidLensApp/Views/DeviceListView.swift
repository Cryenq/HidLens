import SwiftUI
import HidLensCore

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceListViewModel
    @Binding var selection: UInt64?
    @State private var showSetupGuide = false

    var body: some View {
        List(selection: $selection) {
            if viewModel.devices.isEmpty && !viewModel.isLoading {
                Text("No devices found")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            ForEach(viewModel.devices) { device in
                DeviceRow(device: device)
                    .tag(device.id)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh device list")
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .top) {
            if !viewModel.hidAccessGranted {
                permissionBanner
            }
        }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
        .sheet(isPresented: $showSetupGuide) {
            SetupGuideView()
        }
    }

    // MARK: - Permission Banner

    private var permissionBanner: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Input Monitoring required")
                    .font(.caption.bold())
            }
            Text("HidLens needs Input Monitoring to read HID devices.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                viewModel.openInputMonitoringSettings()
            }
            .font(.caption)
            .controlSize(.mini)
            .buttonStyle(.borderedProminent)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.1))
    }

    // MARK: - Status Bar (SIP + KEXT)

    private var statusBar: some View {
        VStack(spacing: 4) {
            if let msg = viewModel.kextMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // SIP Status
            if let csr = viewModel.csrStatus {
                sipStatusRow(csr)
            }

            // KEXT Status
            kextStatusRow

            Divider().padding(.horizontal, 4)

            // Action buttons
            HStack(spacing: 8) {
                if viewModel.kextInstalling {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Working...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if viewModel.kextLoaded {
                    Button("Unload KEXT") {
                        viewModel.unloadKext()
                    }
                    .font(.caption)
                    .controlSize(.mini)
                } else if viewModel.csrStatus?.isConfiguredForKext == true {
                    Button("Install KEXT") {
                        viewModel.installKext()
                    }
                    .font(.caption)
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                Button {
                    showSetupGuide = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .font(.caption)
                .controlSize(.mini)
                .buttonStyle(.plain)
                .help("Setup Guide")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func sipStatusRow(_ csr: PermissionChecker.CSRStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(csr.isConfiguredForKext ? .green : .red)
                .frame(width: 8, height: 8)

            if csr.isConfiguredForKext {
                Text("SIP: configured")
                    .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SIP: not configured")
                        .font(.caption)
                        .foregroundStyle(.red)
                    ForEach(csr.issues, id: \.self) { issue in
                        Text("- \(issue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
    }

    private var kextStatusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.kextLoaded ? .green : .red)
                .frame(width: 8, height: 8)

            Text(viewModel.kextLoaded ? "KEXT: loaded" : "KEXT: not loaded")
                .font(.caption)

            Spacer()
        }
    }
}

struct DeviceRow: View {
    let device: HIDDeviceInfo

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(device.vendorIDHex + ":" + device.productIDHex)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let profile = ControllerProfile.find(vendorID: device.vendorID, productID: device.productID) {
                        Text("\(profile.defaultHz)Hz")
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        if let usage = device.primaryUsage {
            switch usage {
            case 0x02: return "computermouse"
            case 0x04, 0x05: return "gamecontroller"
            default: return "cable.connector"
            }
        }
        return "cable.connector"
    }
}
