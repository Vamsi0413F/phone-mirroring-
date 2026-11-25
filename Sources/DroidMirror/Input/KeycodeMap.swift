import AppKit

/// Maps macOS NSEvent keyCodes / special keys to Android AKEYCODE_* values.
/// Reference: android/keycodes.h (NDK) + NSEvent.SpecialKey
public enum KeycodeMap {

    // MARK: - Android key constants (AKEYCODE_*)
    public static let AKEYCODE_UNKNOWN:    UInt32 = 0
    public static let AKEYCODE_BACK:       UInt32 = 4
    public static let AKEYCODE_TAB:        UInt32 = 61
    public static let AKEYCODE_ENTER:      UInt32 = 66
    public static let AKEYCODE_DEL:        UInt32 = 67   // Backspace on Android
    public static let AKEYCODE_ESCAPE:     UInt32 = 111
    public static let AKEYCODE_DPAD_UP:    UInt32 = 19
    public static let AKEYCODE_DPAD_DOWN:  UInt32 = 20
    public static let AKEYCODE_DPAD_LEFT:  UInt32 = 21
    public static let AKEYCODE_DPAD_RIGHT: UInt32 = 22
    public static let AKEYCODE_MOVE_HOME:  UInt32 = 122
    public static let AKEYCODE_MOVE_END:   UInt32 = 123
    public static let AKEYCODE_PAGE_UP:    UInt32 = 92
    public static let AKEYCODE_PAGE_DOWN:  UInt32 = 93
    public static let AKEYCODE_FORWARD_DEL: UInt32 = 112 // Delete (forward)
    public static let AKEYCODE_SPACE:      UInt32 = 62

    // MARK: - Lookup

    /// Returns the Android keycode for a macOS hardware keyCode,
    /// or nil if the key should be handled as text injection instead.
    public static func androidKeycode(for event: NSEvent) -> UInt32? {
        // Check NSEvent.SpecialKey first
        if let special = event.specialKey {
            return specialKeyMap[special]
        }
        // Fallback: raw hardware keyCode table
        return hardwareKeyMap[event.keyCode]
    }

    // MARK: - Private tables

    /// NSEvent.SpecialKey → Android keycode
    private static let specialKeyMap: [NSEvent.SpecialKey: UInt32] = [
        .carriageReturn:    AKEYCODE_ENTER,
        .newline:           AKEYCODE_ENTER,
        .enter:             AKEYCODE_ENTER,
        .tab:               AKEYCODE_TAB,
        .backTab:           AKEYCODE_TAB,
        .delete:            AKEYCODE_DEL,
        .backspace:         AKEYCODE_DEL,
        .deleteForward:     AKEYCODE_FORWARD_DEL,
        // .escape is not an NSEvent.SpecialKey — handled via hardwareKeyMap (keyCode 53)
        .upArrow:           AKEYCODE_DPAD_UP,
        .downArrow:         AKEYCODE_DPAD_DOWN,
        .leftArrow:         AKEYCODE_DPAD_LEFT,
        .rightArrow:        AKEYCODE_DPAD_RIGHT,
        .home:              AKEYCODE_MOVE_HOME,
        .end:               AKEYCODE_MOVE_END,
        .pageUp:            AKEYCODE_PAGE_UP,
        .pageDown:          AKEYCODE_PAGE_DOWN,
    ]

    /// macOS hardware keyCode → Android keycode (US layout)
    /// Only non-printable / special keys that need keycode injection.
    private static let hardwareKeyMap: [UInt16: UInt32] = [
        36:  AKEYCODE_ENTER,       // Return
        76:  AKEYCODE_ENTER,       // Numpad Enter
        48:  AKEYCODE_TAB,         // Tab
        51:  AKEYCODE_DEL,         // Backspace/Delete
        117: AKEYCODE_FORWARD_DEL, // Delete (forward)
        53:  AKEYCODE_ESCAPE,      // Escape
        126: AKEYCODE_DPAD_UP,     // Up arrow
        125: AKEYCODE_DPAD_DOWN,   // Down arrow
        123: AKEYCODE_DPAD_LEFT,   // Left arrow
        124: AKEYCODE_DPAD_RIGHT,  // Right arrow
        115: AKEYCODE_MOVE_HOME,   // Home
        119: AKEYCODE_MOVE_END,    // End
        116: AKEYCODE_PAGE_UP,     // Page Up
        121: AKEYCODE_PAGE_DOWN,   // Page Down
        49:  AKEYCODE_SPACE,       // Space (fallback if no characters)
    ]

    /// True if this event should be sent as text injection rather than a keycode.
    public static func shouldInjectAsText(_ event: NSEvent) -> Bool {
        guard let chars = event.characters, !chars.isEmpty else { return false }
        // Don't inject text for control characters or if there's a mapped keycode
        let scalar = chars.unicodeScalars.first!
        guard scalar.value >= 0x20 && scalar.value != 0x7F else { return false }
        // No special key mapping means it's printable text
        return event.specialKey == nil && hardwareKeyMap[event.keyCode] == nil
    }
}
