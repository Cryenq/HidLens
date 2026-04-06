import Foundation
import IOKit
import IOKit.hid

public enum HIDDescriptorParser {

    public static func rawDescriptor(from device: IOHIDDevice) -> Data? {
        guard let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) else {
            return nil
        }
        if let data = descriptor as? Data {
            return data
        }
        return nil
    }

    public static func hexDump(_ data: Data, bytesPerLine: Int = 16) -> String {
        var lines: [String] = []
        for offset in stride(from: 0, to: data.count, by: bytesPerLine) {
            let end = min(offset + bytesPerLine, data.count)
            let slice = data[offset..<end]
            let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
            let offsetStr = String(format: "%04X", offset)
            lines.append("\(offsetStr): \(hex)")
        }
        return lines.joined(separator: "\n")
    }
}
