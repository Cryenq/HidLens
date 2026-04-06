# HidLens

**macOS USB Polling Rate Override for Game Controllers**

HidLens is the macOS equivalent of [hidusbf](https://github.com/LordOfMice/hidusbf) (Windows). It overrides USB polling rates for game controllers on macOS, including Apple Silicon, using a kernel extension (KEXT).

## What it does

- **Override USB polling rate** for PlayStation controllers (DualShock 4, DualSense, DualSense Edge) from their default 200-250Hz up to **1000Hz**
- **Measure actual polling rate** with nanosecond precision — average Hz, jitter, latency percentiles (p50/p95/p99)
- **Export measurements** as JSON or CSV
- Works on **Apple Silicon** (M1/M2/M3/M4) and Intel Macs

## Supported Devices

| Controller | VID:PID | Default Rate | Max Override |
|---|---|---|---|
| DualShock 4 v1 | 054C:05C4 | 250 Hz | 1000 Hz |
| DualShock 4 v2 | 054C:09CC | 250 Hz | 1000 Hz |
| DualSense (PS5) | 054C:0CE6 | 250 Hz | 1000 Hz |
| DualSense Edge | 054C:0DF2 | 250 Hz | 1000 Hz |

USB mice support is planned for a future version.

## How it works

HidLens uses a kernel extension that modifies the `bInterval` field in USB endpoint descriptors and resets the device. The xHCI controller then reprograms its Endpoint Context with the new polling interval. This is the same proven technique used by:
- [GCAdapterDriver](https://github.com/secretkeysio/GCAdapterDriver) (macOS)
- [gcadapter-oc-kmod](https://github.com/HannesMann/gcadapter-oc-kmod) (Linux)

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon (M1+) or Intel Mac
- **Reduced Security** must be enabled (one-time setup)

## Setup (One-Time)

1. **Shut down** your Mac completely
2. **Hold the power button** until "Loading startup options" appears
3. Click **Options** → Continue
4. Menu bar: **Utilities → Startup Security Utility**
5. Select **Reduced Security**
6. Check **"Allow user management of kernel extensions from identified developers"**
7. **Restart** your Mac

## Installation

### Build from source

```bash
# Build CLI tool
swift build -c release

# The CLI binary is at:
.build/release/hidlens
```

The KEXT must be built with Xcode (see Development section below).

### Load KEXT

```bash
sudo ./Scripts/install-kext.sh
# or manually:
sudo kextload build/HidLensDriver.kext
```

## CLI Usage

```bash
# List connected controllers and mice
hidlens list

# Show device details
hidlens inspect <registry-id>

# Measure actual polling rate (5 seconds, move device during measurement)
hidlens measure <registry-id> --duration 5

# Override polling rate to 1000Hz (requires KEXT)
hidlens override <device-index> --rate 1000

# Reset to original polling rate
hidlens reset <device-index>

# Export measurement as JSON
hidlens export <registry-id> --format json --output report.json

# Show KEXT setup guide
hidlens setup
```

## Development

### Project Structure

```
HidLens/
├── HidLensDriver/          # KEXT (C++) — bInterval modification
├── Sources/
│   ├── HidLensCore/        # Shared library (Swift) — models, services
│   ├── hidlens/            # CLI tool (Swift)
│   └── HidLensApp/         # SwiftUI app (Swift) — requires Xcode
├── Tests/                  # Unit tests
└── Scripts/                # Install/uninstall helpers
```

### Building

```bash
# CLI + Core library
swift build

# Run tests
swift test

# KEXT (requires Xcode with IOKit kernel headers)
# Create an Xcode project and add HidLensDriver/ as a KEXT target
```

### KEXT Development Notes

- The KEXT requires a **KEXT-enabled Developer ID certificate** for distribution
- For development: ad-hoc signing + SIP disabled is sufficient
- The KEXT uses IOKit kernel APIs (`IOService`, `IOUSBHostInterface`, `IOUserClient`)
- Communication between KEXT and userland is via `IOServiceOpen` / `IOConnectCallScalarMethod`

## How does polling override work?

1. The KEXT matches USB devices by Vendor ID / Product ID (e.g., Sony DualShock 4)
2. When the user requests an override, the KEXT:
   - Reads the USB endpoint descriptor's `bInterval` field (e.g., 5 = 250Hz for Full-Speed)
   - Modifies `bInterval` to the target value (e.g., 1 = 1000Hz)
   - Cycles the USB configuration: `SetConfiguration(0)` → `SetConfiguration(original)`
3. The xHCI controller reads the updated descriptor and reprograms its Endpoint Context
4. The device is now polled at the new rate

## Limitations

- **KEXTs are deprecated by Apple** — may stop working in future macOS versions
- **Reduced Security is required** — this is a system-wide security change
- DualShock 4 is USB Full-Speed → **1000Hz is the physical maximum** (no 4000/8000Hz)
- The KEXT must be **reloaded after each reboot** (can be scripted)
- **Experimental**: Whether the Apple Silicon xHCI controller fully honors bInterval=1 for all devices needs real-world verification

## vs hidusbf (Windows)

| Feature | hidusbf (Windows) | HidLens (macOS) |
|---|---|---|
| Override polling rate | Yes (patches system USB drivers) | Yes (KEXT modifies endpoint descriptor) |
| Max rate (FS devices) | 1000 Hz | 1000 Hz |
| Measure polling rate | Basic | Nanosecond precision + percentiles |
| Requires setup | Admin + driver signature bypass | Reduced Security + KEXT approval |
| Open source | No | Yes (MIT) |

## License

MIT
