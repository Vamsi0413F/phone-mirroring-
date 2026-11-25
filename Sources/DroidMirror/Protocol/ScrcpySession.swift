import Foundation
import CoreMedia
import SwiftUI

public enum SessionState: Equatable, Sendable {
    case idle
    case pushingServer
    case startingServer
    case connectingSocket
    case streaming
    case disconnected
    case failed(String)
    
    public var description: String {
        switch self {
        case .idle:              return "Idle"
        case .pushingServer:     return "Pushing server to device..."
        case .startingServer:    return "Starting scrcpy server..."
        case .connectingSocket:  return "Connecting video socket..."
        case .streaming:         return "Live Stream Active"
        case .disconnected:      return "Disconnected"
        case .failed(let err):   return "Error: \(err)"
        }
    }
}

@MainActor
public final class ScrcpySession: ObservableObject {
    @Published public private(set) var state: SessionState = .idle
    @Published public private(set) var deviceName: String = ""
    @Published public private(set) var streamDimensions: CGSize = .zero
    @Published public private(set) var frameCount: Int = 0
    @Published public private(set) var currentFps: Int = 0
    @Published public private(set) var activeDevice: DeviceModel? = nil
    
    public let renderer = VideoRenderer()

    /// The active control channel — nil until control socket is connected.
    public private(set) var controlSocket: ControlSocket?
    
    private var streamTask: Task<Void, Never>?
    private var orientationTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var isAdaptingOrientation = false
    
    private var serverProcess: Process?
    private var forwardPort: Int = 0
    private var serial: String = ""
    private var scid: String = ""
    private var reconnectAttempts = 0
    private static let maxReconnectAttempts = 3
    
    private let parser = H264AnnexBParser()
    private let adb = AdbService.shared
    private let settings = SettingsModel.shared
    
    public init() {}
    
    // MARK: - Public API

    public func startMirroring(device: DeviceModel) {
        guard state != .streaming && state != .startingServer && state != .pushingServer else { return }
        
        self.activeDevice = device
        self.serial = device.serial
        self.state = .pushingServer
        self.frameCount = 0
        self.currentFps = 0
        self.reconnectAttempts = 0
        
        let randomVal = UInt32.random(in: 0x10000000...0x7fffffff)
        self.scid = String(format: "%08x", randomVal)
        self.forwardPort = Int.random(in: 27183...27999)
        
        streamTask = Task { [weak self] in
            guard let self = self else { return }
            await self.runSessionPipeline()
        }
    }
    
    // MARK: - Session pipeline

    private func runSessionPipeline() async {
        let targetSerial = self.serial
        let port = self.forwardPort
        let socketName = "scrcpy_\(self.scid)"
        
        do {
            self.state = .pushingServer
            try await adb.pushServer(to: targetSerial)
            
            self.state = .startingServer
            try await adb.setupForward(serial: targetSerial, localPort: port, abstractSocket: socketName)
            
            let audioEnabled = settings.audioEnabled
            let proc = try adb.spawnServerProcess(
                serial: targetSerial,
                scid: self.scid,
                maxSize: settings.maxResolution,
                bitRate: settings.videoBitrate,
                maxFps: 60,
                tunnelForward: true,
                control: true,
                audio: audioEnabled,
                audioDup: settings.audioDup
            )
            self.serverProcess = proc
            
            // --- 1. Video socket (first connection + handshake) ---
            self.state = .connectingSocket
            let videoSocket = TcpSocket()
            let connected = await Task.detached {
                return videoSocket.connectAndHandshake(port: UInt16(port), retryCount: 60, retryDelayMs: 100)
            }.value
            
            guard connected else {
                throw AdbError.processFailed(command: "socket.handshake", exitCode: -1,
                    stderr: "Failed to connect video socket on port \(port)")
            }

            // --- 2. Audio socket (SECOND connection in scrcpy v3.1, ONLY if audio is enabled) ---
            if audioEnabled {
                let audioReceiver = AudioReceiver()
                audioTask = Task.detached {
                    audioReceiver.connectAndRun(port: UInt16(port), retryCount: 30, retryDelayMs: 150)
                }
                // Allow audio socket to establish before control socket connects
                try? await Task.sleep(nanoseconds: 120_000_000)
            }

            // --- 3. Control socket (THIRD connection if audioEnabled, or SECOND if no audio) ---
            let ctrl = ControlSocket()
            let ctrlOK = await Task.detached {
                return ctrl.connect(port: UInt16(port), retryCount: 40, retryDelayMs: 100)
            }.value
            if ctrlOK {
                self.controlSocket = ctrl
                DiagnosticsLogger.shared.log("Control socket ready for touch/input injection", category: "SESSION", level: .info)
            } else {
                DiagnosticsLogger.shared.log("Control socket failed — input injection disabled", category: "SESSION", level: .warn)
            }
            
            self.reconnectAttempts = 0
            await self.readStream(socket: videoSocket)
            
        } catch {
            DiagnosticsLogger.shared.log("Session failed: \(error.localizedDescription)", category: "SESSION", level: .error)
            
            // Auto-reconnect on transient failure
            if reconnectAttempts < Self.maxReconnectAttempts && state != .disconnected {
                reconnectAttempts += 1
                DiagnosticsLogger.shared.log(
                    "Auto-reconnect attempt \(reconnectAttempts)/\(Self.maxReconnectAttempts)...",
                    category: "SESSION", level: .info)
                teardown(port: port, serial: targetSerial)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await runSessionPipeline()
            } else {
                self.state = .failed(error.localizedDescription)
                teardown(port: port, serial: targetSerial)
            }
        }
    }
    
    private func readStream(socket: TcpSocket) async {
        let parser = self.parser
        let renderer = self.renderer
        let targetSerial = self.serial
        
        await Task.detached { [weak self] in
            // Read 64-byte device name
            guard let nameData = socket.readExact(count: ScrcpyConstants.deviceNameLength) else {
                DiagnosticsLogger.shared.log("Failed reading device name", category: "PROTOCOL", level: .error)
                await self?.updateState(.failed("Failed to read device name"))
                return
            }
            let rawString = String(data: nameData, encoding: .utf8) ?? "Android Device"
            let sanitizedName = rawString.components(separatedBy: "\0").first ?? rawString
            DiagnosticsLogger.shared.log("Device handshake complete: '\(sanitizedName)'", category: "PROTOCOL", level: .info)
            await self?.setDeviceName(sanitizedName)
            
            // Read 12-byte video metadata
            guard let metaData = socket.readExact(count: ScrcpyConstants.videoMetaLength) else {
                DiagnosticsLogger.shared.log("Failed reading video metadata", category: "PROTOCOL", level: .error)
                await self?.updateState(.failed("Failed to read stream metadata"))
                return
            }
            let codecId      = metaData.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let initialWidth = metaData.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let initialHeight = metaData.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            DiagnosticsLogger.shared.log("Video Meta: Codec=0x\(String(format: "%08x", codecId)), \(initialWidth)x\(initialHeight)", category: "PROTOCOL", level: .info)
            
            let initialSize = CGSize(width: Int(initialWidth), height: Int(initialHeight))
            await self?.handleDimensionChange(initialSize)
            await self?.updateState(.streaming)
            await self?.startOrientationWatcher(serial: targetSerial)
            
            var fpsCounter = 0
            var lastFpsCheck = Date()
            
            while socket.isConnected && !Task.isCancelled {
                guard let headerData = socket.readExact(count: ScrcpyConstants.packetHeaderLength) else {
                    DiagnosticsLogger.shared.log("Packet header stream ended", category: "STREAM", level: .info)
                    break
                }
                
                let ptsAndFlags = headerData.subdata(in: 0..<8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                let packetSize  = headerData.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                
                guard packetSize > 0 && packetSize < 20_000_000 else {
                    DiagnosticsLogger.shared.log("Invalid packet size: \(packetSize)", category: "STREAM", level: .error)
                    break
                }
                
                guard let payload = socket.readExact(count: Int(packetSize)) else {
                    DiagnosticsLogger.shared.log("Unexpected end of packet payload", category: "STREAM", level: .error)
                    break
                }
                
                let isConfig   = (ptsAndFlags & ScrcpyConstants.ptsFlagConfig)   != 0
                let isKeyframe = (ptsAndFlags & ScrcpyConstants.ptsFlagKeyframe) != 0
                let ptsMicros  = ptsAndFlags & ScrcpyConstants.ptsValueMask
                let nalUnits   = parser.extractNalUnits(from: payload)
                
                if isConfig {
                    DiagnosticsLogger.shared.log(
                        "Video config packet: \(packetSize) bytes, \(nalUnits.count) NAL units",
                        category: "CONFIG", level: .info)
                    if parser.updateParameters(from: nalUnits), let dim = parser.dimensions {
                        await self?.handleDimensionChange(dim)
                    }
                    continue
                }
                
                if isKeyframe || nalUnits.contains(where: { $0.isSPS || $0.isPPS }) {
                    if parser.updateParameters(from: nalUnits), let dim = parser.dimensions {
                        await self?.handleDimensionChange(dim)
                    }
                }
                
                guard parser.formatDescription != nil else { continue }
                
                let avccData = parser.createAvccBuffer(from: nalUnits)
                guard !avccData.isEmpty else { continue }
                
                let pts = CMTime(value: Int64(ptsMicros), timescale: 1_000_000)
                if let sampleBuffer = parser.makeSampleBuffer(from: avccData, pts: pts) {
                    renderer.render(sampleBuffer: sampleBuffer)
                    fpsCounter += 1
                    
                    let now = Date()
                    if now.timeIntervalSince(lastFpsCheck) >= 1.0 {
                        let fps = fpsCounter
                        fpsCounter = 0
                        lastFpsCheck = now
                        await self?.incrementFrame(fps: fps)
                    }
                }
            }
            
            await self?.updateState(.disconnected)
        }.value
        
        teardown(port: self.forwardPort, serial: self.serial)
    }
    
    // MARK: - Orientation watcher

    private func startOrientationWatcher(serial: String) {
        orientationTask?.cancel()
        orientationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard let self = self, self.state == .streaming, !Task.isCancelled else { break }
                
                guard let orientation = await self.adb.getSurfaceOrientation(serial: serial) else { continue }
                
                let isPhysicalLandscape = (orientation == 1 || orientation == 3)
                let currentDims = self.streamDimensions
                guard currentDims.width > 0 && currentDims.height > 0 else { continue }
                let isStreamLandscape = (currentDims.width > currentDims.height)
                
                if isPhysicalLandscape != isStreamLandscape && !self.isAdaptingOrientation {
                    self.isAdaptingOrientation = true
                    DiagnosticsLogger.shared.log(
                        "Orientation change detected: SurfaceOrientation=\(orientation). Adapting orientation and re-launching stream...",
                        category: "SESSION", level: .info)
                    
                    // Immediately adapt dimensions and resize window so video fills the screen
                    let swapped = CGSize(width: currentDims.height, height: currentDims.width)
                    await self.handleDimensionChange(swapped)
                    
                    await self.restartStreamForOrientationChange()
                    self.isAdaptingOrientation = false
                }
            }
        }
    }
    
    private func restartStreamForOrientationChange() async {
        guard activeDevice != nil, state == .streaming else { return }
        DiagnosticsLogger.shared.log("Re-launching scrcpy server for orientation update...", category: "SESSION", level: .info)
        
        streamTask?.cancel()
        streamTask = nil
        controlSocket?.close()
        controlSocket = nil
        audioTask?.cancel()
        audioTask = nil
        if let proc = serverProcess, proc.isRunning { proc.terminate() }
        serverProcess = nil
        
        let oldPort = self.forwardPort
        await adb.removeForward(serial: serial, localPort: oldPort)
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        let randomVal = UInt32.random(in: 0x10000000...0x7fffffff)
        self.scid = String(format: "%08x", randomVal)
        self.forwardPort = Int.random(in: 27183...27999)
        self.reconnectAttempts = 0
        
        streamTask = Task { [weak self] in
            guard let self = self else { return }
            await self.runSessionPipeline()
        }
    }
    
    // MARK: - Stop / teardown
    
    public func stop() {
        DiagnosticsLogger.shared.log("Stopping mirroring session...", category: "SESSION", level: .info)
        orientationTask?.cancel()
        orientationTask = nil
        streamTask?.cancel()
        streamTask = nil
        audioTask?.cancel()
        audioTask = nil
        controlSocket?.close()
        controlSocket = nil
        
        teardown(port: self.forwardPort, serial: self.serial)
        state = .disconnected
    }
    
    private func teardown(port: Int, serial: String) {
        orientationTask?.cancel()
        orientationTask = nil
        renderer.flush()
        controlSocket?.close()
        controlSocket = nil
        
        if let proc = serverProcess, proc.isRunning { proc.terminate() }
        serverProcess = nil
        
        if port > 0 && !serial.isEmpty {
            Task { await adb.removeForward(serial: serial, localPort: port) }
        }
    }
    
    // MARK: - State helpers (can be called from non-main actor)

    private func updateState(_ newState: SessionState) {
        self.state = newState
    }
    
    private func setDeviceName(_ name: String) {
        self.deviceName = name
    }
    
    public func handleDimensionChange(_ newDimensions: CGSize) {
        guard newDimensions.width > 0 && newDimensions.height > 0 else { return }
        guard newDimensions != self.streamDimensions else { return }
        
        DiagnosticsLogger.shared.log(
            "Device frame size changed: \(Int(self.streamDimensions.width))x\(Int(self.streamDimensions.height)) -> \(Int(newDimensions.width))x\(Int(newDimensions.height))",
            category: "SESSION", level: .info)
        
        self.streamDimensions = newDimensions
        renderer.flush()
        WindowFrameController.shared.handleDimensionChange(to: newDimensions)
    }
    
    private func incrementFrame(fps: Int) {
        self.frameCount += fps
        self.currentFps = fps
    }
    
    deinit {
        orientationTask?.cancel()
        streamTask?.cancel()
        audioTask?.cancel()
        if let proc = serverProcess, proc.isRunning { proc.terminate() }
    }
}
