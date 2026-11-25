import SwiftUI

@main
struct DroidMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var discovery = DeviceDiscovery.shared
    @StateObject private var session = ScrcpySession()
    
    @State private var isMirroring = false
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isMirroring {
                    MirroringView(session: session) {
                        isMirroring = false
                        WindowFrameController.shared.resetForDeviceList()
                    }
                } else {
                    DeviceListView(discovery: discovery) { device in
                        session.startMirroring(device: device)
                        isMirroring = true
                    }
                    .frame(minWidth: 550, idealWidth: 620, minHeight: 400, idealHeight: 480)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
