import SwiftUI

struct SettingsView: View {
    @AppStorage("showAllDevices") private var showAllDevices = false
    @StateObject private var updateChecker = UpdateChecker()

    var body: some View {
        Form {
            Section {
                Toggle("Show all HID devices", isOn: $showAllDevices)
                Text("When enabled, all connected HID devices are shown. When disabled, only PS4 DualShock 4 controllers are listed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Experimental", systemImage: "flask")
            }

            Section {
                HStack {
                    Text("Updates")
                    Spacer()
                    if updateChecker.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else if let update = updateChecker.availableUpdate {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("v\(update.version) available")
                                .foregroundStyle(.orange)
                            Button("Download") {
                                updateChecker.openDownloadPage()
                            }
                            .controlSize(.small)
                        }
                    } else if updateChecker.lastChecked != nil {
                        Text("Up to date")
                            .foregroundStyle(.green)
                    }
                }
                Button("Check for Updates") {
                    updateChecker.check()
                }
                .disabled(updateChecker.isChecking)

                if let error = updateChecker.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }

            Section {
                LabeledContent("Version", value: UpdateChecker.currentVersion)
                LabeledContent("Build", value: "16")
                HStack {
                    Text("GitHub")
                    Spacer()
                    Link("Cryenq/HidLens", destination: URL(string: "https://github.com/Cryenq/HidLens")!)
                        .foregroundStyle(.blue)
                }
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 380)
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let currentVersion = "1.0.2"
    private static let repoOwner = "Cryenq"
    private static let repoName = "HidLens"

    struct Update {
        let version: String
        let url: URL
    }

    @Published var isChecking = false
    @Published var availableUpdate: Update?
    @Published var errorMessage: String?
    @Published var lastChecked: Date?

    func check() {
        isChecking = true
        errorMessage = nil
        availableUpdate = nil

        let urlString = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if httpResponse.statusCode == 404 {
                    // No releases yet
                    lastChecked = Date()
                    isChecking = false
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let tagName = json?["tag_name"] as? String else {
                    lastChecked = Date()
                    isChecking = false
                    return
                }

                let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                if isNewer(remote: remoteVersion, current: Self.currentVersion) {
                    let htmlURL = json?["html_url"] as? String ?? "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases"
                    availableUpdate = Update(version: remoteVersion, url: URL(string: htmlURL)!)
                }

                lastChecked = Date()
            } catch {
                errorMessage = "Could not check for updates"
            }
            isChecking = false
        }
    }

    func openDownloadPage() {
        if let update = availableUpdate {
            NSWorkspace.shared.open(update.url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases")!)
        }
    }

    private func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
