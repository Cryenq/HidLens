#!/usr/bin/env swift
// USB Reconfigure — Forces the xHCI to rebuild endpoint pipes
// by cycling SET_CONFIGURATION from userspace with USBDeviceOpenSeize.
// Must run AFTER the KEXT has patched bInterval in the cached descriptor.

import IOKit
import IOKit.usb
import Foundation

let DS4_VID: Int = 0x054C
let DS4_PID: Int = 0x09CC

func findDS4Device() -> io_service_t {
    let matchDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
    matchDict[kUSBVendorID] = DS4_VID
    matchDict[kUSBProductID] = DS4_PID

    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
    guard kr == KERN_SUCCESS else {
        print("Error finding USB device: \(kr)")
        return 0
    }

    let service = IOIteratorNext(iterator)
    IOObjectRelease(iterator)
    return service
}

func reconfigureDevice(_ service: io_service_t) -> Bool {
    var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
    var score: Int32 = 0

    let kr = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugInInterface,
        &score
    )

    guard kr == KERN_SUCCESS, let plugin = plugInInterface?.pointee?.pointee else {
        print("Error creating plugin interface: \(String(format: "0x%08X", kr))")
        return false
    }

    // Query for IOUSBDeviceInterface
    var deviceInterfacePtr: UnsafeMutableRawPointer?
    var usbDeviceID = kIOUSBDeviceInterfaceID197
    let result = withUnsafeMutablePointer(to: &usbDeviceID) { idPtr -> HRESULT in
        return plugin.QueryInterface(
            plugInInterface,
            CFUUIDGetUUIDBytes(idPtr.pointee),
            &deviceInterfacePtr
        )
    }

    // Release plugin
    _ = plugin.Release(plugInInterface)

    guard result == S_OK, let devPtr = deviceInterfacePtr else {
        print("Error getting device interface: \(result)")
        return false
    }

    let device = devPtr.assumingMemoryBound(
        to: UnsafeMutablePointer<IOUSBDeviceInterface197>.self
    ).pointee.pointee
    let devRef = devPtr.assumingMemoryBound(
        to: UnsafeMutablePointer<IOUSBDeviceInterface197>.self
    )

    // Try to seize the device from the kernel HID driver
    print("Opening device with seize...")
    var openResult = device.USBDeviceOpenSeize(devRef.pointee)
    if openResult != kIOReturnSuccess {
        print("USBDeviceOpenSeize failed: \(String(format: "0x%08X", openResult))")
        print("Trying normal open...")
        openResult = device.USBDeviceOpen(devRef.pointee)
        if openResult != kIOReturnSuccess {
            print("Normal open also failed: \(String(format: "0x%08X", openResult))")
            return false
        }
    }
    print("Device opened successfully!")

    // Get current configuration
    var configNum: UInt8 = 0
    var getResult = device.GetConfiguration(devRef.pointee, &configNum)
    print("Current configuration: \(configNum) (result: \(String(format: "0x%08X", getResult)))")

    // Cycle: set config 0 (unconfigured) then back to original
    print("Setting configuration 0 (unconfigured)...")
    var setResult = device.SetConfiguration(devRef.pointee, 0)
    print("SetConfiguration(0) result: \(String(format: "0x%08X", setResult))")

    usleep(100_000) // 100ms pause

    let targetConfig: UInt8 = configNum > 0 ? configNum : 1
    print("Setting configuration \(targetConfig)...")
    setResult = device.SetConfiguration(devRef.pointee, targetConfig)
    print("SetConfiguration(\(targetConfig)) result: \(String(format: "0x%08X", setResult))")

    // Close device — HID driver should re-match
    print("Closing device...")
    device.USBDeviceClose(devRef.pointee)

    // Release
    _ = device.Release(devRef.pointee)

    print("Done! HID driver should re-match with patched bInterval.")
    return setResult == kIOReturnSuccess
}

// Main
print("USB Reconfigure for DS4 (VID=\(String(format: "0x%04X", DS4_VID)) PID=\(String(format: "0x%04X", DS4_PID)))")
print("")

let service = findDS4Device()
guard service != 0 else {
    print("DS4 controller not found! Make sure it's plugged in via USB.")
    exit(1)
}
print("Found DS4 device (service: \(service))")

if reconfigureDevice(service) {
    print("\nSUCCESS — now measure with: swift Scripts/measure-detailed.swift")
} else {
    print("\nFAILED — see errors above")
}

IOObjectRelease(service)
