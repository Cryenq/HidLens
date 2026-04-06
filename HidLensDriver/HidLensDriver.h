#ifndef HidLensDriver_h
#define HidLensDriver_h

#include <IOKit/IOService.h>
#include <IOKit/usb/IOUSBHostInterface.h>
#include <IOKit/usb/IOUSBHostPipe.h>
#include <IOKit/usb/IOUSBHostDevice.h>
#include <IOKit/usb/StandardUSB.h>
#include "HidLensShared.h"

// Use StandardUSB types from modern IOKit SDK
using StandardUSB::DeviceDescriptor;
using StandardUSB::ConfigurationDescriptor;
using StandardUSB::InterfaceDescriptor;
using StandardUSB::EndpointDescriptor;
using StandardUSB::Descriptor;
using StandardUSB::getNextDescriptor;

// Forward declaration
class HidLensUserClient;

/// HidLensDriver - IOService-based KEXT that matches USB HID game controllers
/// and modifies their endpoint bInterval to override USB polling rate.
class HidLensDriver : public IOService {
    OSDeclareDefaultStructors(HidLensDriver)

public:
    virtual bool init(OSDictionary *dictionary = nullptr) override;
    virtual void free() override;
    virtual IOService *probe(IOService *provider, SInt32 *score) override;
    virtual bool start(IOService *provider) override;
    virtual void stop(IOService *provider) override;

    virtual IOReturn newUserClient(task_t owningTask, void *securityID,
                                   UInt32 type, IOUserClient **handler) override;

    IOReturn setPollingRate(uint32_t targetHz);
    IOReturn resetToDefault();
    IOReturn getDeviceInfo(HidLensDeviceInfo *outInfo);
    uint8_t getCurrentBInterval() const { return fCurrentBInterval; }
    uint8_t getOriginalBInterval() const { return fOriginalBInterval; }

    static HidLensDriver *sDeviceRegistry[kHidLensMaxDevices];
    static uint32_t sDeviceCount;

private:
    IOReturn modifyBInterval(uint8_t newBInterval);
    IOReturn reconfigureDevice();
    const EndpointDescriptor *findInterruptInEndpoint();
    uint8_t determineUSBSpeed();

    IOUSBHostInterface *fInterface;
    IOUSBHostDevice    *fDevice;

    uint8_t  fOriginalBInterval;
    uint8_t  fCurrentBInterval;
    uint8_t  fUSBSpeed;
    uint8_t  fEndpointAddress;
    bool     fIsOverridden;
    const EndpointDescriptor *fCachedEndpointDesc;

    uint16_t fVendorID;
    uint16_t fProductID;
    char     fProductName[128];

    uint32_t fRegistryIndex;
};

#endif /* HidLensDriver_h */
