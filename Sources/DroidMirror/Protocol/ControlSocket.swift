import Foundation

/// Thread-safe write-only control channel to the scrcpy server (v3.1).
///
/// Wire formats verified against scrcpy v3.1 source (server/src/main/java/com/genymobile/scrcpy/control/):
///   INJECT_TOUCH_EVENT  (type 2) = 32 bytes total
///   INJECT_SCROLL_EVENT (type 3) = 21 bytes total
///   INJECT_KEYCODE      (type 0) = 14 bytes total
///   INJECT_TEXT         (type 1) = 5 + N bytes
///   BACK_OR_SCREEN_ON   (type 4) =  2 bytes total
public final class ControlSocket: @unchecked Sendable {
    private let socket = TcpSocket()
    private let writeLock = NSLock()

    public init() {}

    // MARK: - Connection

    /// Connects to the same forwarded port as the video socket.
    /// Call only after the video handshake has completed successfully.
    /// No dummy byte is sent or received on the control connection.
    public func connect(port: UInt16, retryCount: Int = 40, retryDelayMs: UInt32 = 100) -> Bool {
        for attempt in 1...retryCount {
            if socket.connectRaw(port: port) {
                DiagnosticsLogger.shared.log(
                    "Control socket connected on 127.0.0.1:\(port) (attempt \(attempt))",
                    category: "CONTROL", level: .info)
                return true
            }
            usleep(retryDelayMs * 1_000)
        }
        DiagnosticsLogger.shared.log(
            "Control socket failed to connect after \(retryCount) attempts",
            category: "CONTROL", level: .error)
        return false
    }

    public func close() {
        socket.close()
    }

    // MARK: - Message senders

    /// INJECT_TOUCH_EVENT — 32 bytes.
    /// action: 0=down 1=up 2=move
    /// pointerId: use ScrcpyConstants.pointerIdMouse for mouse
    /// x, y: device pixel coords
    /// screenW, screenH: current device frame size
    /// pressure: 0.0 … 1.0  (0 for up, 1 for down/move)
    /// actionButton / buttons: Android button masks
    public func sendTouchEvent(
        action: UInt8,
        pointerId: UInt64,
        x: Int32, y: Int32,
        screenW: UInt16, screenH: UInt16,
        pressure: Float,
        actionButton: UInt32,
        buttons: UInt32
    ) {
        var msg = Data(capacity: 32)
        msg.append(ScrcpyConstants.msgInjectTouch)   // 1 byte  type
        msg.append(action)                            // 1 byte  action
        msg.appendBE64(pointerId)                    // 8 bytes pointer_id
        msg.appendBE32(UInt32(bitPattern: x))        // 4 bytes x
        msg.appendBE32(UInt32(bitPattern: y))        // 4 bytes y
        msg.appendBE16(screenW)                      // 2 bytes screen_w
        msg.appendBE16(screenH)                      // 2 bytes screen_h
        msg.appendBE16(floatToU16FP(pressure))       // 2 bytes pressure (u16fp)
        msg.appendBE32(actionButton)                 // 4 bytes action_button
        msg.appendBE32(buttons)                      // 4 bytes buttons
        // Total: 1+1+8+4+4+2+2+2+4+4 = 32 ✓
        writeMsg(msg)
    }

    /// INJECT_SCROLL_EVENT — 21 bytes.
    /// hscroll / vscroll: float, positive = right/up, negative = left/down
    public func sendScrollEvent(
        x: Int32, y: Int32,
        screenW: UInt16, screenH: UInt16,
        hscroll: Float, vscroll: Float,
        buttons: UInt32
    ) {
        var msg = Data(capacity: 21)
        msg.append(ScrcpyConstants.msgInjectScroll)  // 1 byte  type
        msg.appendBE32(UInt32(bitPattern: x))        // 4 bytes x
        msg.appendBE32(UInt32(bitPattern: y))        // 4 bytes y
        msg.appendBE16(screenW)                      // 2 bytes screen_w
        msg.appendBE16(screenH)                      // 2 bytes screen_h
        msg.appendBE16(floatToU16FP(hscroll))        // 2 bytes hscroll
        msg.appendBE16(floatToU16FP(vscroll))        // 2 bytes vscroll
        msg.appendBE32(buttons)                      // 4 bytes buttons
        // Total: 1+4+4+2+2+2+2+4 = 21 ✓
        writeMsg(msg)
    }

    /// INJECT_KEYCODE — 14 bytes.
    /// action: 0=down 1=up
    /// keycode: Android AKEYCODE_* value
    public func sendKeycode(
        action: UInt8,
        keycode: UInt32,
        repeat repeatCount: UInt32,
        metastate: UInt32
    ) {
        var msg = Data(capacity: 14)
        msg.append(ScrcpyConstants.msgInjectKeycode) // 1 byte  type
        msg.append(action)                           // 1 byte  action
        msg.appendBE32(keycode)                      // 4 bytes keycode
        msg.appendBE32(repeatCount)                  // 4 bytes repeat
        msg.appendBE32(metastate)                    // 4 bytes metastate
        // Total: 1+1+4+4+4 = 14 ✓
        writeMsg(msg)
    }

    /// INJECT_TEXT — 5 + N bytes.
    public func sendText(_ text: String) {
        guard let utf8 = text.data(using: .utf8), !utf8.isEmpty else { return }
        var msg = Data(capacity: 5 + utf8.count)
        msg.append(ScrcpyConstants.msgInjectText)    // 1 byte  type
        msg.appendBE32(UInt32(utf8.count))           // 4 bytes length
        msg.append(utf8)                             // N bytes text
        writeMsg(msg)
    }

    /// BACK_OR_SCREEN_ON — 2 bytes.
    public func sendBackOrScreenOn(action: UInt8) {
        var msg = Data(capacity: 2)
        msg.append(ScrcpyConstants.msgBackOrScreenOn) // 1 byte type
        msg.append(action)                            // 1 byte action
        writeMsg(msg)
    }

    // MARK: - Convenience helpers

    /// Sends a full tap: down followed immediately by up.
    public func sendTap(x: Int32, y: Int32, screenW: UInt16, screenH: UInt16) {
        sendTouchEvent(action: ScrcpyConstants.actionDown,
                       pointerId: ScrcpyConstants.pointerIdMouse,
                       x: x, y: y, screenW: screenW, screenH: screenH,
                       pressure: 1.0,
                       actionButton: ScrcpyConstants.buttonPrimary,
                       buttons: ScrcpyConstants.buttonPrimary)
        sendTouchEvent(action: ScrcpyConstants.actionUp,
                       pointerId: ScrcpyConstants.pointerIdMouse,
                       x: x, y: y, screenW: screenW, screenH: screenH,
                       pressure: 0.0,
                       actionButton: ScrcpyConstants.buttonPrimary,
                       buttons: 0)
    }

    // MARK: - Private

    private func writeMsg(_ data: Data) {
        writeLock.lock()
        defer { writeLock.unlock() }
        if !socket.writeAll(data) {
            DiagnosticsLogger.shared.log(
                "Control socket write failed (\(data.count) bytes)", category: "CONTROL", level: .warn)
        }
    }

    // sc_float_to_u16fp: clamp to [-1,1], multiply by 0x8000, reinterpret as UInt16
    static func floatToU16FP(_ v: Float) -> UInt16 {
        let clamped = max(-1.0, min(1.0, v))
        // Multiply by 0x8000 (32768). Result range: [-32768, 32768].
        // Int16 can hold [-32768, 32767], so we clamp the integer to avoid overflow.
        let raw = Int32(clamped * Float(0x8000))
        let i16 = Int16(max(Int32(Int16.min), min(Int32(Int16.max), raw)))
        return UInt16(bitPattern: i16)
    }

    private func floatToU16FP(_ v: Float) -> UInt16 {
        return ControlSocket.floatToU16FP(v)
    }
}

// MARK: - Data big-endian helpers

private extension Data {
    mutating func appendBE16(_ v: UInt16) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { self.append(contentsOf: $0) }
    }
    mutating func appendBE32(_ v: UInt32) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { self.append(contentsOf: $0) }
    }
    mutating func appendBE64(_ v: UInt64) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { self.append(contentsOf: $0) }
    }
}
