import Foundation
import OSLog

public final class DiagnosticsLogger: @unchecked Sendable {
    public static let shared = DiagnosticsLogger()
    
    public struct LogEntry: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let category: String
        public let message: String
        public let level: Level
        
        public enum Level: String, Sendable {
            case debug = "DEBUG"
            case info = "INFO"
            case warn = "WARN"
            case error = "ERROR"
        }
        
        public var formatted: String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withTime, .withFractionalSeconds]
            let timeStr = formatter.string(from: timestamp)
            return "[\(timeStr)] [\(level.rawValue)] [\(category)] \(message)"
        }
    }
    
    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private let maxEntries = 1000
    private let osLogger = Logger(subsystem: "com.droidmirror.app", category: "General")
    
    private init() {}
    
    public func log(_ message: String, category: String = "General", level: LogEntry.Level = .info) {
        let entry = LogEntry(timestamp: Date(), category: category, message: message, level: level)
        
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
        
        switch level {
        case .debug:
            osLogger.debug("[\(category)] \(message, privacy: .public)")
        case .info:
            osLogger.info("[\(category)] \(message, privacy: .public)")
        case .warn:
            osLogger.warning("[\(category)] \(message, privacy: .public)")
        case .error:
            osLogger.error("[\(category)] \(message, privacy: .public)")
        }
    }
    
    public func getEntries() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
    
    public func exportLogs() -> String {
        lock.lock()
        defer { lock.unlock() }
        return entries.map { $0.formatted }.joined(separator: "\n")
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
