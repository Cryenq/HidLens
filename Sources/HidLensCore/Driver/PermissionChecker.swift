import Foundation
import IOKit
import IOKit.hid
#if canImport(AppKit)
import AppKit
#endif

public enum PermissionChecker {

    public struct CSRStatus: Sendable {
        public let kextSigningDisabled: Bool
        public let kernelIntegrityDisabled: Bool
        public let rawOutput: String

        public var isConfiguredForKext: Bool {
            kextSigningDisabled
        }

        public var issues: [String] {
            var result: [String] = []
            if !kextSigningDisabled {
                result.append("Kext Signing must be disabled")
            }
            return result
        }
    }

    public struct PermissionStatus: Sendable {
        public let hidAccessGranted: Bool
        public let kextLoaded: Bool
        public let csrStatus: CSRStatus

        public var sipConfigured: Bool { csrStatus.isConfiguredForKext }
        public var canMeasure: Bool { hidAccessGranted }
        public var canOverride: Bool { hidAccessGranted && kextLoaded }
        public var allReady: Bool { hidAccessGranted && kextLoaded && sipConfigured }
    }

    public static func checkAll() -> PermissionStatus {
        PermissionStatus(
            hidAccessGranted: checkHIDAccess(),
            kextLoaded: KextInstaller.isKextLoaded(),
            csrStatus: checkCSRStatus()
        )
    }

    public static func checkCSRStatus() -> CSRStatus {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        process.arguments = ["status"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CSRStatus(kextSigningDisabled: false, kernelIntegrityDisabled: false, rawOutput: "Failed to run csrutil: \(error.localizedDescription)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return CSRStatus(
            kextSigningDisabled: output.contains("Kext Signing: disabled"),
            kernelIntegrityDisabled: output.contains("Kernel Integrity Protections: disabled"),
            rawOutput: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public static func checkHIDAccess() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { return false }

        IOHIDManagerSetDeviceMatchingMultiple(manager, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)

        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        return devices != nil && !(devices?.isEmpty ?? true)
    }

    public static func openInputMonitoringSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    public static func openPrivacySecuritySettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
