#include "HidLensUserClient.h"
#include "HidLensDriver.h"
#include <IOKit/IOLib.h>
#include <os/log.h>

#define LOG_PREFIX "HidLens UC: "

OSDefineMetaClassAndStructors(HidLensUserClient, IOUserClient)

// ---------------------------------------------------------------------------
// Method dispatch table
// ---------------------------------------------------------------------------

// Each entry: { function, checkScalarInputCount, checkStructureInputSize,
//               checkScalarOutputCount, checkStructureOutputSize }
const IOExternalMethodDispatch HidLensUserClient::sMethods[kHidLensMethodCount] = {
    // kHidLensMethodGetDeviceCount: no input, 1 scalar output (count)
    [kHidLensMethodGetDeviceCount] = {
        .function = sGetDeviceCount,
        .checkScalarInputCount = 0,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 1,
        .checkStructureOutputSize = 0
    },
    // kHidLensMethodGetDeviceInfo: 1 scalar input (index), struct output (HidLensDeviceInfo)
    [kHidLensMethodGetDeviceInfo] = {
        .function = sGetDeviceInfo,
        .checkScalarInputCount = 1,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = sizeof(HidLensDeviceInfo)
    },
    // kHidLensMethodSetPollingRate: 2 scalar inputs (index, targetHz), no output
    [kHidLensMethodSetPollingRate] = {
        .function = sSetPollingRate,
        .checkScalarInputCount = 2,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0
    },
    // kHidLensMethodResetDevice: 1 scalar input (index), no output
    [kHidLensMethodResetDevice] = {
        .function = sResetDevice,
        .checkScalarInputCount = 1,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0
    },
    // kHidLensMethodGetCurrentRate: 1 scalar input (index), 2 scalar outputs (bInterval, Hz)
    [kHidLensMethodGetCurrentRate] = {
        .function = sGetCurrentRate,
        .checkScalarInputCount = 1,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 2,
        .checkStructureOutputSize = 0
    }
};

// ---------------------------------------------------------------------------
// IOUserClient Lifecycle
// ---------------------------------------------------------------------------

bool HidLensUserClient::initWithTask(task_t owningTask, void *securityID, UInt32 type) {
    if (!IOUserClient::initWithTask(owningTask, securityID, type)) {
        return false;
    }
    fTask = owningTask;
    fDriver = nullptr;
    os_log(OS_LOG_DEFAULT, LOG_PREFIX "initWithTask");
    return true;
}

bool HidLensUserClient::start(IOService *provider) {
    if (!IOUserClient::start(provider)) {
        return false;
    }

    fDriver = OSDynamicCast(HidLensDriver, provider);
    if (!fDriver) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "start: provider is not HidLensDriver");
        return false;
    }

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "start: connected to HidLensDriver");
    return true;
}

void HidLensUserClient::stop(IOService *provider) {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX "stop");
    IOUserClient::stop(provider);
}

void HidLensUserClient::free() {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX "free");
    IOUserClient::free();
}

IOReturn HidLensUserClient::clientClose() {
    os_log(OS_LOG_DEFAULT, LOG_PREFIX "clientClose");

    if (!isInactive()) {
        terminate();
    }
    return kIOReturnSuccess;
}

// ---------------------------------------------------------------------------
// External Method Dispatch
// ---------------------------------------------------------------------------

IOReturn HidLensUserClient::externalMethod(uint32_t selector,
                                            IOExternalMethodArguments *arguments,
                                            IOExternalMethodDispatch *dispatch,
                                            OSObject *target,
                                            void *reference) {
    if (selector >= kHidLensMethodCount) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "externalMethod: invalid selector %d", selector);
        return kIOReturnBadArgument;
    }

    dispatch = const_cast<IOExternalMethodDispatch *>(&sMethods[selector]);
    target = this;
    reference = nullptr;

    return IOUserClient::externalMethod(selector, arguments, dispatch, target, reference);
}

// ---------------------------------------------------------------------------
// Method Implementations
// ---------------------------------------------------------------------------

IOReturn HidLensUserClient::sGetDeviceCount(OSObject *target, void *reference,
                                             IOExternalMethodArguments *arguments) {
    arguments->scalarOutput[0] = HidLensDriver::sDeviceCount;
    os_log(OS_LOG_DEFAULT, LOG_PREFIX "getDeviceCount: %d", HidLensDriver::sDeviceCount);
    return kIOReturnSuccess;
}

IOReturn HidLensUserClient::sGetDeviceInfo(OSObject *target, void *reference,
                                            IOExternalMethodArguments *arguments) {
    uint32_t index = (uint32_t)arguments->scalarInput[0];

    if (index >= kHidLensMaxDevices || HidLensDriver::sDeviceRegistry[index] == nullptr) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "getDeviceInfo: invalid index %d", index);
        return kIOReturnBadArgument;
    }

    HidLensDriver *driver = HidLensDriver::sDeviceRegistry[index];
    HidLensDeviceInfo *info = (HidLensDeviceInfo *)arguments->structureOutput;

    return driver->getDeviceInfo(info);
}

IOReturn HidLensUserClient::sSetPollingRate(OSObject *target, void *reference,
                                             IOExternalMethodArguments *arguments) {
    uint32_t index = (uint32_t)arguments->scalarInput[0];
    uint32_t targetHz = (uint32_t)arguments->scalarInput[1];

    if (index >= kHidLensMaxDevices || HidLensDriver::sDeviceRegistry[index] == nullptr) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "setPollingRate: invalid index %d", index);
        return kIOReturnBadArgument;
    }

    // Sanity check on target Hz
    if (targetHz < 1 || targetHz > 8000) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "setPollingRate: invalid target %dHz", targetHz);
        return kIOReturnBadArgument;
    }

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "setPollingRate: device %d → %dHz", index, targetHz);
    HidLensDriver *driver = HidLensDriver::sDeviceRegistry[index];
    return driver->setPollingRate(targetHz);
}

IOReturn HidLensUserClient::sResetDevice(OSObject *target, void *reference,
                                           IOExternalMethodArguments *arguments) {
    uint32_t index = (uint32_t)arguments->scalarInput[0];

    if (index >= kHidLensMaxDevices || HidLensDriver::sDeviceRegistry[index] == nullptr) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "resetDevice: invalid index %d", index);
        return kIOReturnBadArgument;
    }

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "resetDevice: device %d", index);
    HidLensDriver *driver = HidLensDriver::sDeviceRegistry[index];
    return driver->resetToDefault();
}

IOReturn HidLensUserClient::sGetCurrentRate(OSObject *target, void *reference,
                                              IOExternalMethodArguments *arguments) {
    uint32_t index = (uint32_t)arguments->scalarInput[0];

    if (index >= kHidLensMaxDevices || HidLensDriver::sDeviceRegistry[index] == nullptr) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "getCurrentRate: invalid index %d", index);
        return kIOReturnBadArgument;
    }

    HidLensDriver *driver = HidLensDriver::sDeviceRegistry[index];
    uint8_t bInterval = driver->getCurrentBInterval();
    // Determine USB speed from device info
    HidLensDeviceInfo info;
    driver->getDeviceInfo(&info);
    uint32_t hz = HidLensBIntervalToHz(bInterval, info.usbSpeed);

    arguments->scalarOutput[0] = bInterval;
    arguments->scalarOutput[1] = hz;

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "getCurrentRate: device %d — bInterval=%d (%dHz)", index, bInterval, hz);
    return kIOReturnSuccess;
}
