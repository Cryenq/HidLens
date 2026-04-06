import HidLensCore

enum TableFormatter {

    static func deviceTable(_ devices: [HIDDeviceInfo], kextAvailable: Bool) -> String {
        var lines: [String] = []

        // Header
        lines.append(formatRow("#", "Name", "VID", "PID", "Transport", "Profile"))
        lines.append(String(repeating: "─", count: 90))

        for (i, device) in devices.enumerated() {
            let profile = ControllerProfile.find(vendorID: device.vendorID, productID: device.productID)
            let profileStr = profile.map { "\($0.name) (\($0.defaultHz)Hz)" } ?? ""

            lines.append(formatRow(
                "\(i)",
                String(device.displayName.prefix(30)),
                device.vendorIDHex,
                device.productIDHex,
                device.transport ?? "N/A",
                profileStr
            ))
        }

        lines.append("")
        lines.append("Use 'hidlens inspect <registry-id>' for detailed info.")
        lines.append("Registry IDs:")
        for device in devices {
            lines.append("  \(device.displayName): \(device.id)")
        }

        return lines.joined(separator: "\n")
    }

    private static func formatRow(_ col1: String, _ col2: String, _ col3: String,
                                   _ col4: String, _ col5: String, _ col6: String) -> String {
        let c1 = col1.padding(toLength: 4, withPad: " ", startingAt: 0)
        let c2 = col2.padding(toLength: 30, withPad: " ", startingAt: 0)
        let c3 = col3.padding(toLength: 10, withPad: " ", startingAt: 0)
        let c4 = col4.padding(toLength: 10, withPad: " ", startingAt: 0)
        let c5 = col5.padding(toLength: 12, withPad: " ", startingAt: 0)
        return "\(c1)  \(c2)  \(c3)  \(c4)  \(c5)  \(col6)"
    }
}
