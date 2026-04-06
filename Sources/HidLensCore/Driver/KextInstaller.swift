import Foundation

public enum KextInstaller {

    private static let bundleID = "com.hidlens.driver"
    private static let kextDstPath = "/tmp/HidLensDriver.kext"

    public static func isKextLoaded() -> Bool {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/kmutil")
        process.arguments = ["showloaded", "--list-only", "--bundle-identifier", bundleID]
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let combined = (String(data: outData, encoding: .utf8) ?? "")
                + (String(data: errData, encoding: .utf8) ?? "")
            return combined.contains(bundleID)
        } catch {
            return false
        }
    }

    public static func findKextPath() -> String? {
        let fm = FileManager.default

        if let bundled = Bundle.main.path(forResource: "HidLensDriver", ofType: "kext") {
            return bundled
        }

        let appPath = Bundle.main.bundlePath
        let productsDir = (appPath as NSString).deletingLastPathComponent
        let siblingPath = productsDir + "/HidLensDriver.kext"
        if fm.fileExists(atPath: siblingPath) {
            return siblingPath
        }

        let homeDir = fm.homeDirectoryForCurrentUser.path
        let projectDirs = [
            homeDir + "/Downloads/HidLens",
            homeDir + "/Developer/HidLens",
            homeDir + "/Projects/HidLens"
        ]
        for dir in projectDirs {
            for config in ["Debug", "Release"] {
                let path = dir + "/build/\(config)/HidLensDriver.kext"
                if fm.fileExists(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    public static func installKext(completion: @escaping (Result<String, Error>) -> Void) {
        guard let kextSrc = findKextPath() else {
            completion(.failure(KextInstallerError.kextNotFound))
            return
        }

        // Copy as current user first — root can't access ~/Downloads (TCC)
        let stagingPath = NSTemporaryDirectory() + "HidLensDriver_staging.kext"
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: stagingPath) {
                try fm.removeItem(atPath: stagingPath)
            }
            try fm.copyItem(atPath: kextSrc, toPath: stagingPath)
        } catch {
            completion(.failure(KextInstallerError.installFailed("Failed to copy KEXT: \(error.localizedDescription)")))
            return
        }

        let commands = [
            "kmutil unload -b \(bundleID) 2>/dev/null || true",
            "rm -rf /private/var/db/KernelExtensionManagement/Staging/\(bundleID).* 2>/dev/null || true",
            "rm -rf \(kextDstPath)",
            "cp -R '\(stagingPath)' \(kextDstPath)",
            "chown -R root:wheel \(kextDstPath)",
            "chmod -R 755 \(kextDstPath)",
            "codesign --force --sign - --deep \(kextDstPath)",
            "kmutil load -p \(kextDstPath)"
        ]

        let shellCommand = commands.joined(separator: " && ")
        runWithAdminPrivileges(shellCommand, completion: completion)
    }

    public static func unloadKext(completion: @escaping (Result<Void, Error>) -> Void) {
        let shellCommand = "kmutil unload -b \(bundleID)"
        runWithAdminPrivileges(shellCommand) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func runWithAdminPrivileges(_ command: String, completion: @escaping (Result<String, Error>) -> Void) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = outPipe
        process.standardError = errPipe

        process.terminationHandler = { proc in
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errData, encoding: .utf8) ?? ""

            if proc.terminationStatus == 0 {
                completion(.success(output))
            } else {
                if errorOutput.contains("User canceled") || errorOutput.contains("-128") {
                    completion(.failure(KextInstallerError.userCancelled))
                } else {
                    let msg = errorOutput.isEmpty ? output : errorOutput
                    completion(.failure(KextInstallerError.installFailed(msg)))
                }
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }

    public static let setupInstructions = """
    HidLens KEXT Setup Guide
    ========================

    1. Boot into Recovery Mode (hold power button → Options)
    2. Open Terminal from Utilities menu
    3. Run: csrutil enable --without kext
    4. Restart your Mac

    5. Build the KEXT: xcodebuild -scheme HidLensDriver build
    6. Install: sudo bash ~/Downloads/HidLens/Scripts/install-kext.sh
    7. Reboot, then run the install script again
    8. Approve in System Settings → Privacy & Security if prompted

    Verify: kmutil showloaded --list-only | grep hidlens
    """
}

public enum KextInstallerError: Error, LocalizedError, Equatable {
    case kextNotFound
    case installFailed(String)
    case userCancelled

    public var errorDescription: String? {
        switch self {
        case .kextNotFound:
            return "KEXT binary not found. Build HidLensDriver in Xcode first."
        case .installFailed(let msg):
            return "KEXT installation failed: \(msg)"
        case .userCancelled:
            return "Installation cancelled by user"
        }
    }
}
