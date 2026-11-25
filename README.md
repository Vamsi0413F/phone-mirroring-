# DroidMirror

An "iPhone Mirroring" experience for Android, built as a native macOS application in Swift and SwiftUI (macOS 13+).

---

## Architecture Overview

DroidMirror achieves low latency and a zero-terminal experience by embedding `adb` and the `scrcpy-server` binary, establishing socket tunnels directly from macOS, and decoding the H.264 video stream via Apple's native hardware frameworks:

```
┌─────────────────────────────────────────────────────────────┐
│                    DroidMirror UI (SwiftUI)                 │
│  Device Picker • Phone Viewport • Error Banners • Diagnostics│
└──────────────┬──────────────────────────────▲───────────────┘
               │                              │
┌──────────────▼──────────────────────────────┴───────────────┐
│                 ScrcpySession & VideoRenderer               │
│  Session lifecycle, dynamic forward ports, frame metrics    │
└──────────────┬──────────────────────────────▲───────────────┘
               │                              │
┌──────────────▼─────────────┐ ┌──────────────┴───────────────┐
│     H264AnnexBParser       │ │          TcpSocket           │
│  - Parameter set extraction│ │  - Low-latency TCP socket    │
│    (SPS / PPS)             │ │  - Fast buffer reading       │
│  - AVCC length-prefixing   │ │  - scrcpy framing reader     │
│  - AVSampleBufferDisplay   │ │                              │
└──────────────▲─────────────┘ └──────────────┬───────────────┘
               │                              │
┌──────────────┴──────────────────────────────▼───────────────┐
│                      AdbService & Core                      │
│  - Stale adb server cleanup & startup                       │
│  - Device discovery (`adb devices -l`)                      │
│  - Server push & tunnel configuration                       │
│  - Hardened runtime & bundled binary locator                │
└─────────────────────────────────────────────────────────────┘
```

---

## Pinned Protocol Specification (scrcpy v3.1)

DroidMirror pins **scrcpy v3.1** and validates its SHA-256 before running:

* **Server Version:** `3.1` (`ScrcpyConstants.version`)
* **SHA-256 Checksum:** `958f0944a62f23b1f33a16e9eb14844c1a04b882ca175a738c16d23cb22b86c0` (`ScrcpyConstants.serverSha256`)
* **Remote Path:** `/data/local/tmp/scrcpy-server.jar`
* **Server Invocation:**
  ```bash
  adb shell CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 3.1 \
    scid=<8-hex-digits> log_level=info video=true audio=false control=false \
    video_codec=h264 max_size=1920 video_bit_rate=8000000 max_fps=60 \
    tunnel_forward=true send_dummy_byte=true send_device_meta=true \
    send_codec_meta=true send_frame_meta=true cleanup=true
  ```

### Handshake & Wire Format:
1. **Dummy Byte:** 1 byte (`0x00`) confirming connection.
2. **Device Name:** 64 bytes (UTF-8, null-padded).
3. **Stream Metadata:**
   * Codec ID (4 bytes big-endian FourCC, e.g. `0x68323634` for H.264).
   * Initial Width (4 bytes big-endian).
   * Initial Height (4 bytes big-endian).
4. **Packet Loop (12-byte header + payload):**
   * 8 bytes: PTS (61 bits) + Keyframe Flag (bit 62) + Config Flag (bit 63).
   * 4 bytes: Payload length (big-endian).
   * Payload: Annex-B NAL units parsed for SPS/PPS parameters and wrapped into `CMSampleBuffer`s rendered by `AVSampleBufferDisplayLayer`.

---

## Building and Running

### Prerequisites
* macOS 13.0 or later
* Xcode 15+ / Command Line Tools (Apple Silicon & Intel supported)
* An Android device with USB debugging enabled

### Build the App Bundle
Run the build script from the repository root:
```bash
./build_app.sh
```
This compiles the release binary with `xcodebuild`, embeds bundled binaries and licenses into `build/DroidMirror.app`, and signs it with **Hardened Runtime** (`--options runtime --entitlements Sources/DroidMirror/Resources/Entitlements.plist --sign -`).

### Launch the App
```bash
open build/DroidMirror.app
```
Or run directly from terminal:
```bash
./build/DroidMirror.app/Contents/MacOS/DroidMirror
```

---

## Testing with an Android Device

1. Connect your Android phone to your Mac with a USB cable.
2. On your phone:
   * Go to **Settings > About Phone** and tap **Build Number** 7 times to enable Developer Options.
   * Go to **Settings > System > Developer Options** and enable **USB Debugging**.
3. Launch **DroidMirror**:
   * Stale ADB servers are automatically killed and restarted cleanly.
   * Your phone will show up in the device list.
   * If the device status displays `Unauthorized (Check Phone RSA Prompt)`, unlock your phone and tap **Allow USB debugging** (optionally check *"Always allow from this computer"*).
4. Click **Mirror**:
   * The app pushes `scrcpy-server.jar`, starts the forward tunnel, connects the video stream, and renders the phone screen live in hardware-accelerated 60 FPS H.264.
5. Click **Diagnostics** anytime to view and copy debug logs.

---

## Third-Party Licenses & Attributions

* **scrcpy-server**: Copyright 2018 Genymobile, Copyright 2018-2025 Romain Vimont. Licensed under the Apache License, Version 2.0 (`Resources/licenses/scrcpy-LICENSE.txt`).
* **Android Debug Bridge (adb)**: Bundled from the official Android SDK platform-tools. Licensed under the Android Open Source Project notice (`Resources/licenses/adb-NOTICE.txt`).
