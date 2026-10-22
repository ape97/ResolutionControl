# Platform state

The macOS/Xcode version Resolution Control was last fully tested against (`scripts/check.sh` green, deployed).
`scripts/status.sh` compares the last `tested:` line with the running system.
Append new lines at the bottom and keep the format exactly (the "Platform now" value from `status.sh` + ` date=YYYY-MM-DD`).

## Dependencies on the system (an update can break these)
- **MenuBarExtra (.window)** and window notifications used to detect the menu closing (`App/AppModel.swift`).
- **SMAppService** (login item) – `scripts/status.sh` checks it via `sfltool dumpbtm`.
- **Private AppKit methods** used by the performance test (`App/StructureTest.swift`): `_updateStructuralRegionsOnNextDisplayCycle`,
  `_setTrackingAreasDirty:` – test only, not the app.
- **Signing**: builds are ad-hoc signed by default. If you sign with your own certificate via `Config/Local.xcconfig`, it expires; `scripts/status.sh` shows when, then renew it in Xcode.
- **CoreGraphics display modes** (`CGDisplayCopyAllDisplayModes` with `kCGDisplayShowDuplicateLowResolutionModes`,
  `CGConfigureDisplayWithDisplayMode`, ioFlags 0x4 = default, 0x02000000 = native) and **ColorSync**
  (`ColorSyncDeviceSetCustomProfiles`) – `App/Displays.swift`; the self-test reads the real modes and checks the built-in list.

## Tested
tested: macOS=27.0.1 (26A434) Xcode=27.0 SDK=27.0 date=2026-10-16
