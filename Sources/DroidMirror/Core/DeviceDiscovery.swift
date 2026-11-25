import Foundation
import SwiftUI

@MainActor
public final class DeviceDiscovery: ObservableObject {
    public static let shared = DeviceDiscovery()
    
    @Published public private(set) var devices: [DeviceModel] = []
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var isAdbReady: Bool = false
    
    private var timerTask: Task<Void, Never>?
    private let adb = AdbService.shared
    
    private init() {}
    
    /// Initializes ADB: starts ADB server if needed and begins polling.
    public func start() {
        guard timerTask == nil else { return }
        
        timerTask = Task { [weak self] in
            guard let self = self else { return }
            DiagnosticsLogger.shared.log("Starting ADB environment...", category: "DISCOVERY")
            
            // Connect to existing server or start daemon without killing active sessions/authorizations
            do {
                try await self.adb.startServer()
                self.isAdbReady = true
                DiagnosticsLogger.shared.log("ADB server ready.", category: "DISCOVERY")
            } catch {
                self.lastError = "Failed to start ADB server: \(error.localizedDescription)"
                DiagnosticsLogger.shared.log("ADB start failed: \(error)", category: "DISCOVERY", level: .error)
            }
            
            // Polling loop
            while !Task.isCancelled {
                await self.refreshDevices()
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            }
        }
    }
    
    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }
    
    /// Explicitly refreshes the connected device list.
    public func refreshDevices() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            let list = try await adb.getDevices()
            self.devices = list
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
            DiagnosticsLogger.shared.log("Device refresh error: \(error.localizedDescription)", category: "DISCOVERY", level: .warn)
        }
    }
    
    deinit {
        timerTask?.cancel()
    }
}
