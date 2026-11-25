import Foundation

public enum AdbError: LocalizedError {
    case processFailed(command: String, exitCode: Int32, stderr: String)
    case deviceNotFound(serial: String)
    case deviceUnauthorized(serial: String)
    case deviceOffline(serial: String)
    case serverNotFound
    
    public var errorDescription: String? {
        switch self {
        case .processFailed(let cmd, let code, let stderr):
            return "Command '\(cmd)' failed with exit code \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .deviceNotFound(let serial):
            return "Device '\(serial)' not found. Please ensure it is connected and USB debugging is enabled."
        case .deviceUnauthorized(let serial):
            return "Device '\(serial)' is unauthorized. Please accept the RSA fingerprint prompt on your phone's screen."
        case .deviceOffline(let serial):
            return "Device '\(serial)' is offline. Try reconnecting the USB cable."
        case .serverNotFound:
            return "scrcpy-server binary could not be located."
        }
    }
}

public final class AdbService: @unchecked Sendable {
    public static let shared = AdbService()
    
    private init() {}
    
    /// Executes an ADB command with arguments, capturing output.
    @discardableResult
    public func execute(args: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let adbUrl = try BinaryLocator.locateAdb()
        let process = Process()
        process.executableURL = adbUrl
        process.environment = ProcessInfo.processInfo.environment
        process.environment = ProcessInfo.processInfo.environment
        process.arguments = args
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        DiagnosticsLogger.shared.log("Running: adb \(args.joined(separator: " "))", category: "ADB", level: .debug)
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                
                let exitCode = proc.terminationStatus
                if exitCode == 0 {
                    continuation.resume(returning: (stdout, stderr, exitCode))
                } else {
                    continuation.resume(throwing: AdbError.processFailed(command: args.joined(separator: " "), exitCode: exitCode, stderr: stderr))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Cleanly kills any existing adb server instance.
    public func killServer() async {
        DiagnosticsLogger.shared.log("Killing stale adb server instances...", category: "ADB", level: .info)
        do {
            _ = try await execute(args: ["kill-server"])
        } catch {
            DiagnosticsLogger.shared.log("adb kill-server completed or exited: \(error)", category: "ADB", level: .debug)
        }
    }
    
    /// Starts the adb server daemon.
    public func startServer() async throws {
        DiagnosticsLogger.shared.log("Starting adb server...", category: "ADB", level: .info)
        _ = try await execute(args: ["start-server"])
    }
    
    /// Forces ADB to renegotiate authorization, triggering the RSA key dialog on the phone's screen.
    public func triggerAuthorization(serial: String? = nil) async {
        DiagnosticsLogger.shared.log("Triggering ADB authorization prompt for \(serial ?? "all devices")...", category: "ADB", level: .info)
        if let s = serial, !s.isEmpty {
            _ = try? await execute(args: ["-s", s, "reconnect", "offline"])
            try? await Task.sleep(nanoseconds: 300_000_000)
            _ = try? await execute(args: ["-s", s, "reconnect"])
        } else {
            _ = try? await execute(args: ["reconnect", "offline"])
            try? await Task.sleep(nanoseconds: 300_000_000)
            _ = try? await execute(args: ["reconnect"])
        }
    }

    /// Cleanly restarts the ADB server daemon.
    public func restartServer() async {
        DiagnosticsLogger.shared.log("Restarting ADB server daemon...", category: "ADB", level: .info)
        await killServer()
        try? await Task.sleep(nanoseconds: 500_000_000)
        _ = try? await startServer()
    }
    
    /// Queries the current physical surface orientation of the device (0/2: portrait, 1/3: landscape)
    public func getSurfaceOrientation(serial: String) async -> Int? {
        guard !serial.isEmpty else { return nil }
        do {
            let (stdout, _, _) = try await execute(args: ["-s", serial, "shell", "dumpsys", "input"])
            for line in stdout.components(separatedBy: .newlines) {
                if line.contains("SurfaceOrientation") {
                    let parts = line.split(whereSeparator: { $0.isWhitespace || $0 == ":" })
                    if let last = parts.last, let val = Int(last) {
                        return val
                    }
                }
            }
        } catch {
            // Ignore error
        }
        return nil
    }
    
    /// Queries connected devices using `adb devices -l` and parses output.
    public func getDevices() async throws -> [DeviceModel] {
        let (stdout, _, _) = try await execute(args: ["devices", "-l"])
        return Self.parseDevicesOutput(stdout)
    }
    
    /// Parses the raw string output of `adb devices -l`.
    public static func parseDevicesOutput(_ output: String) -> [DeviceModel] {
        var devices: [DeviceModel] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.starts(with: "List of devices attached") || trimmed.starts(with: "* daemon") {
                continue
            }
            
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2 else { continue }
            
            let serial = parts[0]
            let rawState = parts[1].lowercased()
            let state = DeviceState(rawValue: rawState) ?? .unknown
            
            let isWireless = serial.contains(":") || serial.contains(".")
            let transport: DeviceTransport = isWireless ? .wireless : .usb
            
            var product: String?
            var model: String?
            var device: String?
            var transportId: String?
            
            for part in parts.dropFirst(2) {
                if part.starts(with: "product:") {
                    product = String(part.dropFirst("product:".count))
                } else if part.starts(with: "model:") {
                    model = String(part.dropFirst("model:".count))
                } else if part.starts(with: "device:") {
                    device = String(part.dropFirst("device:".count))
                } else if part.starts(with: "transport_id:") {
                    transportId = String(part.dropFirst("transport_id:".count))
                }
            }
            
            let modelObj = DeviceModel(
                serial: serial,
                state: state,
                transport: transport,
                product: product,
                model: model,
                device: device,
                transportId: transportId
            )
            devices.append(modelObj)
        }
        
        return devices
    }
    
    /// Pushes the verified scrcpy-server.jar to the device's `/data/local/tmp/`.
    public func pushServer(to serial: String) async throws {
        let serverUrl = try BinaryLocator.locateServerJar()
        DiagnosticsLogger.shared.log("Pushing server jar from \(serverUrl.path) to device \(serial)...", category: "ADB", level: .info)
        _ = try await execute(args: ["-s", serial, "push", serverUrl.path, ScrcpyConstants.remoteServerPath])
        DiagnosticsLogger.shared.log("Server pushed successfully to \(serial).", category: "ADB", level: .info)
    }
    
    /// Establishes port forwarding: Mac localhost:localPort -> Android localabstract:socketName
    public func setupForward(serial: String, localPort: Int, abstractSocket: String) async throws {
        DiagnosticsLogger.shared.log("Forwarding tcp:\(localPort) -> localabstract:\(abstractSocket) on \(serial)...", category: "ADB", level: .info)
        _ = try await execute(args: ["-s", serial, "forward", "tcp:\(localPort)", "localabstract:\(abstractSocket)"])
    }
    
    /// Removes port forwarding.
    public func removeForward(serial: String, localPort: Int) async {
        DiagnosticsLogger.shared.log("Removing forward tcp:\(localPort) on \(serial)...", category: "ADB", level: .debug)
        do {
            _ = try await execute(args: ["-s", serial, "forward", "--remove", "tcp:\(localPort)"])
        } catch {
            DiagnosticsLogger.shared.log("Remove forward warning: \(error.localizedDescription)", category: "ADB", level: .warn)
        }
    }
    
    /// Spawns the scrcpy server process on the device via `adb shell app_process`.
    public func spawnServerProcess(
        serial: String,
        scid: String,
        maxSize: Int = 0,
        bitRate: Int = 20_000_000,
        maxFps: Int = 60,
        tunnelForward: Bool = true,
        control: Bool = false,
        audio: Bool = false,
        audioDup: Bool = true
    ) throws -> Process {
        let adbUrl = try BinaryLocator.locateAdb()
        let process = Process()
        process.executableURL = adbUrl
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil || env["HOME"]!.isEmpty {
            env["HOME"] = NSHomeDirectory()
        }
        process.environment = env
        
        // Exact scrcpy v3.1 invocation arguments:
        // app_process / com.genymobile.scrcpy.Server 3.1 [key=value ...]
        var shellArgs: [String] = [
            "-s", serial, "shell",
            "CLASSPATH=\(ScrcpyConstants.remoteServerPath)",
            "app_process", "/", "com.genymobile.scrcpy.Server",
            ScrcpyConstants.version,
            "scid=\(scid)",
            "log_level=info",
            "video=true",
            "audio=\(audio ? "true" : "false")",
            "control=\(control ? "true" : "false")",
            "video_codec=h264",
            "max_size=\(maxSize)",
            "video_bit_rate=\(bitRate)",
            "max_fps=\(maxFps)",
            "tunnel_forward=\(tunnelForward ? "true" : "false")",
            "send_dummy_byte=true",
            "send_device_meta=true",
            "send_codec_meta=true",
            "send_frame_meta=true",
            "cleanup=true"
        ]
        if audio {
            shellArgs.append("audio_codec=raw")
            shellArgs.append("audio_dup=\(audioDup ? "true" : "false")")
        }
        
        process.arguments = shellArgs
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DiagnosticsLogger.shared.log("[Device stdout] \(text.trimmingCharacters(in: .whitespacesAndNewlines))", category: "SCRCPY_DEVICE", level: .debug)
        }
        
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DiagnosticsLogger.shared.log("[Device stderr] \(text.trimmingCharacters(in: .whitespacesAndNewlines))", category: "SCRCPY_DEVICE", level: .warn)
        }
        
        DiagnosticsLogger.shared.log("Spawning server on \(serial) (scid=\(scid))...", category: "ADB", level: .info)
        try process.run()
        return process
    }
}
