#ifndef HidLensShared_h
#define HidLensShared_h

#include <stdint.h>

// Bundle identifier for the KEXT
#define kHidLensDriverClassName "HidLensDriver"
#define kHidLensUserClientClassName "HidLensUserClient"
#define kHidLensBundleID "com.hidlens.driver"

// Maximum number of devices the KEXT tracks simultaneously
#define kHidLensMaxDevices 8

// IOUserClient method selectors
enum HidLensMethod {
    kHidLensMethodGetDeviceCount    = 0,  // Get number of matched devices
    kHidLensMethodGetDeviceInfo     = 1,  // Get info for device at index
    kHidLensMethodSetPollingRate    = 2,  // Set polling rate for device
    kHidLensMethodResetDevice       = 3,  // Restore original bInterval
    kHidLensMethodGetCurrentRate    = 4,  // Get current bInterval for device
    kHidLensMethodCount             = 5
};

// Polling rate presets (Hz)
enum HidLensPollingRate {
    kHidLensRate125  = 125,
    kHidLensRate250  = 250,
    kHidLensRate500  = 500,
    kHidLensRate1000 = 1000
};

// Device info structure shared between KEXT and userland
typedef struct {
    uint32_t index;              // Device index in KEXT's tracked array
    uint16_t vendorID;           // USB Vendor ID
    uint16_t productID;          // USB Product ID
    uint8_t  originalBInterval;  // Original bInterval from device descriptor
    uint8_t  currentBInterval;   // Current bInterval (after override)
    uint8_t  usbSpeed;           // 0 = Full-Speed, 1 = High-Speed, 2 = SuperSpeed
    uint8_t  isOverridden;       // 1 if polling rate has been modified
    char     productName[128];   // Product name string (UTF-8)
} HidLensDeviceInfo;

// Convert target Hz to bInterval value
// For Full-Speed (12 Mbps): bInterval is in milliseconds (1-255)
//   bInterval = 1000 / targetHz
// For High-Speed (480 Mbps): bInterval uses 2^(bInterval-1) * 125μs formula
//   Need to find bInterval where 2^(bInterval-1) * 125μs = 1000000/targetHz μs
static inline uint8_t HidLensHzToBInterval(uint32_t targetHz, uint8_t usbSpeed) {
    if (targetHz == 0) return 1;

    if (usbSpeed == 0) {
        // Full-Speed: bInterval in ms, range 1-255
        uint32_t intervalMs = 1000 / targetHz;
        if (intervalMs < 1) intervalMs = 1;
        if (intervalMs > 255) intervalMs = 255;
        return (uint8_t)intervalMs;
    } else {
        // High-Speed: bInterval uses 2^(bInterval-1) * 125μs
        // targetHz -> interval in μs -> find bInterval
        uint32_t intervalUs = 1000000 / targetHz;
        // Find smallest bInterval where 2^(bInterval-1) * 125 >= intervalUs
        // bInterval=1: 125μs (8000Hz)
        // bInterval=2: 250μs (4000Hz)
        // bInterval=3: 500μs (2000Hz)
        // bInterval=4: 1000μs (1000Hz)
        // bInterval=5: 2000μs (500Hz)
        // bInterval=6: 4000μs (250Hz)
        // bInterval=7: 8000μs (125Hz)
        for (uint8_t b = 1; b <= 16; b++) {
            uint32_t period = (1 << (b - 1)) * 125;
            if (period >= intervalUs) {
                return b;
            }
        }
        return 16; // minimum rate
    }
}

// Convert bInterval to Hz
static inline uint32_t HidLensBIntervalToHz(uint8_t bInterval, uint8_t usbSpeed) {
    if (bInterval == 0) return 0;

    if (usbSpeed == 0) {
        // Full-Speed: bInterval in ms
        return 1000 / bInterval;
    } else {
        // High-Speed: 2^(bInterval-1) * 125μs
        uint32_t periodUs = (1 << (bInterval - 1)) * 125;
        return 1000000 / periodUs;
    }
}

#endif /* HidLensShared_h */
