import Foundation
import IOKit
import IOKit.hid

public final class HIDDeviceMonitor: @unchecked Sendable {
    private var manager: IOHIDManager?
    private var onChange: (() -> Void)?
    private var isRunning = false
    private var monitorThread: Thread?
    private var monitorRunLoop: CFRunLoop?
    private let readySemaphore = DispatchSemaphore(value: 0)

    public init() {}

    deinit {
        stop()
    }

    public func start(onChange: @escaping () -> Void) {
        guard !isRunning else { return }
        self.onChange = onChange
        isRunning = true

        let thread = Thread { [weak self] in
            guard let self else { return }

            let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = mgr

            IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

            let matchingCriteria: [[String: Any]] = [
                [kIOHIDVendorIDKey as String: 0x054C, kIOHIDProductIDKey as String: 0x05C4],
                [kIOHIDVendorIDKey as String: 0x054C, kIOHIDProductIDKey as String: 0x09CC],
                [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                 kIOHIDDeviceUsageKey as String: kHIDUsage_GD_GamePad],
                [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                 kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Joystick]
            ]
            let cfArray = matchingCriteria.map { $0 as CFDictionary } as CFArray
            IOHIDManagerSetDeviceMatchingMultiple(mgr, cfArray)

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, _ in
                guard let ctx else { return }
                let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(ctx).takeUnretainedValue()
                monitor.notifyChange()
            }, context)
            IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, _ in
                guard let ctx else { return }
                let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(ctx).takeUnretainedValue()
                monitor.notifyChange()
            }, context)

            self.monitorRunLoop = CFRunLoopGetCurrent()
            IOHIDManagerScheduleWithRunLoop(mgr, self.monitorRunLoop!, CFRunLoopMode.defaultMode.rawValue)

            self.readySemaphore.signal()
            CFRunLoopRun()
        }
        thread.name = "com.hidlens.device-monitor"
        thread.qualityOfService = .utility
        thread.start()
        monitorThread = thread

        readySemaphore.wait()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let mgr = manager, let rl = monitorRunLoop {
            IOHIDManagerUnscheduleFromRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopStop(rl)
        }

        manager = nil
        monitorRunLoop = nil
        monitorThread = nil
        onChange = nil
    }

    private func notifyChange() {
        guard isRunning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.onChange?()
        }
    }
}
