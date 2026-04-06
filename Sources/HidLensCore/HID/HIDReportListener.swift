import Foundation
import IOKit
import IOKit.hid

public final class HIDReportListener: @unchecked Sendable {
    private var manager: IOHIDManager?
    private var session: MeasurementSession?
    private let converter = TimestampConverter.shared
    private var isListening = false
    private var listenerThread: Thread?
    private var listenerRunLoop: CFRunLoop?
    private let readySemaphore = DispatchSemaphore(value: 0)

    public init() {}

    public func startListening(vendorID: Int, productID: Int, session: MeasurementSession) throws {
        self.session = session

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = mgr

        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            throw HIDError.openFailed(openResult)
        }

        let matching = [[kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as NSDictionary] as NSArray
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matching)

        let thread = Thread { [weak self] in
            guard let self, let mgr = self.manager else { return }

            let rl = CFRunLoopGetCurrent()!
            self.listenerRunLoop = rl

            IOHIDManagerScheduleWithRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.3, false)

            let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>
            let deviceCount = devices?.count ?? 0

            if deviceCount > 0 {
                let context = Unmanaged.passUnretained(self).toOpaque()
                IOHIDManagerRegisterInputReportWithTimeStampCallback(mgr, { ctx, _, _, _, _, _, _, timeStamp in
                    guard let ctx else { return }
                    let listener = Unmanaged<HIDReportListener>.fromOpaque(ctx).takeUnretainedValue()
                    listener.handleReport(timeStamp: timeStamp)
                }, context)

                session.start()
                self.isListening = true
            }

            self.readySemaphore.signal()
            CFRunLoopRun()
        }
        thread.name = "com.hidlens.measurement"
        thread.qualityOfService = .userInteractive
        thread.start()
        listenerThread = thread

        readySemaphore.wait()

        guard isListening else {
            cleanup()
            throw HIDError.deviceNotFound
        }
    }

    public func stopListening() -> MeasurementStatistics {
        guard isListening else { return .empty }
        isListening = false

        let stats = session?.stop() ?? .empty
        session = nil
        cleanup()
        return stats
    }

    public var listening: Bool { isListening }

    private func handleReport(timeStamp: UInt64) {
        guard isListening, let session else { return }
        let nanoseconds = converter.nanoseconds(fromMachTime: timeStamp)
        session.addSample(timestampNanoseconds: nanoseconds)
    }

    private func cleanup() {
        if let mgr = manager {
            IOHIDManagerRegisterInputReportWithTimeStampCallback(mgr, { _, _, _, _, _, _, _, _ in }, nil)

            if let rl = listenerRunLoop {
                IOHIDManagerUnscheduleFromRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
                CFRunLoopStop(rl)
            }
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        manager = nil
        listenerRunLoop = nil
        listenerThread = nil
    }
}
