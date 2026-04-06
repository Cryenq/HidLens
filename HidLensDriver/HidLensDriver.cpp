#include "HidLensDriver.h"
#include "HidLensUserClient.h"
#include <IOKit/IOLib.h>
#include <os/log.h>
#include <mach/mach_types.h>
#include <libkern/OSKextLib.h>

#define LOG_PREFIX "HidLens: "
#define HLOG(fmt, ...) IOLog(LOG_PREFIX fmt "\n", ##__VA_ARGS__)

// KEXT module entry points — required for _kmod_info symbol
extern kern_return_t HidLensDriver_start(kmod_info_t *ki, void *data);
extern kern_return_t HidLensDriver_stop(kmod_info_t *ki, void *data);

__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(com.hidlens.driver, "1.0.2", HidLensDriver_start, HidLensDriver_stop)

kern_return_t HidLensDriver_start(kmod_info_t *ki, void *data) {
    return KERN_SUCCESS;
}

kern_return_t HidLensDriver_stop(kmod_info_t *ki, void *data) {
    return KERN_SUCCESS;
}

// Static device registry
HidLensDriver *HidLensDriver::sDeviceRegistry[kHidLensMaxDevices] = {};
uint32_t HidLensDriver::sDeviceCount = 0;

OSDefineMetaClassAndStructors(HidLensDriver, IOService)

// ---------------------------------------------------------------------------
// IOService Lifecycle
// ---------------------------------------------------------------------------

bool HidLensDriver::init(OSDictionary *dictionary) {
    if (!IOService::init(dictionary)) {
        return false;
    }

    fInterface = nullptr;
    fDevice = nullptr;
    fOriginalBInterval = 0;
    fCurrentBInterval = 0;
    fUSBSpeed = 0;
    fEndpointAddress = 0;
    fIsOverridden = false;
    fCachedEndpointDesc = nullptr;
    fVendorID = 0;
    fProductID = 0;
    fRegistryIndex = UINT32_MAX;
    memset(fProductName, 0, sizeof(fProductName));

    HLOG("init");
    return true;
}

void HidLensDriver::free() {
    HLOG("free");

    if (fRegistryIndex < kHidLensMaxDevices) {
        sDeviceRegistry[fRegistryIndex] = nullptr;
    }

    IOService::free();
}

IOService *HidLensDriver::probe(IOService *provider, SInt32 *score) {
    IOService *result = IOService::probe(provider, score);
    if (!result) {
        return nullptr;
    }

    IOUSBHostDevice *device = OSDynamicCast(IOUSBHostDevice, provider);
    if (!device) {
        HLOG("probe: provider is not IOUSBHostDevice");
        return nullptr;
    }

    const DeviceDescriptor *devDesc = device->getDeviceDescriptor();
    if (!devDesc) {
        HLOG("probe: cannot get device descriptor");
        return nullptr;
    }

    uint16_t vid = USBToHost16(devDesc->idVendor);
    uint16_t pid = USBToHost16(devDesc->idProduct);

    HLOG("probe: matched device VID=0x%04X PID=0x%04X", vid, pid);

    // Try early patch in probe() — even earlier than start()
    const ConfigurationDescriptor *cd = device->getConfigurationDescriptor();
    HLOG("probe: configDesc=%p", cd);
    if (cd) {
        const Descriptor *hdr = nullptr;
        bool inHID = false;
        while ((hdr = getNextDescriptor(cd, hdr))) {
            if (hdr->bDescriptorType == StandardUSB::kDescriptorTypeInterface) {
                const InterfaceDescriptor *ifd = (const InterfaceDescriptor *)hdr;
                inHID = (ifd->bInterfaceClass == 3);
            }
            if (inHID && hdr->bDescriptorType == StandardUSB::kDescriptorTypeEndpoint) {
                const EndpointDescriptor *ep = (const EndpointDescriptor *)hdr;
                if ((ep->bEndpointAddress & 0x80) && (ep->bmAttributes & 0x03) == kIOUSBEndpointTypeInterrupt) {
                    HLOG("probe: EARLY-PATCH ep 0x%02X bInterval %d -> 1", ep->bEndpointAddress, ep->bInterval);
                    EndpointDescriptor *mep = const_cast<EndpointDescriptor *>(ep);
                    mep->bInterval = 1;
                }
            }
        }
    }

    if (score) {
        *score += 10000;
    }

    return this;
}

bool HidLensDriver::start(IOService *provider) {
    if (!IOService::start(provider)) {
        HLOG("start: super::start failed");
        return false;
    }

    fDevice = OSDynamicCast(IOUSBHostDevice, provider);
    if (!fDevice) {
        HLOG("start: provider is not IOUSBHostDevice");
        stop(provider);
        return false;
    }
    fDevice->retain();

    // Find the HID interface (bInterfaceClass=3) among the device's children
    fInterface = nullptr;
    OSIterator *childIter = fDevice->getChildIterator(gIOServicePlane);
    if (childIter) {
        OSObject *child;
        while ((child = childIter->getNextObject())) {
            IOUSBHostInterface *iface = OSDynamicCast(IOUSBHostInterface, child);
            if (iface) {
                const InterfaceDescriptor *ifDesc = iface->getInterfaceDescriptor();
                if (ifDesc && ifDesc->bInterfaceClass == 3) {
                    fInterface = iface;
                    fInterface->retain();
                    break;
                }
            }
        }
        childIter->release();
    }

    if (!fInterface) {
        HLOG("start: no HID interface found");
        // Continue without interface — we still have the device for descriptor access
    }

    // Read device identification
    const DeviceDescriptor *devDesc = fDevice->getDeviceDescriptor();
    if (devDesc) {
        fVendorID = USBToHost16(devDesc->idVendor);
        fProductID = USBToHost16(devDesc->idProduct);
    }

    // Read product name
    OSString *productStr = OSDynamicCast(OSString, fDevice->getProperty("USB Product Name"));
    if (productStr) {
        strlcpy(fProductName, productStr->getCStringNoCopy(), sizeof(fProductName));
    } else {
        snprintf(fProductName, sizeof(fProductName), "Unknown Device (0x%04X:0x%04X)", fVendorID, fProductID);
    }

    fUSBSpeed = determineUSBSpeed();

    // Find interrupt IN endpoint — retry with delays at boot time
    // Config descriptor may not be ready immediately during boot enumeration
    const EndpointDescriptor *epDesc = findInterruptInEndpoint();
    if (!epDesc) {
        HLOG("start: endpoint not found on first try, checking configDesc...");
        const ConfigurationDescriptor *cd = fDevice->getConfigurationDescriptor();
        HLOG("start: configDesc=%p", cd);
        if (cd) {
            HLOG("start: configDesc totalLength=%d numInterfaces=%d",
                   USBToHost16(cd->wTotalLength), cd->bNumInterfaces);
        }
        // Retry with delays — USB enumeration/configuration can take 2-3 seconds
        // We need the config descriptor before the HID DEXT creates pipes
        for (int retry = 0; retry < 50 && !epDesc; retry++) {
            IOSleep(50); // 50ms × 50 retries = 2.5 seconds max
            epDesc = findInterruptInEndpoint();
            if (retry % 10 == 9) {
                HLOG("start: retry %d -> epDesc=%p configDesc=%p",
                       retry + 1, epDesc, fDevice->getConfigurationDescriptor());
            }
        }
        if (epDesc) {
            HLOG("start: found endpoint after retries!");
        }
    }
    if (!epDesc) {
        HLOG("start: no interrupt IN endpoint found after retries for %s", fProductName);
    } else {
        fEndpointAddress = epDesc->bEndpointAddress;
        fOriginalBInterval = epDesc->bInterval;
        fCurrentBInterval = epDesc->bInterval;

        uint32_t currentHz = HidLensBIntervalToHz(fOriginalBInterval, fUSBSpeed);
        HLOG("start: %s — endpoint 0x%02X, bInterval=%d (%dHz), USB %s",
               fProductName, fEndpointAddress, fOriginalBInterval, currentHz,
               fUSBSpeed == 0 ? "Full-Speed" : (fUSBSpeed == 1 ? "High-Speed" : "SuperSpeed"));

        // AUTO-PATCH: Modify bInterval NOW, before HID DEXT creates its pipes.
        // We can't open the device later (DEXT owns it), so patch the cached
        // config descriptor in-place during enumeration. When the HID driver
        // subsequently creates endpoint pipes, it reads our patched value.
        uint8_t targetBInterval = 1; // 1ms = 1000Hz for Full-Speed
        if (fOriginalBInterval > targetBInterval) {
            EndpointDescriptor *mutableEp = const_cast<EndpointDescriptor *>(epDesc);
            mutableEp->bInterval = targetBInterval;
            fCurrentBInterval = targetBInterval;
            fIsOverridden = true;

            uint32_t newHz = HidLensBIntervalToHz(targetBInterval, fUSBSpeed);
            HLOG("start: AUTO-PATCHED bInterval %d -> %d (%dHz -> %dHz) for %s",
                   fOriginalBInterval, targetBInterval, currentHz, newHz, fProductName);
        }
    }

    // Register in device registry
    for (uint32_t i = 0; i < kHidLensMaxDevices; i++) {
        if (sDeviceRegistry[i] == nullptr) {
            sDeviceRegistry[i] = this;
            fRegistryIndex = i;
            if (i >= sDeviceCount) {
                sDeviceCount = i + 1;
            }
            break;
        }
    }

    if (fRegistryIndex == UINT32_MAX) {
        HLOG("start: device registry full");
    }

    registerService();

    HLOG("start: successfully started for %s (index %d)",
           fProductName, fRegistryIndex);
    return true;
}

void HidLensDriver::stop(IOService *provider) {
    HLOG("stop: %s", fProductName);

    if (fIsOverridden) {
        HLOG("stop: restoring original bInterval=%d", fOriginalBInterval);
        modifyBInterval(fOriginalBInterval);
    }

    if (fDevice) {
        fDevice->release();
        fDevice = nullptr;
    }

    if (fInterface) {
        fInterface->release();
        fInterface = nullptr;
    }

    IOService::stop(provider);
}

// ---------------------------------------------------------------------------
// UserClient factory
// ---------------------------------------------------------------------------

IOReturn HidLensDriver::newUserClient(task_t owningTask, void *securityID,
                                       UInt32 type, IOUserClient **handler) {
    HidLensUserClient *client = new HidLensUserClient;
    if (!client) {
        return kIOReturnNoMemory;
    }

    if (!client->initWithTask(owningTask, securityID, type)) {
        client->release();
        return kIOReturnBadArgument;
    }

    if (!client->attach(this)) {
        client->release();
        return kIOReturnError;
    }

    if (!client->start(this)) {
        client->detach(this);
        client->release();
        return kIOReturnError;
    }

    *handler = client;
    HLOG("newUserClient: created for %s", fProductName);
    return kIOReturnSuccess;
}

// ---------------------------------------------------------------------------
// Polling Rate Control
// ---------------------------------------------------------------------------

IOReturn HidLensDriver::setPollingRate(uint32_t targetHz) {
    // Lazy endpoint discovery — may not be available at start() time
    if (fEndpointAddress == 0) {
        HLOG("setPollingRate: retrying endpoint discovery...");
        const EndpointDescriptor *epDesc = findInterruptInEndpoint();
        if (epDesc) {
            fEndpointAddress = epDesc->bEndpointAddress;
            fOriginalBInterval = epDesc->bInterval;
            fCurrentBInterval = epDesc->bInterval;
            fUSBSpeed = determineUSBSpeed();
            HLOG("setPollingRate: found endpoint 0x%02X bInterval=%d",
                   fEndpointAddress, fOriginalBInterval);
        } else {
            // Dump config descriptor info for debugging
            const ConfigurationDescriptor *cd = fDevice ? fDevice->getConfigurationDescriptor() : nullptr;
            HLOG("setPollingRate: configDesc=%p", cd);
            if (cd) {
                HLOG("setPollingRate: configDesc totalLength=%d numInterfaces=%d",
                       USBToHost16(cd->wTotalLength), cd->bNumInterfaces);
                // Walk descriptors for debug
                const Descriptor *hdr = nullptr;
                int count = 0;
                while ((hdr = getNextDescriptor(cd, hdr)) && count < 30) {
                    HLOG("  desc type=%d len=%d", hdr->bDescriptorType, hdr->bLength);
                    if (hdr->bDescriptorType == StandardUSB::kDescriptorTypeInterface) {
                        const InterfaceDescriptor *ifd = (const InterfaceDescriptor *)hdr;
                        HLOG("  interface %d class=%d subclass=%d endpoints=%d",
                               ifd->bInterfaceNumber, ifd->bInterfaceClass, ifd->bInterfaceSubClass, ifd->bNumEndpoints);
                    }
                    if (hdr->bDescriptorType == StandardUSB::kDescriptorTypeEndpoint) {
                        const EndpointDescriptor *ep = (const EndpointDescriptor *)hdr;
                        HLOG("  endpoint addr=0x%02X attr=0x%02X bInterval=%d",
                               ep->bEndpointAddress, ep->bmAttributes, ep->bInterval);
                    }
                    count++;
                }
            }
            HLOG("setPollingRate: no endpoint found after retry");
            return kIOReturnNotFound;
        }
    }

    uint8_t newBInterval = HidLensHzToBInterval(targetHz, fUSBSpeed);
    uint32_t actualHz = HidLensBIntervalToHz(newBInterval, fUSBSpeed);

    HLOG("setPollingRate: %s — target %dHz, bInterval=%d (actual %dHz)",
           fProductName, targetHz, newBInterval, actualHz);

    IOReturn ret = modifyBInterval(newBInterval);
    if (ret != kIOReturnSuccess) {
        HLOG("setPollingRate: modifyBInterval failed: 0x%08X", ret);
        return ret;
    }

    ret = reconfigureDevice();
    if (ret != kIOReturnSuccess) {
        HLOG("setPollingRate: reconfigureDevice failed: 0x%08X", ret);
        modifyBInterval(fOriginalBInterval);
        return ret;
    }

    fCurrentBInterval = newBInterval;
    fIsOverridden = true;

    HLOG("setPollingRate: SUCCESS — %s now at %dHz (bInterval=%d)",
           fProductName, actualHz, newBInterval);
    return kIOReturnSuccess;
}

IOReturn HidLensDriver::resetToDefault() {
    if (!fIsOverridden) {
        return kIOReturnSuccess;
    }

    HLOG("resetToDefault: %s — restoring bInterval=%d",
           fProductName, fOriginalBInterval);

    IOReturn ret = modifyBInterval(fOriginalBInterval);
    if (ret != kIOReturnSuccess) return ret;

    ret = reconfigureDevice();
    if (ret != kIOReturnSuccess) return ret;

    fCurrentBInterval = fOriginalBInterval;
    fIsOverridden = false;

    HLOG("resetToDefault: SUCCESS — %s back to %dHz",
           fProductName, HidLensBIntervalToHz(fOriginalBInterval, fUSBSpeed));
    return kIOReturnSuccess;
}

IOReturn HidLensDriver::getDeviceInfo(HidLensDeviceInfo *outInfo) {
    if (!outInfo) return kIOReturnBadArgument;

    outInfo->index = fRegistryIndex;
    outInfo->vendorID = fVendorID;
    outInfo->productID = fProductID;
    outInfo->originalBInterval = fOriginalBInterval;
    outInfo->currentBInterval = fCurrentBInterval;
    outInfo->usbSpeed = fUSBSpeed;
    outInfo->isOverridden = fIsOverridden ? 1 : 0;
    strlcpy(outInfo->productName, fProductName, sizeof(outInfo->productName));

    return kIOReturnSuccess;
}

// ---------------------------------------------------------------------------
// Private Implementation
// ---------------------------------------------------------------------------

IOReturn HidLensDriver::modifyBInterval(uint8_t newBInterval) {
    if (!fCachedEndpointDesc) {
        HLOG("modifyBInterval: no cached endpoint descriptor");
        return kIOReturnNotReady;
    }

    // Patch bInterval in-place in the cached descriptor
    EndpointDescriptor *mutableEp = const_cast<EndpointDescriptor *>(fCachedEndpointDesc);
    uint8_t oldInterval = mutableEp->bInterval;
    mutableEp->bInterval = newBInterval;

    HLOG("modifyBInterval: endpoint 0x%02X bInterval %d -> %d",
           fEndpointAddress, oldInterval, newBInterval);
    return kIOReturnSuccess;
}

IOReturn HidLensDriver::reconfigureDevice() {
    if (!fDevice) return kIOReturnNotReady;

    HLOG("reconfig: starting for %s, cachedBInterval=%d",
           fProductName, fCachedEndpointDesc ? fCachedEndpointDesc->bInterval : -1);

    IOReturn ret = kIOReturnError;

    // === Strategy 1: Normal device open + setConfiguration cycle ===
    IOReturn openRet = fDevice->open(this);
    HLOG("reconfig: open(normal) = 0x%08X", openRet);

    if (openRet != kIOReturnSuccess) {
        // === Strategy 2: Seize device ===
        openRet = fDevice->open(this, kIOServiceSeize);
        HLOG("reconfig: open(seize) = 0x%08X", openRet);
    }

    if (openRet == kIOReturnSuccess) {
        const ConfigurationDescriptor *configDesc = fDevice->getConfigurationDescriptor();
        if (configDesc) {
            uint8_t configValue = configDesc->bConfigurationValue;
            HLOG("reconfig: config cycle %d -> 0 -> %d", configValue, configValue);

            // Multiple rapid config cycles to force xHCI to reprogram
            // endpoint context aggressively
            for (int cycle = 0; cycle < 3; cycle++) {
                ret = fDevice->setConfiguration(0);
                IOSleep(10);
                ret = fDevice->setConfiguration(configValue);
                HLOG("reconfig: cycle %d setConfig(0→%d) = 0x%08X", cycle, configValue, ret);
                if (cycle < 2) IOSleep(10);
            }

            // Verify descriptor after cycle
            if (fCachedEndpointDesc) {
                HLOG("reconfig: POST bInterval=%d at ptr %p", fCachedEndpointDesc->bInterval, fCachedEndpointDesc);
            }
            // Fresh walk to check
            const ConfigurationDescriptor *freshCd = fDevice->getConfigurationDescriptor();
            HLOG("reconfig: freshCd=%p (was %p) same=%d", freshCd, configDesc, freshCd == configDesc);
            if (freshCd) {
                const Descriptor *hdr = nullptr;
                while ((hdr = getNextDescriptor(freshCd, hdr))) {
                    if (hdr->bDescriptorType == StandardUSB::kDescriptorTypeEndpoint) {
                        const EndpointDescriptor *ep = (const EndpointDescriptor *)hdr;
                        if ((ep->bEndpointAddress & 0x80) && (ep->bmAttributes & 0x03) == kIOUSBEndpointTypeInterrupt) {
                            HLOG("reconfig: VERIFY ep 0x%02X bInterval=%d ptr=%p (cached=%p)",
                                   ep->bEndpointAddress, ep->bInterval, ep, fCachedEndpointDesc);
                        }
                    }
                }
            }
        } else {
            HLOG("reconfig: no config descriptor");
        }
        fDevice->close(this);
        HLOG("reconfig: device closed");
    } else {
        HLOG("reconfig: all open attempts failed");

        // === Strategy 3: Try opening HID interface + adjustPipe ===
        HLOG("reconfig: trying interface adjustPipe...");
        IOUSBHostInterface *hidIf = nullptr;
        OSIterator *iter = fDevice->getChildIterator(gIOServicePlane);
        if (iter) {
            OSObject *child;
            while ((child = iter->getNextObject())) {
                IOUSBHostInterface *iface = OSDynamicCast(IOUSBHostInterface, child);
                if (iface) {
                    const InterfaceDescriptor *ifDesc = iface->getInterfaceDescriptor();
                    if (ifDesc && ifDesc->bInterfaceClass == 3) {
                        hidIf = iface;
                        hidIf->retain();
                        break;
                    }
                }
            }
            iter->release();
        }

        if (hidIf) {
            IOReturn ifOpen = hidIf->open(this, kIOServiceSeize);
            HLOG("reconfig: interface open(seize) = 0x%08X", ifOpen);

            if (ifOpen == kIOReturnSuccess) {
                IOUSBHostPipe *pipe = hidIf->copyPipe(fEndpointAddress);
                HLOG("reconfig: copyPipe(0x%02X) = %p", fEndpointAddress, pipe);

                if (pipe && fCachedEndpointDesc) {
                    ret = pipe->adjustPipe(fCachedEndpointDesc, nullptr);
                    HLOG("reconfig: adjustPipe(bInterval=%d) = 0x%08X",
                           fCachedEndpointDesc->bInterval, ret);

                    const EndpointDescriptor *pipeDesc = pipe->getEndpointDescriptor();
                    if (pipeDesc) {
                        HLOG("reconfig: pipe now reports bInterval=%d", pipeDesc->bInterval);
                    }
                    pipe->release();
                }
                hidIf->close(this);
            }
            hidIf->release();
        } else {
            HLOG("reconfig: no HID interface found");
        }
    }

    HLOG("reconfig: done ret=0x%08X", ret);
    return kIOReturnSuccess;
}

const EndpointDescriptor *HidLensDriver::findInterruptInEndpoint() {
    if (!fDevice) {
        HLOG("findEP: fDevice is NULL");
        return nullptr;
    }

    const ConfigurationDescriptor *configDesc = fDevice->getConfigurationDescriptor();
    if (!configDesc) {
        HLOG("findEP: getConfigurationDescriptor returned NULL");
        return nullptr;
    }

    HLOG("findEP: configDesc=%p totalLen=%d numIf=%d configVal=%d",
           configDesc, USBToHost16(configDesc->wTotalLength),
           configDesc->bNumInterfaces, configDesc->bConfigurationValue);

    const Descriptor *header = nullptr;
    bool inHIDInterface = false;
    uint8_t currentInterfaceNum = 0;
    int descCount = 0;

    while ((header = getNextDescriptor(configDesc, header))) {
        descCount++;
        if (header->bDescriptorType == StandardUSB::kDescriptorTypeInterface) {
            const InterfaceDescriptor *ifd = (const InterfaceDescriptor *)header;
            HLOG("findEP: iface %d class=%d sub=%d proto=%d numEP=%d",
                   ifd->bInterfaceNumber, ifd->bInterfaceClass,
                   ifd->bInterfaceSubClass, ifd->bInterfaceProtocol,
                   ifd->bNumEndpoints);
            inHIDInterface = (ifd->bInterfaceClass == 3);
            currentInterfaceNum = ifd->bInterfaceNumber;
        }

        if (header->bDescriptorType == StandardUSB::kDescriptorTypeEndpoint) {
            const EndpointDescriptor *epDesc = (const EndpointDescriptor *)header;
            uint8_t transferType = epDesc->bmAttributes & 0x03;
            bool isIN = (epDesc->bEndpointAddress & 0x80) != 0;

            HLOG("findEP: endpoint addr=0x%02X attr=0x%02X interval=%d (inHID=%d type=%d isIN=%d)",
                   epDesc->bEndpointAddress, epDesc->bmAttributes, epDesc->bInterval,
                   inHIDInterface, transferType, isIN);

            if (inHIDInterface && transferType == kIOUSBEndpointTypeInterrupt && isIN) {
                HLOG("findEP: MATCH 0x%02X bInterval=%d in interface %d",
                       epDesc->bEndpointAddress, epDesc->bInterval, currentInterfaceNum);
                fCachedEndpointDesc = epDesc;
                return epDesc;
            }
        }
    }

    HLOG("findEP: no match found (%d descriptors walked)", descCount);
    return nullptr;
}

uint8_t HidLensDriver::determineUSBSpeed() {
    if (!fDevice) return 0;

    OSNumber *speedNum = OSDynamicCast(OSNumber, fDevice->getProperty("Device Speed"));
    if (speedNum) {
        uint32_t speed = speedNum->unsigned32BitValue();
        switch (speed) {
            case 2:  return 1; // High-Speed
            case 3:  return 2; // SuperSpeed
            default: return 0; // Full-Speed
        }
    }

    return 0;
}
