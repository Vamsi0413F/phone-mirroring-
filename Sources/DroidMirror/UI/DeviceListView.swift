import SwiftUI

public struct DeviceListView: View {
    @ObservedObject public var discovery: DeviceDiscovery
    public let onSelectDevice: (DeviceModel) -> Void
    @State private var showingDiagnostics = false
    @State private var showingSettings = false
    @State private var triggeringAuth = false
    @State private var restartingAdb = false
    
    public init(discovery: DeviceDiscovery, onSelectDevice: @escaping (DeviceModel) -> Void) {
        self.discovery = discovery
        self.onSelectDevice = onSelectDevice
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DroidMirror")
                        .font(.title2.bold())
                    Text("Select a connected Android device to begin mirroring")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()

                Button(action: { showingSettings = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                }
                .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                    SettingsPopover(settings: SettingsModel.shared)
                }
                .help("Configure resolution, bitrate, and audio")
                
                Button(action: {
                    restartingAdb = true
                    Task {
                        await AdbService.shared.restartServer()
                        await discovery.refreshDevices()
                        restartingAdb = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(restartingAdb ? "Resetting..." : "Reset ADB")
                    }
                }
                .disabled(restartingAdb)
                .help("Restarts the ADB daemon to force the RSA authorization prompt on OnePlus and other devices")

                Button(action: {
                    triggeringAuth = true
                    Task {
                        await AdbService.shared.triggerAuthorization()
                        await discovery.refreshDevices()
                        triggeringAuth = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                        Text(triggeringAuth ? "Triggering..." : "Trigger Phone Prompt")
                    }
                }
                .disabled(triggeringAuth)
                .help("Sends an authorization renegotiation ping to force the RSA fingerprint prompt on OnePlus/Android screens")
                
                Button(action: {
                    Task {
                        await discovery.refreshDevices()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(discovery.isRefreshing ? 360 : 0))
                            .animation(discovery.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: discovery.isRefreshing)
                        Text("Refresh")
                    }
                }
                .disabled(discovery.isRefreshing)
                
                Button(action: { showingDiagnostics = true }) {
                    Image(systemName: "stethoscope")
                    Text("Diagnostics")
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Content
            if discovery.devices.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(discovery.devices) { device in
                        deviceRow(device)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView()
        }
    }
    
    private func deviceRow(_ device: DeviceModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: device.transport == .usb ? "cable.connector.horizontal" : "wifi")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .font(.headline)
                    
                    HStack(spacing: 6) {
                        Text("Serial: \(device.serial)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(device.transport.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                StatusBadgeView(state: device.state)
                
                if device.state == .unauthorized {
                    Button("Show Prompt on Phone") {
                        Task {
                            await AdbService.shared.triggerAuthorization(serial: device.serial)
                            await discovery.refreshDevices()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: { onSelectDevice(device) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Mirror")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!device.state.isReady)
            }
            
            // RSA Prompt alert if unauthorized
            if device.state == .unauthorized {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.orange)
                        Text("Action Required: Unlock your phone and tap 'Allow USB debugging'.")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                    Text("💡 If no prompt appeared:\n• Swipe down notification shade on phone > tap 'Charging via USB' > change to 'File Transfer' (MTP).\n• Then click 'Show Prompt on Phone' or 'Reset ADB' above.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 6)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "iphone.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Android Devices Detected")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                checklistRow(step: "1", text: "Connect your Android device with a USB data cable.")
                checklistRow(step: "2", text: "OnePlus / OxygenOS: Swipe down from top > tap 'Charging via USB' > change to 'File Transfer'.")
                checklistRow(step: "3", text: "Settings > About Device > tap 'Version / Build Number' 7 times to enable Developer Options.")
                checklistRow(step: "4", text: "Settings > System / Developer Options > Turn ON 'USB Debugging'.")
                checklistRow(step: "5", text: "Unlock your phone to accept the RSA fingerprint prompt.")
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .frame(maxWidth: 520)
            
            HStack(spacing: 12) {
                Button("Trigger Phone Prompt") {
                    triggeringAuth = true
                    Task {
                        await AdbService.shared.triggerAuthorization()
                        await discovery.refreshDevices()
                        triggeringAuth = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(triggeringAuth)
                
                Button("Scan Again") {
                    Task {
                        await discovery.refreshDevices()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
            
            Spacer()
        }
        .padding()
    }
    
    private func checklistRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(step)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
