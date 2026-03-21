# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build for macOS
xcodebuild -project tether.xcodeproj -scheme tether -destination 'platform=macOS' build

# Build for iPad simulator
xcodebuild -project tether.xcodeproj -scheme tether -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' build

# Build for iOS device (arm64)
xcodebuild -project tether.xcodeproj -scheme tether -destination 'generic/platform=iOS' build
```

No external dependencies — only Apple frameworks (ImageCaptureCore, ImageIO, SwiftUI, Foundation). No SPM packages.

No test infrastructure exists yet.

## Architecture

Canon EOS cameras communicate over USB using PTP (Picture Transfer Protocol) with Canon vendor extensions. Apple's ImageCaptureCore framework provides device discovery and raw PTP command passthrough on iPadOS/macOS.

```
SwiftUI Views
  ContentView ─── GeometryReader + ZStack layout
    │  ├── liveViewLayer (full-bleed: play button / pulsing camera / LiveViewDisplay + stop overlay)
    │  └── floatingControls (draggable .glassEffect() panel: drag handle + CameraControlsView + status)
    │
    ├── LiveViewDisplay ─── shows CGImage or ContentUnavailableView (platform-aware USB text)
    └── CameraControlsView ─── ISO picker, shutter button, Tv picker (no own background)
       │
  CameraManager (@Observable — discovery, connection, state)
       │
  CanonPTPService (PTP command encoding/decoding, Canon vendor ops)
       │
  ICDeviceBrowser / ICCameraDevice (Apple's ImageCaptureCore)
```

**CameraManager** — Central state manager. Owns the `ICDeviceBrowser`, handles device discovery (filters for Canon USB vendor ID `0x04A9`), manages connection lifecycle, and drives the UI via `@Observable`. Delegates are `nonisolated` with `Task { @MainActor in }` dispatch for Swift 6 concurrency. Has a `#if DEBUG` preview factory (`CameraManager.preview(state:cameraName:isLiveViewActive:)`) for SwiftUI previews.

**CanonPTPService** — Builds PTP command containers (12-byte header: length + type + opcode + transaction ID, all little-endian), sends them via `requestSendPTPCommand`, and parses responses. The completion handler returns data-in payload as the *first* parameter and PTP response container as the *second* — this is counterintuitive and was discovered empirically.

**CanonPTPConstants** — Single source of truth for Canon PTP operation codes, property codes, ISO/shutter speed value mappings (APEX-based hex codes), `Data` extension helpers for little-endian serialization, and the `ConnectionState` enum.

## UI / Interaction Design

**Layout**: Full-bleed live view with a floating controls panel overlaid via `ZStack`. No top bar — status info lives inside the floating panel.

**Live view states** (in `ContentView.liveViewLayer`):
1. **No camera** → `LiveViewDisplay` shows `ContentUnavailableView` with platform-specific USB text (Mac/iPhone/iPad/Vision Pro, via `#if os()` + `UIDevice.current.userInterfaceIdiom`)
2. **Connected, live view off** → large `play.fill` button in `.glassEffect()`
3. **Live view warming up** (active but no frames yet) → pulsing `camera.fill` symbol (`.symbolEffect(.pulse)`)
4. **Live view streaming** → `LiveViewDisplay` with a `stop.fill` glass button overlaid top-right

**Floating controls panel** (`ContentView.floatingControls`):
- Wrapped in `.glassEffect()` (liquid glass). `CameraControlsView` has no background of its own.
- Drag handle capsule at top as visual affordance
- Draggable via `DragGesture(minimumDistance: 10)` — works with touch, trackpad, and mouse
- Position stored as absolute `CGPoint?` (defaults to bottom-center via `GeometryReader`), clamped to 60pt from edges on release with spring animation
- `minimumDistance: 10` prevents stealing taps from buttons/menus inside the panel

**SwiftUI previews**: `ContentView` has an injectable `init(cameraManager:)` and three named previews: "No Camera", "Connected — Live View Off", "Live View Warming Up". Uses `CameraManager.preview(state:cameraName:isLiveViewActive:)` factory (DEBUG only).

## Canon PTP Protocol Details

These details are non-obvious and were discovered through testing with a Canon EOS Rebel T5 (1200D). They should apply broadly to Canon EOS DSLRs from 2012+ and EOS R mirrorless cameras.

### PTP Command Container Format

Every command sent via `requestSendPTPCommand` must be a properly formed PTP container:

```
Offset  Size   Field
0x00    4      ContainerLength (total bytes, LE)
0x04    2      ContainerType = 0x0001 (Command Block)
0x06    2      OperationCode (LE)
0x08    4      TransactionID (LE, monotonically increasing from 1)
0x0C    4*N    Parameters (up to 5, each UInt32 LE)
```

Minimum command size is 12 bytes (no parameters). The PTP response container has the same layout but with ContainerType = 0x0003 and a ResponseCode at offset 0x06 (0x2001 = OK).

### `requestSendPTPCommand` Completion Handler

**Critical**: Apple's completion handler `(Data, Data, Error?)` returns:
- **First Data** = data-in phase payload (file/event/frame data from camera). Empty (0 bytes) for commands without a data-in phase.
- **Second Data** = PTP response container (always 12+ bytes). Contains response code at offset 6.

This was determined empirically — the naming in Apple's headers is ambiguous. Every command tested on macOS returns 0 bytes in the first param and the PTP response in the second, except for commands with data-in phases (GetEvent, GetViewFinderData) which return payload in the first.

### Canon EOS Operation Codes

Commands that take **PTP command parameters** (value goes at offset 0x0C in the command container):
- `SetRemoteMode (0x9114)` — param: 0x01 = enable, 0x00 = disable
- `SetEventMode (0x9115)` — param: 0x01 = enable event queuing
- `RemoteReleaseOn (0x9128)` — param: 0x03 = AF + full press (bit 0 = half-press/AF, bit 1 = full press)
- `RemoteReleaseOff (0x9129)` — param: 0x03 = release both
- `GetViewFinderData (0x9153)` — param: 0x00100000 = buffer size hint

Commands that use the **data-out phase** instead of command parameters:
- `SetDevicePropValueEx (0x9110)` — NO command params. Data-out = `[totalSize:4][propCode:4][value:4]` (12 bytes total, all LE). This is a common mistake — 0x910F is NOT GetDevicePropValueEx (it's GetPartialObjectEx).

Commands that return **data-in phase** content:
- `GetEvent (0x9116)` — no params. Returns bulk event records in first completion param.
- `GetViewFinderData (0x9153)` — returns live view frame with Canon header + JPEG in first completion param.

### Connection Sequence

The exact order matters — deviating causes hangs or silent failures:

1. `ICDeviceBrowser.start()` → discovers USB devices
2. Filter for `device.usbVendorID == 0x04A9` (Canon) and `device is ICCameraDevice`
3. Set `camera.delegate`, call `camera.requestOpenSession()`
4. Wait for `device(_:didOpenSessionWithError:)` — session is open but camera NOT ready yet
5. **Wait for `deviceDidBecomeReady(withCompleteContentCatalog:)`** — this is critical. Sending PTP commands before this callback causes them to hang indefinitely with no error.
6. On iPadOS only: `browser.requestControlAuthorization()` and verify `.authorized`
7. `SetRemoteMode(0x01)` → puts camera in remote control mode (screen may go blank)
8. `SetEventMode(0x01)` → camera begins queuing property change events
9. `GetEvent` → returns all current property values + available value lists
10. Camera is now fully controllable

### Reading Properties via Events

Canon EOS has NO per-property get command. Instead:
- Call `SetEventMode(1)` once during init — camera queues all current values
- Call `GetEvent (0x9116)` to retrieve queued events
- After property changes (from app or camera body), new events are queued
- Poll `GetEvent` after each `SetDevicePropValueEx` to confirm the change and get updated available values

### Event Record Binary Format

GetEvent returns concatenated variable-length records in the data-in payload:

**Property Value Changed (0xC189)** — 16 bytes fixed:
```
Offset  Size   Field
0x00    4      RecordSize = 0x10 (16)
0x04    4      EventType = 0xC189
0x08    4      PropertyCode (e.g., 0xD103 = ISO)
0x0C    4      CurrentValue
```

**Available Values List Changed (0xC18A)** — variable length:
```
Offset  Size   Field
0x00    4      RecordSize = 0x14 + (count * 4)
0x04    4      EventType = 0xC18A
0x08    4      PropertyCode
0x0C    4      DataType (PTP type code, but Canon always uses 4-byte slots regardless)
0x10    4      Count of available values
0x14    4*N    Array of valid values (each 4 bytes even if actual type is smaller)
```

**End Marker** — 8 bytes:
```
08 00 00 00  00 00 00 00   (size=8, type=0)
```

Records are back-to-back, 4-byte aligned. When a property becomes unavailable (e.g., switching modes), the camera sends 0xC18A with count=0.

### Canon Property Codes

- `0xD101` — Aperture (Av)
- `0xD102` — Shutter speed (Tv)
- `0xD103` — ISO
- `0xD104` — Exposure compensation
- `0xD107` — Metering mode
- `0xD10A` — White balance
- `0xD1B0` — EVF output device (bit 1 = PC/0x02 routes live view to computer)
- `0xD1B4` — EVF mode (1 = enable, 0 = disable)

ISO and shutter speed values use Canon's APEX-based hex encoding. Each full stop = +8 in hex (e.g., ISO 100=0x48, 200=0x50, 400=0x58). Third-stop increments are +3 and +5 between full stops. The complete mappings are in `CanonPTPConstants.swift`.

### Live View

Enable: `SetDevicePropValueEx(evfMode, 1)` then `SetDevicePropValueEx(evfOutputDevice, 0x02)`
Poll frames: `GetViewFinderData(0x00100000)` at ~15fps (67ms interval)
Disable: reverse order — `SetDevicePropValueEx(evfOutputDevice, 0x00)` then `SetDevicePropValueEx(evfMode, 0)`

Frame data has a Canon proprietary header before the JPEG. Extract by scanning for JPEG SOI marker (0xFF 0xD8) and reading to EOI (0xFF 0xD9). Do NOT rely on fixed offsets — scan for SOI.

### Shutter Trigger

```
RemoteReleaseOn(0x03)   → AF + shutter actuates
sleep(200ms)            → allow mechanical shutter to complete
RemoteReleaseOff(0x03)  → release
```

Photo saves to camera's SD card, not the iPad/Mac. The 200ms delay is important — releasing too quickly can cause incomplete captures on some camera bodies.

### Timeout Handling

PTP commands can hang indefinitely if the camera is in a bad state or the command is malformed. The `OnceFlag` pattern in `CanonPTPService` ensures `withCheckedThrowingContinuation` is resumed exactly once — either by the PTP callback or by a 10-second `DispatchQueue` timeout, whichever comes first.

## Platform Differences (iPadOS vs macOS)

iPadOS requires two additional steps that macOS does not:
1. `NSCameraUsageDescription` in Info.plist (added via `INFOPLIST_KEY_` build setting)
2. `browser.requestControlAuthorization()` before sending PTP commands — wrapped in `#if os(iOS)` since the API doesn't exist on macOS

## Project Configuration

- Swift 6 strict concurrency: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `PBXFileSystemSynchronizedRootGroup` — new `.swift` files in `tether/` are automatically picked up by Xcode
- Deployment targets: iOS 26.0, macOS 26.0, visionOS 26.0
- App Sandbox enabled with USB access (`ENABLE_RESOURCE_ACCESS_USB = YES`)
