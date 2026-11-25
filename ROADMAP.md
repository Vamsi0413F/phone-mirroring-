# DroidMirror Roadmap & Phase Status

## Phase Status Summary

| Phase | Title | Status | Notes |
| :--- | :--- | :--- | :--- |
| **Phase 1** | **MVP (Live Hardware-Accelerated Video Pipeline)** | **COMPLETED** | Bundled `adb` + `scrcpy-server v3.1` (verified SHA-256), stale server cleanup, auto device discovery, RSA prompt handling, Annex-B NAL parser, AVSampleBufferDisplayLayer renderer, diagnostics exporter, signed app bundle. |
| **Phase 2** | **Native Client & Interactive Input** | *Upcoming* | Touch/mouse/scroll/keyboard injection over scrcpy control socket, aspect ratio window locking, phone bezel, rotation handling, bitrate/resolution settings. |
| **Phase 3** | **Wireless Debugging & Onboarding** | *Upcoming* | Guided pairing flow, QR code and pairing code (`_adb-tls-pairing._tcp`), mDNS auto-reconnect (`_adb-tls-connect._tcp`), persistent device storage. |
| **Phase 4** | **Experience Features** | *Upcoming* | Menu bar item, toolbar buttons (Home, Back, Recents, Power, Rotate), screen-off mirroring, clipboard sync, drag-and-drop file transfer, screenshots & recordings, always-on-top. |
| **Phase 5** | **Notification Mirroring Companion** | *Upcoming* | Android Kotlin service (`NotificationListenerService`), local notification forwarding, macOS native notifications (`UserNotifications`). |

---

## Phase 1 Detailed Deliverables

### What is Working:
1. **Pinned Binary Bundling:**
   - Bundled official universal `adb` binary (`arm64` + `x86_64`).
   - Pinned `scrcpy-server-v3.1` with SHA-256 digest validation (`958f0944a62f23b1f33a16e9eb14844c1a04b882ca175a738c16d23cb22b86c0`).
   - Bundled licenses and attributions (`scrcpy-LICENSE.txt`, `adb-NOTICE.txt`).
2. **ADB Lifecycle Management:**
   - Automatic termination of stale ADB server instances on launch.
   - Clean background daemon startup and periodic device polling (`adb devices -l`).
   - Clear UI indication for `device`, `unauthorized` (RSA prompt instructions), and `offline` states.
3. **Low-Latency Video Pipeline:**
   - Dynamic port allocation and `adb forward` socket management.
   - Low-latency TCP socket communication with the scrcpy server.
   - Annex-B NAL unit separation (extracting SPS and PPS parameter sets).
   - Dynamic AVCC translation and `CMSampleBuffer` generation.
   - Hardware-accelerated zero-copy rendering via `AVSampleBufferDisplayLayer` in SwiftUI with immediate display attachment (`kCMSampleAttachmentKey_DisplayImmediately`).
   - Real-time resolution detection and FPS counter.
4. **Hardened Runtime App Bundle:**
   - Non-sandboxed hardened runtime configuration signed with local development identity.
   - Working app bundle generated at `build/DroidMirror.app`.
   - All 9 unit tests passing for ADB output parsing and scrcpy packet/NAL decoding.
5. **Diagnostics:**
   - Live in-memory structured log capture.
   - "Diagnostics" sheet with one-click "Copy Diagnostics" button.

### What is Not Working / Deferred to Next Phases:
1. **Touch & Keyboard Input (Phase 2):** In Phase 1, touch and keyboard events are not yet injected into the phone (video is one-way display only).
2. **Bezel & Aspect Ratio Lock (Phase 2):** Window currently uses a clean standard view rather than a phone bezel frame.
3. **Audio Forwarding (Phase 2):** Audio streaming is disabled (`audio=false`) for Phase 1.
4. **Wireless Auto-Discovery (Phase 3):** mDNS Bonjour discovery (`_adb-tls-pairing._tcp` and `_adb-tls-connect._tcp`) will be implemented in Phase 3.
