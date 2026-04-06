import SwiftUI
import HidLensCore

@MainActor
final class PollingOverrideViewModel: ObservableObject {
    @Published var selectedRate: PollingProfile = .hz1000
    @Published var kextAvailable = false
    @Published var statusMessage: String?
    @Published var isError = false
    @Published var isApplying = false
    @Published var showSetupGuide = false

    private let overrideService = PollingOverrideService()

    init() {
        kextAvailable = KextInstaller.isKextLoaded()
    }

    func applyOverride(deviceVID: Int, devicePID: Int) {
        statusMessage = nil
        isError = false
        isApplying = true

        Task {
            do {
                let devices = try overrideService.listKextDevices()
                guard let device = devices.first(where: {
                    $0.vendorID == UInt16(deviceVID) && $0.productID == UInt16(devicePID)
                }) else {
                    statusMessage = "Device not matched by KEXT"
                    isError = true
                    isApplying = false
                    return
                }

                try overrideService.setPollingRate(
                    deviceIndex: device.index,
                    targetHz: UInt32(selectedRate.rawValue)
                )
                statusMessage = "Override applied: \(selectedRate.label)"
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
            isApplying = false
        }
    }

    func resetDevice(deviceVID: Int, devicePID: Int) {
        statusMessage = nil
        isError = false
        isApplying = true

        Task {
            do {
                let devices = try overrideService.listKextDevices()
                guard let device = devices.first(where: {
                    $0.vendorID == UInt16(deviceVID) && $0.productID == UInt16(devicePID)
                }) else {
                    statusMessage = "Device not matched by KEXT"
                    isError = true
                    isApplying = false
                    return
                }

                try overrideService.resetDevice(deviceIndex: device.index)
                statusMessage = "Restored to original rate"
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
            isApplying = false
        }
    }
}
