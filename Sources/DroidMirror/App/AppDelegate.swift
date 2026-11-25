import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsLogger.shared.log("DroidMirror launched", category: "APP")
        DeviceDiscovery.shared.start()
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        DiagnosticsLogger.shared.log("DroidMirror terminating, cleaning up...", category: "APP")
        DeviceDiscovery.shared.stop()
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
