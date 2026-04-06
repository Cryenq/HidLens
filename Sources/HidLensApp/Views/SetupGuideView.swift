import SwiftUI
import HidLensCore

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var csrStatus: PermissionChecker.CSRStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HidLens Setup")
                    .font(.title2.bold())
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
                VStack(alignment: .leading, spacing: 20) {
                    if let csr = csrStatus {
                        statusSection(csr)
                    }
                    sipSection
                    kextSection
                    usageSection
                    disclaimerSection
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 650)
        .task {
            csrStatus = PermissionChecker.checkCSRStatus()
        }
    }

    private func statusSection(_ csr: PermissionChecker.CSRStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("System Status", systemImage: "checkmark.shield")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    statusDot(csr.kextSigningDisabled)
                    Text("Kext Signing")
                        .font(.callout)
                    Text(csr.kextSigningDisabled ? "disabled" : "enabled — needs change")
                        .font(.callout)
                        .foregroundStyle(csr.kextSigningDisabled ? .green : .red)
                }
                GridRow {
                    statusDot(KextInstaller.isKextLoaded())
                    Text("HidLens KEXT")
                        .font(.callout)
                    Text(KextInstaller.isKextLoaded() ? "loaded" : "not loaded")
                        .font(.callout)
                        .foregroundStyle(KextInstaller.isKextLoaded() ? .green : .red)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
    }

    private func statusDot(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? .green : .red)
    }

    private var sipSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("1. Disable Kext Signing (one-time)", systemImage: "lock.shield")
                .font(.headline)

            Text("Required so macOS allows loading third-party kernel extensions.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Shut down your Mac completely")
                step(2, "Hold the power button until \"Loading startup options\" appears")
                step(3, "Click Options → Continue")
                step(4, "Open Terminal from the Utilities menu")
                step(5, "Run:")
                codeBlock("csrutil enable --without kext")
                step(6, "Restart your Mac")
            }

            Text("Verify after reboot:")
                .font(.callout)
                .foregroundStyle(.secondary)
            codeBlock("csrutil status")
            Text("Should show: Kext Signing: disabled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var kextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("2. Install the KEXT", systemImage: "puzzlepiece.extension")
                .font(.headline)

            Text("Click the Install button in the sidebar — it will ask for your password.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("On first install, macOS may require a reboot before the KEXT loads. After rebooting, click Install again.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("If System Settings prompts you to approve the extension, do so under Privacy & Security.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Manual install via Terminal:")
                .font(.callout)
                .foregroundStyle(.secondary)
            codeBlock("sudo bash ~/Downloads/HidLens/Scripts/install-kext.sh")
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("3. Use", systemImage: "gamecontroller")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Connect your DualShock 4 via USB")
                Text("2. Select it in the sidebar")
                Text("3. Pick a polling rate and click Apply")
                Text("4. Run a measurement to verify")
            }
            .font(.callout)

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("A USB hub gives the best results — true 1000Hz on Apple Silicon.")
                    .font(.caption)
            }
        }
    }

    private var disclaimerSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Heads up")
                    .font(.caption.bold())
                Text("KEXTs are deprecated by Apple. Partially disabling SIP reduces system security. The KEXT must be reloaded after every reboot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.08))
        .cornerRadius(8)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(.callout, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.06))
            .cornerRadius(6)
            .textSelection(.enabled)
    }
}
