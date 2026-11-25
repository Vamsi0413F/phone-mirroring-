import Foundation
import Darwin

public final class TcpSocket: @unchecked Sendable {
    private var fd: Int32 = -1
    private let lock = NSLock()
    
    public init() {}
    
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fd >= 0
    }
    
    /// Connects to the local forwarded port and reads the scrcpy handshake dummy byte (0x00),
    /// retrying until the server finishes starting up on the Android device.
    public func connectAndHandshake(port: UInt16, retryCount: Int = 60, retryDelayMs: UInt32 = 100) -> Bool {
        for attempt in 1...retryCount {
            let socketFd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socketFd >= 0 else {
                usleep(retryDelayMs * 1000)
                continue
            }
            
            // Set TCP_NODELAY for minimum latency
            var one: Int32 = 1
            setsockopt(socketFd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
            
            // Set handshake receive timeout (500ms)
            var tv = timeval(tv_sec: 0, tv_usec: 500_000)
            setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            
            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.connect(socketFd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            if connectResult == 0 {
                var dummyByte: UInt8 = 0xFF
                let bytesRead = Darwin.recv(socketFd, &dummyByte, 1, 0)
                if bytesRead == 1 && dummyByte == 0x00 {
                    // Reset timeout back to indefinite blocking for streaming
                    var zeroTv = timeval(tv_sec: 0, tv_usec: 0)
                    setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &zeroTv, socklen_t(MemoryLayout<timeval>.size))
                    
                    lock.lock()
                    self.fd = socketFd
                    lock.unlock()
                    DiagnosticsLogger.shared.log("Handshake successful on 127.0.0.1:\(port) (attempt \(attempt))", category: "SOCKET", level: .info)
                    return true
                }
            }
            
            Darwin.close(socketFd)
            usleep(retryDelayMs * 1000)
        }
        
        DiagnosticsLogger.shared.log("Handshake failed on 127.0.0.1:\(port) after \(retryCount) attempts", category: "SOCKET", level: .error)
        return false
    }
    
    public func readExact(count: Int) -> Data? {
        var data = Data(count: count)
        var totalRead = 0
        
        while totalRead < count {
            let currentFd: Int32
            lock.lock()
            currentFd = self.fd
            lock.unlock()
            
            guard currentFd >= 0 else { return nil }
            
            let remaining = count - totalRead
            let bytesRead: Int = data.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return -1 }
                let targetPtr = base.advanced(by: totalRead)
                return Darwin.recv(currentFd, targetPtr, remaining, 0)
            }
            
            if bytesRead <= 0 {
                return nil
            }
            totalRead += bytesRead
        }
        
        return data
    }
    
    /// Writes exactly `data.count` bytes. Returns false on error.
    @discardableResult
    public func writeAll(_ data: Data) -> Bool {
        let currentFd: Int32
        lock.lock()
        currentFd = self.fd
        lock.unlock()
        guard currentFd >= 0 else { return false }

        var totalWritten = 0
        let count = data.count
        return data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            while totalWritten < count {
                let n = Darwin.send(currentFd, base.advanced(by: totalWritten), count - totalWritten, 0)
                if n <= 0 { return false }
                totalWritten += n
            }
            return true
        }
    }

    /// Opens a plain TCP connection with no handshake byte exchange.
    /// Used for the control and audio sockets (second/third connections).
    public func connectRaw(port: UInt16) -> Bool {
        let socketFd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFd >= 0 else { return false }

        var one: Int32 = 1
        setsockopt(socketFd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(socketFd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 {
            lock.lock()
            self.fd = socketFd
            lock.unlock()
            return true
        }
        Darwin.close(socketFd)
        return false
    }

    public func close() {
        lock.lock()
        let currentFd = self.fd
        self.fd = -1
        lock.unlock()
        
        if currentFd >= 0 {
            Darwin.shutdown(currentFd, SHUT_RDWR)
            Darwin.close(currentFd)
        }
    }
    
    deinit {
        close()
    }
}
