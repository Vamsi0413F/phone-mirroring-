import AppKit
import AVFoundation
import SwiftUI

// MARK: - DisplayLayerNSView (video + input)

public final class DisplayLayerNSView: NSView {
    public let displayLayer = AVSampleBufferDisplayLayer()

    /// Set by MirroringView before the view appears.
    public weak var session: ScrcpySession?

    // Scroll throttle: max one event per 16 ms (≈ 60 Hz)
    private var lastScrollTime: Date = .distantPast
    private static let scrollThrottleInterval: TimeInterval = 1.0 / 60.0

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        
        displayLayer.videoGravity = .resize
        displayLayer.frame = bounds
        layer?.addSublayer(displayLayer)
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let win = self.window {
            DiagnosticsLogger.shared.log(
                "DisplayLayerNSView moved to window: frame=\(win.frame)", category: "WINDOW", level: .info)
            WindowFrameController.shared.register(window: win)
            win.makeFirstResponder(self)
        }
    }
    
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func layout() {
        super.layout()
        guard let session = session else {
            displayLayer.frame = bounds
            return
        }
        let deviceSize = session.streamDimensions
        if deviceSize.width > 0 && deviceSize.height > 0 {
            let transformer = CoordinateTransformer(viewBounds: bounds, deviceSize: deviceSize)
            displayLayer.frame = transformer.videoRect
        } else {
            displayLayer.frame = bounds
        }
    }
    
    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }
    
    public func flush() {
        displayLayer.flushAndRemoveImage()
    }

    // MARK: - Coordinate helper

    private func deviceCoords(for event: NSEvent) -> (x: Int32, y: Int32, w: UInt16, h: UInt16)? {
        guard let session = session else { return nil }
        let deviceSize = session.streamDimensions
        guard deviceSize.width > 0 && deviceSize.height > 0 else { return nil }

        let viewPt = convert(event.locationInWindow, from: nil)
        let transformer = CoordinateTransformer(viewBounds: bounds, deviceSize: deviceSize)
        let vr = transformer.videoRect
        guard vr.width > 0 && vr.height > 0 else { return nil }

        // Precise normalized offset relative to the actual video rectangle
        let normX = max(0.0, min(1.0, (viewPt.x - vr.minX) / vr.width))
        let normY = max(0.0, min(1.0, (viewPt.y - vr.minY) / vr.height))

        let dx = Int32((normX * deviceSize.width).rounded())
        let dy = Int32(((1.0 - normY) * deviceSize.height).rounded())

        let clampedX = max(0, min(Int32(deviceSize.width) - 1, dx))
        let clampedY = max(0, min(Int32(deviceSize.height) - 1, dy))

        return (clampedX, clampedY, UInt16(deviceSize.width), UInt16(deviceSize.height))
    }

    private var ctrl: ControlSocket? { session?.controlSocket }

    // MARK: - Mouse events (Finger Touch injection for pixel-perfect patterns)

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let (x, y, w, h) = deviceCoords(for: event) else { return }
        ctrl?.sendTouchEvent(action: ScrcpyConstants.actionDown,
                             pointerId: ScrcpyConstants.pointerIdGenericFinger,
                             x: x, y: y, screenW: w, screenH: h,
                             pressure: 1.0,
                             actionButton: 0,
                             buttons: 0)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let (x, y, w, h) = deviceCoords(for: event) else { return }
        ctrl?.sendTouchEvent(action: ScrcpyConstants.actionMove,
                             pointerId: ScrcpyConstants.pointerIdGenericFinger,
                             x: x, y: y, screenW: w, screenH: h,
                             pressure: 1.0,
                             actionButton: 0,
                             buttons: 0)
    }

    public override func mouseUp(with event: NSEvent) {
        guard let (x, y, w, h) = deviceCoords(for: event) else { return }
        ctrl?.sendTouchEvent(action: ScrcpyConstants.actionUp,
                             pointerId: ScrcpyConstants.pointerIdGenericFinger,
                             x: x, y: y, screenW: w, screenH: h,
                             pressure: 0.0,
                             actionButton: 0,
                             buttons: 0)
    }

    // Right-click = Back
    public override func rightMouseDown(with event: NSEvent) {
        ctrl?.sendBackOrScreenOn(action: ScrcpyConstants.actionDown)
    }
    public override func rightMouseUp(with event: NSEvent) {
        ctrl?.sendBackOrScreenOn(action: ScrcpyConstants.actionUp)
    }

    // Trackpad / mouse-wheel scroll — throttled
    public override func scrollWheel(with event: NSEvent) {
        let now = Date()
        guard now.timeIntervalSince(lastScrollTime) >= Self.scrollThrottleInterval else { return }
        lastScrollTime = now

        guard let (x, y, w, h) = deviceCoords(for: event) else { return }

        let scale: CGFloat = 1.0 / 60.0
        let hscroll = Float(event.scrollingDeltaX * scale)
        let vscroll = Float(event.scrollingDeltaY * scale)
        guard abs(hscroll) > 0.001 || abs(vscroll) > 0.001 else { return }

        ctrl?.sendScrollEvent(x: x, y: y, screenW: w, screenH: h,
                              hscroll: hscroll, vscroll: vscroll, buttons: 0)
    }

    // MARK: - Keyboard events

    public override func keyDown(with event: NSEvent) {
        if KeycodeMap.shouldInjectAsText(event), let chars = event.characters {
            ctrl?.sendText(chars)
        } else if let keycode = KeycodeMap.androidKeycode(for: event) {
            ctrl?.sendKeycode(action: ScrcpyConstants.actionDown, keycode: keycode,
                              repeat: 0, metastate: 0)
        }
    }

    public override func keyUp(with event: NSEvent) {
        if !KeycodeMap.shouldInjectAsText(event), let keycode = KeycodeMap.androidKeycode(for: event) {
            ctrl?.sendKeycode(action: ScrcpyConstants.actionUp, keycode: keycode,
                              repeat: 0, metastate: 0)
        }
    }
}

// MARK: - SampleBufferRendererView

public struct SampleBufferRendererView: NSViewRepresentable {
    public let renderer: VideoRenderer
    public weak var session: ScrcpySession?
    
    public init(renderer: VideoRenderer, session: ScrcpySession? = nil) {
        self.renderer = renderer
        self.session = session
    }
    
    public func makeNSView(context: Context) -> DisplayLayerNSView {
        let view = DisplayLayerNSView()
        view.session = session
        renderer.attach(view: view)
        return view
    }
    
    public func updateNSView(_ nsView: DisplayLayerNSView, context: Context) {
        nsView.session = session
        nsView.needsLayout = true
    }
    
    public static func dismantleNSView(_ nsView: DisplayLayerNSView, coordinator: ()) {
        nsView.flush()
    }
}

// MARK: - VideoRenderer

public final class VideoRenderer: @unchecked Sendable {
    private weak var currentView: DisplayLayerNSView?
    private let lock = NSLock()
    
    public init() {}
    
    public func attach(view: DisplayLayerNSView) {
        lock.lock()
        currentView = view
        lock.unlock()
    }
    
    public func render(sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let view = self.currentView
            self.lock.unlock()
            view?.enqueue(sampleBuffer)
        }
    }
    
    public func flush() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let view = self.currentView
            self.lock.unlock()
            view?.flush()
        }
    }
}
