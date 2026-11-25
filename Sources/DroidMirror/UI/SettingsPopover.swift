import SwiftUI

public struct SettingsPopover: View {
    @ObservedObject public var settings: SettingsModel
    
    public init(settings: SettingsModel = .shared) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.accentColor)
                Text("Settings")
                    .font(.headline)
            }
            .padding(.bottom, 2)

            // Video clarity info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.tv")
                        .foregroundColor(.green)
                    Text("Maximum Clarity Active")
                        .font(.subheadline.bold())
                }
                Text("Streams at 100% native unscaled display resolution at 20 Mbps with zero compression downsampling.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)

            Divider()

            // Audio settings
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Forward Audio to Mac", isOn: $settings.audioEnabled)
                    .font(.subheadline.bold())
                    .help("Streams device audio directly to Mac speakers in native uncompressed PCM format (Android 11+)")

                if settings.audioEnabled {
                    Toggle("Keep Sound on Phone (Audio Dup)", isOn: $settings.audioDup)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.leading, 18)
                        .help("Keeps audio playing on the phone while also forwarding it to the Mac (Android 13+)")
                }
            }

            Divider()

            Text("Audio settings take effect on next connection.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .frame(minWidth: 300)
    }
}
