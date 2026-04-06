#!/usr/bin/env swift
// Precise polling rate measurement
// Uses InputReportWithTimeStampCallback: 1 callback per USB poll + hardware timestamp
import IOKit
import IOKit.hid
import Foundation

var timestamps: [UInt64] = []

// This callback fires once per HID report with the USB hardware timestamp
func reportCallback(_ ctx: UnsafeMutableRawPointer?, _ result: IOReturn,
                    _ sender: UnsafeMutableRawPointer?, _ type: IOHIDReportType,
                    _ reportID: UInt32, _ report: UnsafeMutablePointer<UInt8>,
                    _ reportLength: CFIndex, _ timeStamp: UInt64) {
    timestamps.append(timeStamp)
}

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerOpen(mgr, 0)
let matching = [[kIOHIDVendorIDKey: 0x054C, kIOHIDProductIDKey: 0x09CC] as NSDictionary] as NSArray
IOHIDManagerSetDeviceMatchingMultiple(mgr, matching)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.5, false)

IOHIDManagerRegisterInputReportWithTimeStampCallback(mgr, reportCallback, nil)

let duration = 10.0
print("Precise measurement — \(Int(duration))s — MOVE ANALOG STICKS!\n")
let end = CFAbsoluteTimeGetCurrent() + duration
while CFAbsoluteTimeGetCurrent() < end {
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.001, false)
}
// Unregister by re-registering a no-op callback
func noopCallback(_ ctx: UnsafeMutableRawPointer?, _ result: IOReturn,
                  _ sender: UnsafeMutableRawPointer?, _ type: IOHIDReportType,
                  _ reportID: UInt32, _ report: UnsafeMutablePointer<UInt8>,
                  _ reportLength: CFIndex, _ timeStamp: UInt64) {}
IOHIDManagerRegisterInputReportWithTimeStampCallback(mgr, noopCallback, nil)
IOHIDManagerClose(mgr, 0)

var info = mach_timebase_info_data_t()
mach_timebase_info(&info)

var intervals: [Double] = []
for i in 1..<timestamps.count {
    let diff = timestamps[i] - timestamps[i-1]
    let us = Double(diff) * Double(info.numer) / Double(info.denom) / 1000.0
    intervals.append(us)
}

guard !intervals.isEmpty else { print("No data — is the controller connected via USB?"); exit(1) }

let sorted = intervals.sorted()
let count = intervals.count
let avgUs = intervals.reduce(0, +) / Double(count)
let avgHz = 1_000_000.0 / avgUs

let variance = intervals.map { ($0 - avgUs) * ($0 - avgUs) }.reduce(0, +) / Double(count)
let stddev = sqrt(variance)
let jitterPct = (stddev / avgUs) * 100.0

var consecJitter: [Double] = []
for i in 1..<intervals.count {
    consecJitter.append(abs(intervals[i] - intervals[i-1]))
}
let avgConsecJitter = consecJitter.isEmpty ? 0 : consecJitter.reduce(0, +) / Double(consecJitter.count)

print("═══════════════════════════════════════════════════")
print("  POLLING RATE — \(count) reports in \(Int(duration))s")
print("  (Hardware timestamps, 1 per USB poll)")
print("═══════════════════════════════════════════════════")
print("")
print("  Average:      \(String(format: "%7.1f", avgHz)) Hz   (\(String(format: "%.1f", avgUs)) µs)")
print("  Median:       \(String(format: "%7.1f", 1_000_000.0 / sorted[count/2])) Hz   (\(String(format: "%.1f", sorted[count/2])) µs)")
print("  Min interval: \(String(format: "%7.1f", sorted.first!)) µs  (\(String(format: "%.0f", 1_000_000.0 / sorted.first!)) Hz)")
print("  Max interval: \(String(format: "%7.1f", sorted.last!)) µs  (\(String(format: "%.0f", 1_000_000.0 / sorted.last!)) Hz)")
print("")
print("  Std Dev:      \(String(format: "%6.1f", stddev)) µs")
print("  Jitter:       \(String(format: "%5.2f", jitterPct))%")
print("  Avg poll-to-poll jitter: \(String(format: "%.1f", avgConsecJitter)) µs")
print("")

// Percentiles
print("  ┌─ Percentiles ─────────────────────────────────")
for p in [1, 5, 10, 25, 50, 75, 90, 95, 99] {
    let idx = min(count - 1, count * p / 100)
    let us = sorted[idx]
    print("  │ p\(String(format: "%-2d", p)):  \(String(format: "%7.1f", 1_000_000.0 / us)) Hz   (\(String(format: "%7.1f", us)) µs)")
}
print("  └───────────────────────────────────────────────")

// Fine-grained histogram around 1ms
print("")
print("  ┌─ Interval Distribution ───────────────────────")
let fineBuckets: [(String, Double, Double)] = [
    ("   <500 µs", 0, 500),
    (" 500-750 µs", 500, 750),
    (" 750-900 µs", 750, 900),
    (" 900-950 µs", 900, 950),
    (" 950-975 µs", 950, 975),
    ("975-1000 µs", 975, 1000),
    ("   1000  µs", 1000, 1001),
    ("1000-1025µs", 1001, 1025),
    ("1025-1050µs", 1025, 1050),
    ("1050-1100µs", 1050, 1100),
    ("1100-1250µs", 1100, 1250),
    ("1250-1500µs", 1250, 1500),
    ("1500-2000µs", 1500, 2000),
    ("   >2000 µs", 2000, 999999)
]
let maxN = fineBuckets.map { b in intervals.filter { $0 >= b.1 && $0 < b.2 }.count }.max() ?? 1
for (label, lo, hi) in fineBuckets {
    let n = intervals.filter { $0 >= lo && $0 < hi }.count
    if n == 0 { continue }
    let pct = Double(n) / Double(count) * 100
    let barLen = Int(Double(n) / Double(max(1, maxN)) * 25.0)
    let bar = String(repeating: "█", count: max(1, barLen))
    print("  │ \(label): \(String(format: "%5d", n)) (\(String(format: "%5.1f", pct))%) \(bar)")
}
print("  └───────────────────────────────────────────────")

// Consistency
let within25 = intervals.filter { abs($0 - 1000.0) <= 25.0 }.count
let within50 = intervals.filter { abs($0 - 1000.0) <= 50.0 }.count
print("")
print("  Consistency (±25µs of 1ms): \(String(format: "%.1f", Double(within25) / Double(count) * 100))%")
print("  Consistency (±50µs of 1ms): \(String(format: "%.1f", Double(within50) / Double(count) * 100))%")
print("")
