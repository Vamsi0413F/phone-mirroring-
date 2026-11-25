import Foundation
import CryptoKit

public enum BinaryLocatorError: LocalizedError {
    case adbNotFound
    case serverJarNotFound
    case serverChecksumMismatch(expected: String, actual: String)
    
    public var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "Bundled 'adb' binary could not be found."
        case .serverJarNotFound:
            return "Bundled 'scrcpy-server' could not be found."
        case .serverChecksumMismatch(let expected, let actual):
            return "scrcpy-server SHA-256 checksum mismatch. Expected: \(expected), got: \(actual)"
        }
    }
}

public struct BinaryLocator {
    /// Returns the active Bundle for resource lookup (SwiftPM module or main app bundle).
    public static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
    
    /// Resolves the file URL for the bundled `adb` binary.
    public static func locateAdb() throws -> URL {
        // 1. Try Bundle resource URL
        if let url = resourceBundle.url(forResource: "adb", withExtension: nil, subdirectory: "Resources/bin") ??
                     resourceBundle.url(forResource: "adb", withExtension: nil) {
            ensureExecutable(url: url)
            return url
        }
        
        // 2. Try direct relative path within bundle / executable directory
        let bundlePath = Bundle.main.bundleURL
        let candidatePaths = [
            bundlePath.appendingPathComponent("Contents/Resources/bin/adb"),
            bundlePath.appendingPathComponent("Resources/bin/adb"),
            bundlePath.appendingPathComponent("adb"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/DroidMirror/Resources/bin/adb")
        ]
        
        for candidate in candidatePaths where FileManager.default.fileExists(atPath: candidate.path) {
            ensureExecutable(url: candidate)
            return candidate
        }
        
        // 3. Check system PATH fallback
        let systemCandidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
        for path in systemCandidates where FileManager.default.fileExists(atPath: path) {
            DiagnosticsLogger.shared.log("Using system adb fallback at \(path)", category: "BinaryLocator", level: .warn)
            return URL(fileURLWithPath: path)
        }
        
        throw BinaryLocatorError.adbNotFound
    }
    
    /// Resolves and validates the SHA-256 checksum of the bundled `scrcpy-server-v3.1`.
    public static func locateServerJar() throws -> URL {
        let expectedHash = ScrcpyConstants.serverSha256
        let filename = ScrcpyConstants.bundledServerFilename
        
        var targetUrl: URL?
        
        if let url = resourceBundle.url(forResource: filename, withExtension: nil, subdirectory: "Resources/bin") ??
                     resourceBundle.url(forResource: filename, withExtension: nil) {
            targetUrl = url
        } else {
            let bundlePath = Bundle.main.bundleURL
            let candidatePaths = [
                bundlePath.appendingPathComponent("Contents/Resources/bin/\(filename)"),
                bundlePath.appendingPathComponent("Resources/bin/\(filename)"),
                bundlePath.appendingPathComponent(filename),
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/DroidMirror/Resources/bin/\(filename)")
            ]
            
            for candidate in candidatePaths where FileManager.default.fileExists(atPath: candidate.path) {
                targetUrl = candidate
                break
            }
        }
        
        guard let url = targetUrl else {
            throw BinaryLocatorError.serverJarNotFound
        }
        
        // Verify SHA-256 checksum
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        
        guard hashString.lowercased() == expectedHash.lowercased() else {
            DiagnosticsLogger.shared.log("Checksum validation failed for \(url.path)", category: "BinaryLocator", level: .error)
            throw BinaryLocatorError.serverChecksumMismatch(expected: expectedHash, actual: hashString)
        }
        
        DiagnosticsLogger.shared.log("Verified scrcpy-server v\(ScrcpyConstants.version) (SHA-256: \(hashString.prefix(12))...)", category: "BinaryLocator", level: .info)
        return url
    }
    
    private static func ensureExecutable(url: URL) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let perms = attrs[.posixPermissions] as? NSNumber {
                let current = perms.uint16Value
                if (current & 0o111) == 0 {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
            }
        } catch {
            DiagnosticsLogger.shared.log("Failed to verify/set permissions on \(url.path): \(error)", category: "BinaryLocator", level: .warn)
        }
    }
}
