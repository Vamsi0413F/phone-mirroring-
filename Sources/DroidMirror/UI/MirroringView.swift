import SwiftUI

public struct MirroringView: View {
    @ObservedObject public var session: ScrcpySession
    @ObservedObject private var settings = SettingsModel.shared
    public let onDisconnect: () -> Void

    @State private var showSettings = false
    
    public init(session: ScrcpySession, onDisconnect: @escaping () -> Void) {
        self.session = session
        self.onDisconnect = onDisconnect
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 10) {
                // Status dot + device name
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.state == .streaming ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(session.deviceName.isEmpty
                         ? (session.activeDevice?.displayName ?? "Android Device")
                         : session.deviceName)
                        .font(.system(size: 13, weight: .semibold))
                }
                
                // Resolution badge
                if session.streamDimensions != .zero {
                    Text("\(Int(session.streamDimensions.width))×\(Int(session.streamDimensions.height))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                
                // FPS
                if session.currentFps > 0 {
                    Text("\(session.currentFps) FPS")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                }
                
                Spacer()

                // Settings gear
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .popover(isPresented: $showSettings, arrowEdge: .top) {
                    SettingsPopover(settings: settings)
                }
                .help("Settings (resolution, bitrate, audio)")

                // Disconnect
                Button(action: {
                    session.stop()
                    onDisconnect()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Disconnect")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // ── Video viewport ────────────────────────────────────────────
            ZStack {
                Color.black.ignoresSafeArea()
                
                SampleBufferRendererView(renderer: session.renderer, session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // State overlays
                if session.state != .streaming {
                    VStack(spacing: 14) {
                        switch session.state {
                        case .idle, .pushingServer, .startingServer, .connectingSocket:
                            ProgressView().controlSize(.large)
                            Text(session.state.description)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                        case .streaming:
                            EmptyView()
                            
                        case .failed(let err):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.orange)
                            Text("Mirroring Interrupted")
                                .font(.headline).foregroundColor(.white)
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Button("Return to Device List") {
                                session.stop(); onDisconnect()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                            
                        case .disconnected:
                            Image(systemName: "cable.connector.slash")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Device Disconnected")
                                .font(.headline).foregroundColor(.white)
                            Button("Back to Devices") { onDisconnect() }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 8)
                        }
                    }
                    .padding(32)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(12)
                }
            }
        }
    }
}
