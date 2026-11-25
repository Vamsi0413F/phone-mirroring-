import AppKit

@MainActor
public final class WindowFrameController: NSObject, NSWindowDelegate {
    public static let shared = WindowFrameController()
    
    private weak var targetWindow: NSWindow?
    public private(set) var currentDimensions: CGSize = .zero
    
    // Header bar height inside MirroringView (fixed height above video layer)
    public let headerHeight: CGFloat = 42.0
    
    private override init() {
        super.init()
    }
    
    private var activeWindow: NSWindow? {
        if let win = targetWindow { return win }
        let app = NSApplication.shared
        return app.keyWindow ?? app.windows.first(where: { $0.isVisible && !$0.isMiniaturized })
    }
    
    public func register(window: NSWindow) {
        self.targetWindow = window
        window.delegate = self
        DiagnosticsLogger.shared.log("WindowFrameController registered window: frame=\(window.frame)", category: "WINDOW", level: .info)
        if currentDimensions.width > 0 && currentDimensions.height > 0 {
            resizeWindow(for: currentDimensions, animate: false)
        }
    }
    
    public func handleDimensionChange(to newDimensions: CGSize) {
        guard newDimensions.width > 0 && newDimensions.height > 0 else { return }
        guard newDimensions != currentDimensions else { return }
        
        DiagnosticsLogger.shared.log(
            "WindowFrameController device frame size changed: previous=\(Int(currentDimensions.width))x\(Int(currentDimensions.height)) -> new=\(Int(newDimensions.width))x\(Int(newDimensions.height))",
            category: "WINDOW",
            level: .info
        )
        
        currentDimensions = newDimensions
        resizeWindow(for: newDimensions, animate: true)
    }
    
    public func resetForDeviceList() {
        guard let window = activeWindow else { return }
        currentDimensions = .zero
        window.contentAspectRatio = NSSize.zero
        
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        
        let defaultW: CGFloat = 620
        let defaultH: CGFloat = 460
        let currentCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        
        let newX = max(visibleFrame.minX + 20, min(currentCenter.x - (defaultW / 2), visibleFrame.maxX - defaultW - 20))
        let newY = max(visibleFrame.minY + 20, min(currentCenter.y - (defaultH / 2), visibleFrame.maxY - defaultH - 20))
        
        let newFrame = NSRect(x: newX, y: newY, width: defaultW, height: defaultH)
        DiagnosticsLogger.shared.log("Resetting window for device list: newFrame=\(newFrame), previousFrame=\(window.frame)", category: "WINDOW", level: .info)
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    public func resizeWindow(for dimensions: CGSize, animate: Bool) {
        guard let window = activeWindow else {
            DiagnosticsLogger.shared.log("resizeWindow failed: activeWindow is nil", category: "WINDOW", level: .warn)
            return
        }
        
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }
        let visibleFrame = screen.visibleFrame
        
        let isLandscape = dimensions.width > dimensions.height
        let aspectRatio = dimensions.width / dimensions.height
        
        var targetContentWidth: CGFloat
        var targetContentHeight: CGFloat
        
        if isLandscape {
            // HORIZONTAL (Landscape): Cover maximum available screen area while keeping exact aspect ratio
            let maxW = visibleFrame.width - 24
            let maxH = visibleFrame.height - 24
            let maxVideoH = maxH - headerHeight
            
            if (maxW / aspectRatio) <= maxVideoH {
                // Width fills screen width
                targetContentWidth = maxW
                let videoH = maxW / aspectRatio
                targetContentHeight = videoH + headerHeight
            } else {
                // Height fills screen height
                let videoH = maxVideoH
                targetContentHeight = maxH
                targetContentWidth = videoH * aspectRatio
            }
        } else {
            // VERTICAL (Portrait): From top to bottom of screen with corresponding width ("breath")
            let totalH = visibleFrame.height - 16
            let videoH = totalH - headerHeight
            let totalW = videoH * aspectRatio
            
            if totalW > (visibleFrame.width - 24) {
                let maxW = visibleFrame.width - 24
                targetContentWidth = maxW
                let scaledVideoH = maxW / aspectRatio
                targetContentHeight = scaledVideoH + headerHeight
            } else {
                targetContentWidth = totalW
                targetContentHeight = totalH
            }
        }
        
        targetContentWidth = max(targetContentWidth, 320)
        targetContentHeight = max(targetContentHeight, 380)
        
        // Center-anchor resizing
        let currentCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        var newOriginX = currentCenter.x - (targetContentWidth / 2.0)
        var newOriginY = currentCenter.y - (targetContentHeight / 2.0)
        
        // Clamp strictly within visible bounds
        if newOriginX < visibleFrame.minX + 8 {
            newOriginX = visibleFrame.minX + 8
        } else if newOriginX + targetContentWidth > visibleFrame.maxX - 8 {
            newOriginX = visibleFrame.maxX - targetContentWidth - 8
        }
        
        if newOriginY < visibleFrame.minY + 8 {
            newOriginY = visibleFrame.minY + 8
        } else if newOriginY + targetContentHeight > visibleFrame.maxY - 8 {
            newOriginY = visibleFrame.maxY - targetContentHeight - 8
        }
        
        let newFrame = NSRect(
            x: newOriginX,
            y: newOriginY,
            width: targetContentWidth,
            height: targetContentHeight
        )
        
        window.contentAspectRatio = NSSize.zero
        
        DiagnosticsLogger.shared.log(
            "Setting window frame for \(Int(dimensions.width))x\(Int(dimensions.height)) (aspect: \(String(format: "%.2f", aspectRatio))): newFrame=\(newFrame), previousFrame=\(window.frame)",
            category: "WINDOW",
            level: .info
        )
        
        window.setFrame(newFrame, display: true, animate: animate)
    }
    
    // MARK: - NSWindowDelegate Aspect Ratio Locking
    
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard currentDimensions.width > 0 && currentDimensions.height > 0 else { return frameSize }
        let aspectRatio = currentDimensions.width / currentDimensions.height
        
        let currentFrame = sender.frame
        let deltaW = abs(frameSize.width - currentFrame.width)
        let deltaH = abs(frameSize.height - currentFrame.height)
        
        var newW = frameSize.width
        var newH = frameSize.height
        
        if deltaW >= deltaH {
            // Width driven resize
            let videoH = newW / aspectRatio
            newH = videoH + headerHeight
        } else {
            // Height driven resize
            let videoH = max(newH - headerHeight, 100)
            newW = videoH * aspectRatio
            newH = videoH + headerHeight
        }
        
        let constrainedSize = NSSize(width: max(newW, 320), height: max(newH, 380))
        DiagnosticsLogger.shared.log("User manual resize constraint: proposed=\(Int(frameSize.width))x\(Int(frameSize.height)) -> constrained=\(Int(constrainedSize.width))x\(Int(constrainedSize.height))", category: "WINDOW", level: .debug)
        return constrainedSize
    }
    
    public func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            DiagnosticsLogger.shared.log("Window resized: frame=\(window.frame)", category: "WINDOW", level: .debug)
        }
    }
}
