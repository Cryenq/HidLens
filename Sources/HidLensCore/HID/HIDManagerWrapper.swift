import Foundation
import IOKit
import IOKit.hid

public final class HIDManagerWrapper: @unchecked Sendable {
    private let manager: IOHIDManager
    private var runLoopThread: Thread?
    private var runLoop: CFRunLoop?
    private let readySemaphore = DispatchSemaphore(value: 0)

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        close()
    }

    public func open() throws {
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw HIDError.openFailed(result)
        }

        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            IOHIDManagerScheduleWithRunLoop(self.manager, self.runLoop!, CFRunLoopMode.defaultMode.rawValue)
            self.readySemaphore.signal()
            CFRunLoopRun()
        }
        thread.name = "com.hidlens.hid-runloop"
        thread.qualityOfService = .userInteractive
        thread.start()
        runLoopThread = thread

        readySemaphore.wait()
    }

    public func close() {
        if let rl = runLoop {
            IOHIDManagerUnscheduleFromRunLoop(manager, rl, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopStop(rl)
            runLoop = nil
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        runLoopThread = nil
    }

    public func setDeviceMatching(_ criteria: [[String: Any]]) {
        let cfArray = criteria.map { $0 as CFDictionary } as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, cfArray)
    }

    public func copyDevices() -> Set<IOHIDDevice> {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }
        return devices
    }

    public func registerInputValueCallback(_ callback: @escaping IOHIDValueCallback, context: UnsafeMutableRawPointer?) {
        IOHIDManagerRegisterInputValueCallback(manager, callback, context)
    }

    public func unregisterInputValueCallback() {
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
    }

    public func registerInputReportWithTimeStampCallback(_ callback: @escaping IOHIDReportWithTimeStampCallback, context: UnsafeMutableRawPointer?) {
        IOHIDManagerRegisterInputReportWithTimeStampCallback(manager, callback, context)
    }

    public func unregisterInputReportWithTimeStampCallback() {
        IOHIDManagerRegisterInputReportWithTimeStampCallback(manager, { _, _, _, _, _, _, _, _ in }, nil)
    }

    public func registerDeviceCallbacks(
        matched: @escaping IOHIDDeviceCallback,
        removed: @escaping IOHIDDeviceCallback,
        context: UnsafeMutableRawPointer?
    ) {
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removed, context)
    }

    public var rawManager: IOHIDManager { manager }
}

public enum HIDError: Error, LocalizedError {
    case openFailed(IOReturn)
    case deviceNotFound
    case measurementFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let code):
            return "Failed to open HID manager (IOReturn: 0x\(String(code, radix: 16)))"
        case .deviceNotFound:
            return "HID device not found"
        case .measurementFailed(let reason):
            return "Measurement failed: \(reason)"
        }
    }
}
