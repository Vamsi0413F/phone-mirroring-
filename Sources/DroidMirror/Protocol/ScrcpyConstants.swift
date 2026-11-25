import Foundation

/// Pinned scrcpy release metadata and protocol constants.
public enum ScrcpyConstants {
    /// Pinned scrcpy release version.
    public static let version = "3.1"
    
    /// Expected SHA-256 digest of scrcpy-server-v3.1
    public static let serverSha256 = "958f0944a62f23b1f33a16e9eb14844c1a04b882ca175a738c16d23cb22b86c0"
    
    /// Server binary filename bundled in app resources
    public static let bundledServerFilename = "scrcpy-server-v3.1"
    
    /// Remote destination path on device
    public static let remoteServerPath = "/data/local/tmp/scrcpy-server.jar"
    
    /// Name prefix for the local abstract socket created by scrcpy-server
    public static let abstractSocketBase = "scrcpy"
    
    /// Scrcpy codec identification fourcc for H.264: "h264" = 0x68323634
    public static let videoCodecH264: UInt32 = 0x68323634
    
    /// Scrcpy codec identification fourcc for H.265: "h265" = 0x68323635
    public static let videoCodecH265: UInt32 = 0x68323635
    
    /// Device name buffer length in header (64 bytes, null-padded UTF-8)
    public static let deviceNameLength = 64
    
    /// Video metadata header length: 4 bytes codec ID + 4 bytes width + 4 bytes height
    public static let videoMetaLength = 12
    
    /// Packet header length: 8 bytes PTS/flags + 4 bytes size
    public static let packetHeaderLength = 12
    
    /// Config packet bit flag in 64-bit PTS field (bit 63)
    public static let ptsFlagConfig: UInt64 = 1 << 63
    
    /// Keyframe bit flag in 64-bit PTS field (bit 62)
    public static let ptsFlagKeyframe: UInt64 = 1 << 62
    
    /// Mask for extracting the actual presentation timestamp value
    public static let ptsValueMask: UInt64 = ~(ptsFlagConfig | ptsFlagKeyframe)

    // MARK: - Control message type bytes (scrcpy v3.1)
    public static let msgInjectKeycode:   UInt8 = 0
    public static let msgInjectText:      UInt8 = 1
    public static let msgInjectTouch:     UInt8 = 2
    public static let msgInjectScroll:    UInt8 = 3
    public static let msgBackOrScreenOn:  UInt8 = 4

    // MARK: - Android MotionEvent action values
    public static let actionDown: UInt8 = 0
    public static let actionUp:   UInt8 = 1
    public static let actionMove: UInt8 = 2

    // MARK: - Android buttons mask
    public static let buttonPrimary:   UInt32 = 1 << 0   // BUTTON_PRIMARY
    public static let buttonSecondary: UInt32 = 1 << 1   // BUTTON_SECONDARY

    // MARK: - Pointer IDs
    public static let pointerIdMouse: UInt64 = UInt64.max  // SC_POINTER_ID_MOUSE = UINT64_MAX
    public static let pointerIdGenericFinger: UInt64 = UInt64.max - 1 // SC_POINTER_ID_GENERIC_FINGER (-2)

    // MARK: - Audio stream header magic (scrcpy v3.1)
    // Audio codec IDs: "opus" = 0x6f707573, "raw\0" = 0x00726177
    public static let audioCodecOpus: UInt32 = 0x6f707573
    public static let audioCodecRaw:  UInt32 = 0x00726177
}
