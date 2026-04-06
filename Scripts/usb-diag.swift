#!/usr/bin/env swift
// USB Descriptor Diagnostic — reads DS4 config descriptor from userspace
import IOKit
import IOKit.usb
import Foundation

let kIOUSBHostDeviceClassName = "IOUSBHostDevice"

func findDS4() -> io_service_t {
    let matching = IOServiceMatching(kIOUSBHostDeviceClassName) as NSMutableDictionary
    matching["idVendor"] = 0x054C   // Sony
    matching["idProduct"] = 0x09CC  // DS4 v2

    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard kr == KERN_SUCCESS else {
        print("ERROR: IOServiceGetMatchingServices failed: \(kr)")
        return 0
    }
    defer { IOObjectRelease(iterator) }

    let service = IOIteratorNext(iterator)
    if service == 0 {
        print("ERROR: DS4 not found in IORegistry")
    }
    return service
}

func dumpProperties(_ service: io_service_t) {
    var props: Unmanaged<CFMutableDictionary>?
    IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
    guard let dict = props?.takeRetainedValue() as? [String: Any] else { return }

    print("=== DS4 IORegistry Properties ===")
    for key in ["USB Product Name", "idVendor", "idProduct", "Device Speed",
                "bDeviceClass", "bNumConfigurations", "sessionID",
                "kUSBCurrentConfiguration"] {
        if let val = dict[key] {
            print("  \(key) = \(val)")
        }
    }
}

func readConfigDescriptor(_ service: io_service_t) {
    // Open a connection to read descriptors
    var conn: io_connect_t = 0

    // Try to get config descriptor from IORegistry property
    var props: Unmanaged<CFMutableDictionary>?
    IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
    guard let dict = props?.takeRetainedValue() as? [String: Any] else {
        print("ERROR: Cannot read properties")
        return
    }

    // Check for configuration descriptor data
    if let configData = dict["kUSBConfigurationDescriptorOverride"] as? Data {
        print("\nConfig descriptor override: \(configData.count) bytes")
        dumpDescriptorData(configData)
    }

    // Look for child interfaces and their properties
    print("\n=== Child Interfaces ===")
    var childIter: io_iterator_t = 0
    IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIter)
    defer { IOObjectRelease(childIter) }

    var child = IOIteratorNext(childIter)
    while child != 0 {
        var childProps: Unmanaged<CFMutableDictionary>?
        IORegistryEntryCreateCFProperties(child, &childProps, kCFAllocatorDefault, 0)
        if let cDict = childProps?.takeRetainedValue() as? [String: Any] {
            let ifClass = cDict["bInterfaceClass"] as? Int ?? -1
            let ifNum = cDict["bInterfaceNumber"] as? Int ?? -1
            let ifSub = cDict["bInterfaceSubClass"] as? Int ?? -1
            let eps = cDict["bNumEndpoints"] as? Int ?? -1
            var className = ""
            var buf = [CChar](repeating: 0, count: 256)
            IOObjectGetClass(child, &buf)
            className = String(cString: buf)

            print("  Interface \(ifNum): class=\(ifClass) subclass=\(ifSub) endpoints=\(eps) [\(className)]")

            if ifClass == 3 {
                print("    ^^^ THIS IS THE HID INTERFACE ^^^")
                // Dump all properties for HID interface
                for (k, v) in cDict.sorted(by: { $0.key < $1.key }) {
                    if k.contains("ndpoint") || k.contains("Interval") || k.contains("ddress") ||
                       k.contains("Attributes") || k.contains("MaxPacket") {
                        print("    \(k) = \(v)")
                    }
                }
            }
        }
        IOObjectRelease(child)
        child = IOIteratorNext(childIter)
    }
}

// Check HidLensDriver status
func checkHidLensDriver() {
    print("\n=== HidLensDriver Status ===")
    let matching = IOServiceMatching("HidLensDriver")
    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    if kr != KERN_SUCCESS {
        print("  Not found in IORegistry")
        return
    }
    defer { IOObjectRelease(iterator) }

    let service = IOIteratorNext(iterator)
    if service == 0 {
        print("  KEXT loaded but no device matched")
        return
    }
    defer { IOObjectRelease(service) }

    print("  KEXT matched! Service ID: \(service)")

    // Try to open UserClient
    var conn: io_connect_t = 0
    let openResult = IOServiceOpen(service, mach_task_self_, 0, &conn)
    print("  IOServiceOpen: 0x\(String(openResult, radix: 16)) (\(openResult == 0 ? "OK" : "FAILED"))")

    if openResult == 0 {
        // GetDeviceCount
        var outputCount: UInt32 = 1
        var output: [UInt64] = [0]
        let callResult = IOConnectCallScalarMethod(conn, 0, nil, 0, &output, &outputCount)
        print("  DeviceCount: \(output[0]) (result: 0x\(String(callResult, radix: 16)))")

        if output[0] > 0 {
            // GetCurrentRate
            let input: [UInt64] = [0]
            var rateOutput: [UInt64] = [0, 0]
            var rateCount: UInt32 = 2
            let rateResult = IOConnectCallScalarMethod(conn, 4, input, 1, &rateOutput, &rateCount)
            print("  CurrentRate: bInterval=\(rateOutput[0]) Hz=\(rateOutput[1]) (result: 0x\(String(rateResult, radix: 16)))")
        }

        IOServiceClose(conn)
    }
}

// Main
print("USB Descriptor Diagnostic for DualShock 4\n")

let ds4 = findDS4()
guard ds4 != 0 else { exit(1) }
defer { IOObjectRelease(ds4) }

dumpProperties(ds4)
readConfigDescriptor(ds4)
checkHidLensDriver()

func dumpDescriptorData(_ data: Data) {
    var offset = 0
    while offset < data.count {
        let len = Int(data[offset])
        let type = Int(data[offset + 1])
        if len == 0 { break }
        let chunk = data[offset..<min(offset+len, data.count)]
        print("  [\(offset)] type=\(type) len=\(len): \(chunk.map { String(format: "%02X", $0) }.joined(separator: " "))")
        offset += len
    }
}
