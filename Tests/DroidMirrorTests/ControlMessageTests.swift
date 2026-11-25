import XCTest
@testable import DroidMirror

// MARK: - Control message encoding tests
// All byte layouts verified against scrcpy v3.1 source
// (server/src/main/java/com/genymobile/scrcpy/control/ControlMessage.java)
//
// floatToU16FP: clamp to [-1,1], multiply by 32768, clamp to Int16 range, reinterpret as UInt16
//   1.0  * 32768 = 32768 → clamp to Int16.max (32767) → UInt16(32767)
//   0.5  * 32768 = 16384 → Int16(16384) → UInt16(16384)
//   -1.0 * 32768 = -32768 → Int16.min → UInt16(32768) [0x8000]
//   0.0  * 32768 = 0

final class ControlMessageTests: XCTestCase {

    // MARK: floatToU16FP

    func testFloatToU16FP_zero() {
        XCTAssertEqual(ControlSocket.floatToU16FP(0.0), 0)
    }

    func testFloatToU16FP_one() {
        // 1.0 * 32768 = 32768 → clamped to Int16.max = 32767 → UInt16(32767)
        XCTAssertEqual(ControlSocket.floatToU16FP(1.0), UInt16(bitPattern: Int16.max))
    }

    func testFloatToU16FP_half() {
        // 0.5 * 32768 = 16384
        XCTAssertEqual(ControlSocket.floatToU16FP(0.5), 16384)
    }

    func testFloatToU16FP_negativeOne() {
        // -1.0 * 32768 = -32768 → Int16.min → UInt16(0x8000) = 32768
        XCTAssertEqual(ControlSocket.floatToU16FP(-1.0), UInt16(bitPattern: Int16.min))
    }

    func testFloatToU16FP_clampsAboveOne() {
        XCTAssertEqual(ControlSocket.floatToU16FP(5.0), ControlSocket.floatToU16FP(1.0))
    }

    func testFloatToU16FP_clampsBelowNegOne() {
        XCTAssertEqual(ControlSocket.floatToU16FP(-5.0), ControlSocket.floatToU16FP(-1.0))
    }

    // MARK: - INJECT_TOUCH_EVENT (type 2, 32 bytes)

    func testTouchEventEncoding() {
        var msg = Data()
        msg.append(ScrcpyConstants.msgInjectTouch) // 0x02
        msg.append(ScrcpyConstants.actionDown)     // 0x00
        appendBE64(&msg, UInt64.max)               // pointer_id = SC_POINTER_ID_MOUSE
        appendBE32(&msg, UInt32(bitPattern: Int32(100)))  // x = 100
        appendBE32(&msg, UInt32(bitPattern: Int32(200)))  // y = 200
        appendBE16(&msg, UInt16(1080))             // screen_w
        appendBE16(&msg, UInt16(2340))             // screen_h
        appendBE16(&msg, ControlSocket.floatToU16FP(1.0)) // pressure
        appendBE32(&msg, ScrcpyConstants.buttonPrimary)   // action_button
        appendBE32(&msg, ScrcpyConstants.buttonPrimary)   // buttons
        // Total: 1+1+8+4+4+2+2+2+4+4 = 32

        XCTAssertEqual(msg.count, 32, "INJECT_TOUCH_EVENT must be exactly 32 bytes")
        XCTAssertEqual(msg[0], 0x02, "Type byte must be 0x02 (INJECT_TOUCH_EVENT)")
        XCTAssertEqual(msg[1], 0x00, "Action DOWN must be 0x00")
        for i in 2..<10 { XCTAssertEqual(msg[i], 0xFF, "pointer_id byte \(i) must be 0xFF") }
        // x=100 = 0x00000064
        XCTAssertEqual(msg[10], 0x00); XCTAssertEqual(msg[11], 0x00)
        XCTAssertEqual(msg[12], 0x00); XCTAssertEqual(msg[13], 0x64)
        // y=200 = 0x000000C8
        XCTAssertEqual(msg[14], 0x00); XCTAssertEqual(msg[15], 0x00)
        XCTAssertEqual(msg[16], 0x00); XCTAssertEqual(msg[17], 0xC8)
        // screen_w=1080 = 0x0438
        XCTAssertEqual(msg[18], 0x04); XCTAssertEqual(msg[19], 0x38)
        // screen_h=2340 = 0x0924
        XCTAssertEqual(msg[20], 0x09); XCTAssertEqual(msg[21], 0x24)
    }

    // MARK: - INJECT_SCROLL_EVENT (type 3, 21 bytes)

    func testScrollEventEncoding() {
        var msg = Data()
        msg.append(ScrcpyConstants.msgInjectScroll)
        appendBE32(&msg, UInt32(bitPattern: Int32(50)))
        appendBE32(&msg, UInt32(bitPattern: Int32(100)))
        appendBE16(&msg, UInt16(1080))
        appendBE16(&msg, UInt16(2340))
        appendBE16(&msg, ControlSocket.floatToU16FP(0.0))
        appendBE16(&msg, ControlSocket.floatToU16FP(0.5))
        appendBE32(&msg, 0)
        // Total: 1+4+4+2+2+2+2+4 = 21

        XCTAssertEqual(msg.count, 21, "INJECT_SCROLL_EVENT must be exactly 21 bytes")
        XCTAssertEqual(msg[0], 0x03, "Type byte must be 0x03 (INJECT_SCROLL_EVENT)")
    }

    // MARK: - INJECT_KEYCODE (type 0, 14 bytes)

    func testKeycodeEncoding() {
        var msg = Data()
        msg.append(ScrcpyConstants.msgInjectKeycode) // 0x00
        msg.append(ScrcpyConstants.actionDown)        // 0x00
        appendBE32(&msg, 66)   // AKEYCODE_ENTER
        appendBE32(&msg, 0)    // repeat
        appendBE32(&msg, 0)    // metastate
        // Total: 1+1+4+4+4 = 14

        XCTAssertEqual(msg.count, 14, "INJECT_KEYCODE must be exactly 14 bytes")
        XCTAssertEqual(msg[0], 0x00)
        XCTAssertEqual(msg[1], 0x00)
        // keycode 66 = 0x00000042
        XCTAssertEqual(msg[2], 0x00); XCTAssertEqual(msg[3], 0x00)
        XCTAssertEqual(msg[4], 0x00); XCTAssertEqual(msg[5], 0x42)
    }

    // MARK: - INJECT_TEXT (type 1, 5 + N bytes)

    func testTextEncoding() {
        let text = "Hi"
        let utf8 = text.data(using: .utf8)!
        var msg = Data()
        msg.append(ScrcpyConstants.msgInjectText)
        appendBE32(&msg, UInt32(utf8.count))
        msg.append(utf8)
        // Total: 1 + 4 + 2 = 7

        XCTAssertEqual(msg.count, 7, "INJECT_TEXT('Hi') must be 7 bytes")
        XCTAssertEqual(msg[0], 0x01)
        XCTAssertEqual(msg[1], 0x00); XCTAssertEqual(msg[2], 0x00)
        XCTAssertEqual(msg[3], 0x00); XCTAssertEqual(msg[4], 0x02)
        XCTAssertEqual(msg[5], UInt8(ascii: "H"))
        XCTAssertEqual(msg[6], UInt8(ascii: "i"))
    }

    // MARK: - BACK_OR_SCREEN_ON (type 4, 2 bytes)

    func testBackMessageEncoding() {
        var msg = Data()
        msg.append(ScrcpyConstants.msgBackOrScreenOn) // 0x04
        msg.append(ScrcpyConstants.actionDown)         // 0x00
        // Total: 2

        XCTAssertEqual(msg.count, 2, "BACK_OR_SCREEN_ON must be exactly 2 bytes")
        XCTAssertEqual(msg[0], 0x04)
        XCTAssertEqual(msg[1], 0x00)
    }

    // MARK: - Helpers

    private func appendBE16(_ data: inout Data, _ v: UInt16) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
    private func appendBE32(_ data: inout Data, _ v: UInt32) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
    private func appendBE64(_ data: inout Data, _ v: UInt64) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
}
