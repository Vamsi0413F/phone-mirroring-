import Foundation
import SwiftUI

/// Persisted settings. Video is always locked to Maximum Native Clarity (unscaled, 20 Mbps).
public final class SettingsModel: ObservableObject {
    public static let shared = SettingsModel()

    // Maximum native clarity: 0 = unconstrained device native resolution
    public let maxResolution: Int = 0
    public let videoBitrate: Int = 20_000_000 // 20 Mbps ultra-clear bitrate

    @AppStorage("dm_audioEnabled") public var audioEnabled: Bool = true // Audio forwarding
    @AppStorage("dm_audioDup")     public var audioDup: Bool     = true // Keep sound on phone too!

    private init() {}
}
