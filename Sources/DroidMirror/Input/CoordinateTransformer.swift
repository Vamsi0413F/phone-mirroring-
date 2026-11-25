import Foundation
import CoreGraphics

/// Maps macOS window/view coordinates to Android device pixel coordinates.
///
/// The video layer uses `.resizeAspect` gravity, so the actual video rectangle
/// may be letterboxed inside the view bounds. This transformer accounts for
/// that letterbox offset so taps stay edge-accurate.
///
/// Usage:
///   let t = CoordinateTransformer(viewBounds: videoViewBounds, deviceSize: session.streamDimensions)
///   let (dx, dy) = t.transform(viewPoint: point)
public struct CoordinateTransformer: Sendable {
    /// The NSView bounds that contain the AVSampleBufferDisplayLayer (excludes header).
    public let viewBounds: CGRect
    /// Current device frame size (from streamDimensions / SPS).
    public let deviceSize: CGSize

    public init(viewBounds: CGRect, deviceSize: CGSize) {
        self.viewBounds = viewBounds
        self.deviceSize = deviceSize
    }

    // MARK: - Computed video rect (letterboxed inside viewBounds)

    /// The sub-rect of `viewBounds` that actually contains video pixels.
    /// Matches AVLayerVideoGravity.resizeAspect behaviour.
    public var videoRect: CGRect {
        guard deviceSize.width > 0 && deviceSize.height > 0 &&
              viewBounds.width > 0 && viewBounds.height > 0 else {
            return viewBounds
        }
        let viewAspect   = viewBounds.width  / viewBounds.height
        let deviceAspect = deviceSize.width  / deviceSize.height

        let videoW: CGFloat
        let videoH: CGFloat
        if deviceAspect > viewAspect {
            // Pillarboxed: full width, reduced height
            videoW = viewBounds.width
            videoH = videoW / deviceAspect
        } else {
            // Letterboxed: full height, reduced width
            videoH = viewBounds.height
            videoW = videoH * deviceAspect
        }
        let originX = viewBounds.minX + (viewBounds.width  - videoW) / 2
        let originY = viewBounds.minY + (viewBounds.height - videoH) / 2
        return CGRect(x: originX, y: originY, width: videoW, height: videoH)
    }

    // MARK: - Coordinate mapping

    /// Maps a point in view coordinates (AppKit: origin = bottom-left) to
    /// device pixel coordinates (Android: origin = top-left).
    ///
    /// - Parameter viewPoint: Point in the NSView's coordinate space.
    /// - Returns: `(x, y)` clamped to [0, deviceW-1] × [0, deviceH-1],
    ///            or `nil` if outside the video area.
    public func transform(viewPoint: CGPoint) -> (x: Int32, y: Int32)? {
        let vr = videoRect
        guard vr.width > 0 && vr.height > 0 else { return nil }

        // Normalise to [0,1] within the video rect
        let normX = (viewPoint.x - vr.minX) / vr.width
        let normY = (viewPoint.y - vr.minY) / vr.height

        guard normX >= 0 && normX <= 1 && normY >= 0 && normY <= 1 else { return nil }

        // Android Y is top-down; AppKit Y is bottom-up → flip Y
        let deviceX = Int32((normX * deviceSize.width).rounded())
        let deviceY = Int32(((1.0 - normY) * deviceSize.height).rounded())

        let clampedX = max(0, min(Int32(deviceSize.width)  - 1, deviceX))
        let clampedY = max(0, min(Int32(deviceSize.height) - 1, deviceY))

        return (clampedX, clampedY)
    }

    /// Same as `transform(viewPoint:)` but clamps to device bounds instead of returning nil.
    public func transformClamped(viewPoint: CGPoint) -> (x: Int32, y: Int32) {
        let vr = videoRect
        let normX = max(0, min(1, (viewPoint.x - vr.minX) / vr.width))
        let normY = max(0, min(1, (viewPoint.y - vr.minY) / vr.height))
        let deviceX = Int32((normX * deviceSize.width).rounded())
        let deviceY = Int32(((1.0 - normY) * deviceSize.height).rounded())
        let clampedX = max(0, min(Int32(deviceSize.width)  - 1, deviceX))
        let clampedY = max(0, min(Int32(deviceSize.height) - 1, deviceY))
        return (clampedX, clampedY)
    }
}
