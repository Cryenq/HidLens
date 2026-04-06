#ifndef HidLensUserClient_h
#define HidLensUserClient_h

#include <IOKit/IOUserClient.h>
#include "HidLensShared.h"

class HidLensDriver;

/// HidLensUserClient — IOUserClient subclass that enables userland apps to
/// communicate with the HidLensDriver KEXT.
///
/// Exposes methods for:
/// - Querying matched device count and info
/// - Setting polling rate (bInterval override)
/// - Resetting devices to original polling rate
/// - Reading current bInterval
class HidLensUserClient : public IOUserClient {
    OSDeclareDefaultStructors(HidLensUserClient)

public:
    // IOUserClient lifecycle
    virtual bool initWithTask(task_t owningTask, void *securityID, UInt32 type) override;
    virtual bool start(IOService *provider) override;
    virtual void stop(IOService *provider) override;
    virtual void free() override;

    // Client management
    virtual IOReturn clientClose() override;

    // External method dispatch
    virtual IOReturn externalMethod(uint32_t selector,
                                    IOExternalMethodArguments *arguments,
                                    IOExternalMethodDispatch *dispatch,
                                    OSObject *target,
                                    void *reference) override;

protected:
    // Method implementations
    static IOReturn sGetDeviceCount(OSObject *target, void *reference,
                                    IOExternalMethodArguments *arguments);
    static IOReturn sGetDeviceInfo(OSObject *target, void *reference,
                                   IOExternalMethodArguments *arguments);
    static IOReturn sSetPollingRate(OSObject *target, void *reference,
                                    IOExternalMethodArguments *arguments);
    static IOReturn sResetDevice(OSObject *target, void *reference,
                                  IOExternalMethodArguments *arguments);
    static IOReturn sGetCurrentRate(OSObject *target, void *reference,
                                     IOExternalMethodArguments *arguments);

private:
    HidLensDriver *fDriver;
    task_t fTask;

    // Method dispatch table
    static const IOExternalMethodDispatch sMethods[kHidLensMethodCount];
};

#endif /* HidLensUserClient_h */
