import SwiftUI
import HidLensCore

@MainActor
final class DeviceListViewModel: ObservableObject {
    @Published var devices: [HIDDeviceInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var kextLoaded = false
    @Published var kextInstalling = false
    @Published var kextMessage: String?
    @Published var hidAccessGranted = true
    @Published var csrStatus: PermissionChecker.CSRStatus?
    @AppStorage("showAllDevices") var showAllDevices = false

    private let deviceService = DeviceService()
    private let deviceMonitor = HIDDeviceMonitor()
    private var allDevices: [HIDDeviceInfo] = []

    init() {
        checkPermissionsAndRefresh()
        startMonitoring()
    }

    deinit {
        deviceMonitor.stop()
    }

    func checkPermissionsAndRefresh() {
        isLoading = true
        errorMessage = nil

        Task.detached {
            let permissions = PermissionChecker.checkAll()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.kextLoaded = permissions.kextLoaded
                self.hidAccessGranted = permissions.hidAccessGranted
                self.csrStatus = permissions.csrStatus
            }
        }

        refresh()
    }

    func refresh() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let found = try deviceService.listDevices()
                allDevices = found
                applyFilter()
                kextLoaded = KextInstaller.isKextLoaded()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func applyFilter() {
        if showAllDevices {
            devices = allDevices
        } else {
            // Default: only show PS4 DualShock 4 controllers
            devices = allDevices.filter { $0.isDS4Controller }
        }
    }

    func installKext() {
        kextInstalling = true
        kextMessage = nil

        KextInstaller.installKext { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.kextInstalling = false
                switch result {
                case .success(let output):
                    self.kextMessage = "KEXT installed successfully"
                    self.kextLoaded = KextInstaller.isKextLoaded()
                    HidLensLog.driver.info("KEXT install output: \(output)")
                case .failure(let error):
                    if (error as? KextInstallerError) == .userCancelled {
                        self.kextMessage = nil
                    } else {
                        self.kextMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func unloadKext() {
        kextInstalling = true
        kextMessage = nil

        KextInstaller.unloadKext { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.kextInstalling = false
                switch result {
                case .success:
                    self.kextMessage = "KEXT unloaded"
                    self.kextLoaded = false
                case .failure(let error):
                    if (error as? KextInstallerError) == .userCancelled {
                        self.kextMessage = nil
                    } else {
                        self.kextMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func openInputMonitoringSettings() {
        PermissionChecker.openInputMonitoringSettings()
    }

    private func startMonitoring() {
        deviceMonitor.start { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
}
