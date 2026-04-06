#!/usr/bin/env swift
// Detailed measurement — shows interval distribution to identify bottleneck
import IOKit
import IOKit.hid
import Foundation

var timestamps: [UInt64] = []

func callback(_ ctx: UnsafeMutableRawPointer?, _ r: IOReturn, _ s: UnsafeMutableRawPointer?, _ v: IOHIDValue) {
    timestamps.append(IOHIDValueGetTimeStamp(v))
}

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerOpen(mgr, 0)
let matching = [[kIOHIDVendorIDKey: 0x054C, kIOHIDProductIDKey: 0x09CC] as NSDictionary] as NSArray
IOHIDManagerSetDeviceMatchingMultiple(mgr, matching)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.3, false)
IOHIDManagerRegisterInputValueCallback(mgr, callback, nil)

print("Measuring 5 seconds... MOVE ANALOG STICKS!\n")
let end = CFAbsoluteTimeGetCurrent() + 5.0
while CFAbsoluteTimeGetCurrent() < end {
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
}
IOHIDManagerRegisterInputValueCallback(mgr, nil, nil)
IOHIDManagerClose(mgr, 0)

var info = mach_timebase_info_data_t()
mach_timebase_info(&info)

// Compute unique intervals
var intervals: [Double] = []
for i in 1..<timestamps.count {
    let diff = timestamps[i] - timestamps[i-1]
    let us = Double(diff) * Double(info.numer) / Double(info.denom) / 1000.0
    if us > 100 { intervals.append(us) } // filter sub-0.1ms duplicates
}

guard !intervals.isEmpty else { print("No data"); exit(1) }

let sorted = intervals.sorted()
let avgUs = intervals.reduce(0, +) / Double(intervals.count)
let avgHz = 1_000_000.0 / avgUs

print("Total unique intervals: \(intervals.count)")
print("Average: \(String(format: "%.1f", avgHz)) Hz (\(String(format: "%.0f", avgUs)) µs)")
print("Median:  \(String(format: "%.1f", 1_000_000.0 / sorted[sorted.count/2])) Hz (\(String(format: "%.0f", sorted[sorted.count/2])) µs)")
print("p1:      \(String(format: "%.0f", sorted[max(0, sorted.count/100)])) µs")
print("p5:      \(String(format: "%.0f", sorted[max(0, sorted.count*5/100)])) µs")
print("p50:     \(String(format: "%.0f", sorted[sorted.count/2])) µs")
print("p95:     \(String(format: "%.0f", sorted[sorted.count*95/100])) µs")
print("p99:     \(String(format: "%.0f", sorted[min(sorted.count-1, sorted.count*99/100)])) µs")
print("Min:     \(String(format: "%.0f", sorted.first!)) µs (\(String(format: "%.0f", 1_000_000.0 / sorted.first!)) Hz)")
print("Max:     \(String(format: "%.0f", sorted.last!)) µs")

// Histogram: show distribution
print("\nInterval Distribution:")
let buckets: [(String, Double, Double)] = [
    ("<1ms  (>1000Hz)", 0, 1000),
    ("1-1.5ms (666-1000Hz)", 1000, 1500),
    ("1.5-2ms (500-666Hz)", 1500, 2000),
    ("2-3ms   (333-500Hz)", 2000, 3000),
    ("3-4ms   (250-333Hz)", 3000, 4000),
    ("4-5ms   (200-250Hz)", 4000, 5000),
    (">5ms    (<200Hz)", 5000, 100000)
]
for (label, lo, hi) in buckets {
    let count = intervals.filter { $0 >= lo && $0 < hi }.count
    let pct = Double(count) / Double(intervals.count) * 100
    let bar = String(repeating: "█", count: Int(pct / 2))
    print("  \(label): \(String(format: "%5d", count)) (\(String(format: "%5.1f", pct))%) \(bar)")
}
