#!/usr/bin/env swift
// Read raw USB config descriptor for DS4 via IOUSBHostDevice
import IOKit
import IOKit.usb
import Foundation

// Find DS4 device
let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
matching["idVendor"] = 0x054C
matching["idProduct"] = 0x09CC
var iterator: io_iterator_t = 0
IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
let service = IOIteratorNext(iterator)
guard service != 0 else { print("DS4 not found"); exit(1) }

// Open DeviceInterface to read descriptors
var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
var score: Int32 = 0
let kr = IOCreatePlugInInterfaceForService(
    service,
    kIOUSBDeviceUserClientTypeID,
    kIOCFPlugInInterfaceID,
    &plugInInterface,
    &score
)

if kr == KERN_SUCCESS, let plugIn = plugInInterface?.pointee?.pointee {
    print("Got plugin interface")

    // Get USB device interface
    var deviceInterfacePtr: UnsafeMutableRawPointer?
    let usbDeviceInterfaceID = CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID650)
    let qResult = plugIn.QueryInterface(
        plugInInterface,
        usbDeviceInterfaceID,
        &deviceInterfacePtr
    )

    if qResult == 0, let devPtr = deviceInterfacePtr {
        let deviceInterface = devPtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBDeviceInterface650>.self
        ).pointee.pointee

        // Open device
        let openResult = deviceInterface.USBDeviceOpen(devPtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBDeviceInterface650>.self
        ))
        print("USBDeviceOpen: \(openResult)")

        // Get config descriptor
        var configDesc: IOUSBConfigurationDescriptorPtr?
        let configResult = deviceInterface.GetConfigurationDescriptorPtr(
            devPtr.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface650>.self),
            0,
            &configDesc
        )
        print("GetConfigurationDescriptorPtr: \(configResult)")

        if let desc = configDesc {
            let totalLength = Int(desc.pointee.wTotalLength)
            print("Config descriptor: totalLength=\(totalLength) numInterfaces=\(desc.pointee.bNumInterfaces)")

            // Dump raw bytes
            let rawPtr = UnsafeRawPointer(desc)
            let data = Data(bytes: rawPtr, count: totalLength)

            // Parse descriptors
            var offset = 0
            while offset < data.count {
                let len = Int(data[offset])
                if len == 0 { break }
                let type = Int(data[offset + 1])

                switch type {
                case 4: // Interface
                    let ifNum = data[offset + 2]
                    let ifClass = data[offset + 5]
                    let ifSub = data[offset + 6]
                    let numEp = data[offset + 4]
                    print("  INTERFACE \(ifNum): class=\(ifClass) sub=\(ifSub) endpoints=\(numEp)")
                case 5: // Endpoint
                    let addr = data[offset + 2]
                    let attr = data[offset + 3]
                    let maxPacket = UInt16(data[offset + 4]) | (UInt16(data[offset + 5]) << 8)
                    let bInterval = data[offset + 6]
                    let dir = (addr & 0x80) != 0 ? "IN" : "OUT"
                    let xferType = ["Control", "Isochronous", "Bulk", "Interrupt"][Int(attr & 0x03)]
                    print("    ENDPOINT 0x\(String(format: "%02X", addr)) \(dir) \(xferType) maxPacket=\(maxPacket) bInterval=\(bInterval)")
                case 33: // HID
                    print("  HID descriptor (len=\(len))")
                default:
                    break
                }
                offset += len
            }
        }

        deviceInterface.USBDeviceClose(devPtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBDeviceInterface650>.self
        ))
    }

    IODestroyPlugInInterface(plugInInterface)
} else {
    print("Failed to create plugin: \(kr)")
    // Fallback: try to read from IORegistry properties
    print("\nFallback: reading from IORegistry...")
    var props: Unmanaged<CFMutableDictionary>?
    IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
    if let dict = props?.takeRetainedValue() as? [String: Any] {
        for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
            if k.lowercased().contains("config") || k.lowercased().contains("descriptor") {
                print("  \(k) = \(v)")
            }
        }
    }
}

IOObjectRelease(service)
IOObjectRelease(iterator)
