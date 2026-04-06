import Foundation
import IOKit

public final class KextCommunicator: @unchecked Sendable {
    private var connection: io_connect_t = IO_OBJECT_NULL

    public var isConnected: Bool { connection != IO_OBJECT_NULL }

    public init() {}

    deinit {
        disconnect()
    }

    public func connect() throws {
        let matchingDict = IOServiceMatching("HidLensDriver")
        var iterator: io_iterator_t = IO_OBJECT_NULL

        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard kr == KERN_SUCCESS else { throw KextError.serviceNotFound }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != IO_OBJECT_NULL else { throw KextError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = IO_OBJECT_NULL
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess else { throw KextError.openFailed(result) }

        connection = conn
    }

    public func disconnect() {
        if connection != IO_OBJECT_NULL {
            IOServiceClose(connection)
            connection = IO_OBJECT_NULL
        }
    }

    public func getDeviceCount() throws -> UInt32 {
        try ensureConnected()

        var outputCount: UInt32 = 1
        var output: [UInt64] = [0]

        let kr = IOConnectCallScalarMethod(connection, 0, nil, 0, &output, &outputCount)
        guard kr == kIOReturnSuccess else { throw KextError.callFailed(selector: 0, code: kr) }

        return UInt32(output[0])
    }

    public func getDeviceInfo(index: UInt32) throws -> KextDeviceInfo {
        try ensureConnected()

        let input: [UInt64] = [UInt64(index)]
        var outputSize = MemoryLayout<KextDeviceInfo.RawInfo>.size
        var rawInfo = KextDeviceInfo.RawInfo()

        let kr = IOConnectCallMethod(connection, 1, input, UInt32(input.count), nil, 0, nil, nil, &rawInfo, &outputSize)
        guard kr == kIOReturnSuccess else { throw KextError.callFailed(selector: 1, code: kr) }

        return KextDeviceInfo(raw: rawInfo)
    }

    public func setPollingRate(index: UInt32, targetHz: UInt32) throws {
        try ensureConnected()

        let input: [UInt64] = [UInt64(index), UInt64(targetHz)]
        let kr = IOConnectCallScalarMethod(connection, 2, input, UInt32(input.count), nil, nil)
        guard kr == kIOReturnSuccess else { throw KextError.callFailed(selector: 2, code: kr) }
    }

    public func resetDevice(index: UInt32) throws {
        try ensureConnected()

        let input: [UInt64] = [UInt64(index)]
        let kr = IOConnectCallScalarMethod(connection, 3, input, UInt32(input.count), nil, nil)
        guard kr == kIOReturnSuccess else { throw KextError.callFailed(selector: 3, code: kr) }
    }

    public func getCurrentRate(index: UInt32) throws -> (bInterval: UInt8, hz: UInt32) {
        try ensureConnected()

        let input: [UInt64] = [UInt64(index)]
        var outputCount: UInt32 = 2
        var output: [UInt64] = [0, 0]

        let kr = IOConnectCallScalarMethod(connection, 4, input, UInt32(input.count), &output, &outputCount)
        guard kr == kIOReturnSuccess else { throw KextError.callFailed(selector: 4, code: kr) }

        return (bInterval: UInt8(output[0]), hz: UInt32(output[1]))
    }

    private func ensureConnected() throws {
        guard isConnected else { throw KextError.notConnected }
    }
}

// MARK: - Supporting Types

public struct KextDeviceInfo: Sendable {
    public let index: UInt32
    public let vendorID: UInt16
    public let productID: UInt16
    public let originalBInterval: UInt8
    public let currentBInterval: UInt8
    public let usbSpeed: UInt8
    public let isOverridden: Bool
    public let productName: String

    struct RawInfo {
        var index: UInt32 = 0
        var vendorID: UInt16 = 0
        var productID: UInt16 = 0
        var originalBInterval: UInt8 = 0
        var currentBInterval: UInt8 = 0
        var usbSpeed: UInt8 = 0
        var isOverridden: UInt8 = 0
        var productName: (
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8
        ) = (
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        )
    }

    init(raw: RawInfo) {
        self.index = raw.index
        self.vendorID = raw.vendorID
        self.productID = raw.productID
        self.originalBInterval = raw.originalBInterval
        self.currentBInterval = raw.currentBInterval
        self.usbSpeed = raw.usbSpeed
        self.isOverridden = raw.isOverridden != 0

        var nameBytes = raw.productName
        self.productName = withUnsafePointer(to: &nameBytes) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 128) { cStr in
                String(cString: cStr)
            }
        }
    }

    public var vendorIDHex: String { String(format: "0x%04X", vendorID) }
    public var productIDHex: String { String(format: "0x%04X", productID) }

    public var usbSpeedString: String {
        switch usbSpeed {
        case 0: return "Full-Speed"
        case 1: return "High-Speed"
        case 2: return "SuperSpeed"
        default: return "Unknown"
        }
    }

    public var originalHz: UInt32 {
        bIntervalToHz(bInterval: originalBInterval, usbSpeed: usbSpeed)
    }

    public var currentHz: UInt32 {
        bIntervalToHz(bInterval: currentBInterval, usbSpeed: usbSpeed)
    }

    private func bIntervalToHz(bInterval: UInt8, usbSpeed: UInt8) -> UInt32 {
        guard bInterval > 0 else { return 0 }
        if usbSpeed == 0 {
            return 1000 / UInt32(bInterval)
        } else {
            let periodUs = UInt32(1 << (bInterval - 1)) * 125
            return 1_000_000 / periodUs
        }
    }
}

public enum KextError: Error, LocalizedError {
    case serviceNotFound
    case openFailed(IOReturn)
    case notConnected
    case callFailed(selector: UInt32, code: IOReturn)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            return "HidLens KEXT not found. Is it loaded?"
        case .openFailed(let code):
            return "Failed to open KEXT connection (IOReturn: 0x\(String(code, radix: 16)))"
        case .notConnected:
            return "Not connected to KEXT"
        case .callFailed(let selector, let code):
            return "KEXT method \(selector) failed (IOReturn: 0x\(String(code, radix: 16)))"
        }
    }
}
