import Foundation
import AVFoundation

/// Receives raw PCM audio packets from scrcpy audio socket (scrcpy v3.1 `--audio-codec=raw`),
/// and feeds AVAudioEngine for real-time, zero-transcode playback.
public final class AudioReceiver: @unchecked Sendable {
    private let socket = TcpSocket()
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    // 48 kHz stereo 16-bit PCM LE (native scrcpy raw format)
    private let pcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 48000,
        channels: 2,
        interleaved: true
    )!
    
    private var isRunning = false

    public init() {}

    public func connectAndRun(port: UInt16, retryCount: Int = 40, retryDelayMs: UInt32 = 100) {
        var connected = false
        for attempt in 1...retryCount {
            if socket.connectRaw(port: port) {
                DiagnosticsLogger.shared.log("Audio socket connected (attempt \(attempt))", category: "AUDIO", level: .info)
                connected = true
                break
            }
            usleep(retryDelayMs * 1_000)
        }
        guard connected else {
            DiagnosticsLogger.shared.log("Audio socket failed to connect", category: "AUDIO", level: .warn)
            return
        }

        // Read first packet (codec metadata packet)
        guard let header = socket.readExact(count: 12) else { return }
        let size = header.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        if size > 0 && size < 1000 {
            _ = socket.readExact(count: Int(size))
        }

        setupEngine()
        isRunning = true
        receiveLoop()
    }

    public func stop() {
        isRunning = false
        socket.close()
        if engine.isRunning {
            playerNode.stop()
            engine.stop()
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: pcmFormat)
        do {
            try engine.start()
            playerNode.play()
            DiagnosticsLogger.shared.log("AVAudioEngine raw PCM player started", category: "AUDIO", level: .info)
        } catch {
            DiagnosticsLogger.shared.log("AVAudioEngine start error: \(error)", category: "AUDIO", level: .error)
        }
    }

    private func receiveLoop() {
        while isRunning {
            guard let header = socket.readExact(count: 12) else { break }
            let size = header.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard size > 0 && size < 500_000 else { break }
            guard let payload = socket.readExact(count: Int(size)) else { break }

            playPCM(payload)
        }
        stop()
    }

    private func playPCM(_ data: Data) {
        // 2 channels * 2 bytes = 4 bytes per frame
        let frameCount = UInt32(data.count) / 4
        guard frameCount > 0 else { return }
        guard let pcmBuf = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else { return }
        pcmBuf.frameLength = frameCount

        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress, let channelData = pcmBuf.int16ChannelData {
                memcpy(channelData[0], base, data.count)
            }
        }

        playerNode.scheduleBuffer(pcmBuf, completionHandler: nil)
    }
}
