#!/usr/bin/env swift
import IOKit
import IOKit.hid
import Foundation

var timestamps: [UInt64] = []
let startTime = Date()

func callback(_ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ value: IOHIDValue) {
    let ts = IOHIDValueGetTimeStamp(value)
    timestamps.append(ts)
    if timestamps.count % 100 == 0 {
        print("  ... \(timestamps.count) samples")
    }
}

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerOpen(mgr, 0)

let matching = [[kIOHIDVendorIDKey: 0x054C, kIOHIDProductIDKey: 0x09CC] as NSDictionary] as NSArray
IOHIDManagerSetDeviceMatchingMultiple(mgr, matching)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

// Check devices
CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.2, false)
let deviceSet = IOHIDManagerCopyDevices(mgr)
let count = (deviceSet as? Set<AnyHashable>)?.count ?? 0
print("Devices matched: \(count)")

if count == 0 {
    print("No DS4 found!")
    exit(1)
}

// Register callback
IOHIDManagerRegisterInputValueCallback(mgr, callback, nil)

print("Measuring for 3 seconds... MOVE THE ANALOG STICKS!")
print("")

// Run the loop for 3 seconds
let endTime = CFAbsoluteTimeGetCurrent() + 3.0
while CFAbsoluteTimeGetCurrent() < endTime {
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
}

IOHIDManagerRegisterInputValueCallback(mgr, nil, nil)
IOHIDManagerClose(mgr, 0)

print("")
print("Total samples: \(timestamps.count)")

if timestamps.count > 2 {
    // Calculate intervals
    var intervals: [Double] = []
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)

    for i in 1..<timestamps.count {
        let diff = timestamps[i] - timestamps[i-1]
        let ns = Double(diff) * Double(info.numer) / Double(info.denom)
        intervals.append(ns)
    }

    // Remove duplicates (same timestamp = same report, multiple elements)
    let uniqueIntervals = intervals.filter { $0 > 100_000 } // >0.1ms

    if !uniqueIntervals.isEmpty {
        let avgNs = uniqueIntervals.reduce(0, +) / Double(uniqueIntervals.count)
        let avgHz = 1_000_000_000.0 / avgNs
        let minNs = uniqueIntervals.min()!
        let maxNs = uniqueIntervals.max()!

        print("Unique intervals: \(uniqueIntervals.count)")
        print("Average: \(String(format: "%.1f", avgHz)) Hz")
        print("Avg interval: \(String(format: "%.1f", avgNs / 1000)) µs")
        print("Min interval: \(String(format: "%.1f", minNs / 1000)) µs")
        print("Max interval: \(String(format: "%.1f", maxNs / 1000)) µs")
    } else {
        print("No valid intervals found")
    }
} else {
    print("Not enough samples")
}
