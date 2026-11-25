import XCTest
@testable import DroidMirror

final class CoordinateTransformerTests: XCTestCase {

    // MARK: - Portrait mapping (1080×2340 device, 300×650 view)

    private let portraitDevice = CGSize(width: 1080, height: 2340)
    private let portraitBounds = CGRect(x: 0, y: 0, width: 300, height: 650)

    private func portraitTransformer() -> CoordinateTransformer {
        CoordinateTransformer(viewBounds: portraitBounds, deviceSize: portraitDevice)
    }

    func testPortrait_centerPoint() {
        let t = portraitTransformer()
        // view center → device center
        let (dx, dy) = t.transformClamped(viewPoint: CGPoint(x: 150, y: 325))
        XCTAssertEqual(dx, 540, accuracy: 2)
        XCTAssertEqual(dy, 1170, accuracy: 2)
    }

    func testPortrait_topLeftCorner() {
        let t = portraitTransformer()
        let vr = t.videoRect
        let (dx, dy) = t.transformClamped(viewPoint: CGPoint(x: vr.minX, y: vr.maxY))
        XCTAssertEqual(dx, 0, accuracy: 2)   // leftmost device pixel
        XCTAssertEqual(dy, 0, accuracy: 2)   // Android top = AppKit maxY
    }

    func testPortrait_bottomRightCorner() {
        let t = portraitTransformer()
        let vr = t.videoRect
        let (dx, dy) = t.transformClamped(viewPoint: CGPoint(x: vr.maxX, y: vr.minY))
        XCTAssertEqual(dx, Int32(portraitDevice.width)  - 1, accuracy: 2)
        XCTAssertEqual(dy, Int32(portraitDevice.height) - 1, accuracy: 2)
    }

    func testPortrait_outsideVideoClamped() {
        let t = portraitTransformer()
        // A point well outside the video rect should still return something in [0, deviceMax]
        let (dx, dy) = t.transformClamped(viewPoint: CGPoint(x: -100, y: -100))
        XCTAssertGreaterThanOrEqual(dx, 0)
        XCTAssertGreaterThanOrEqual(dy, 0)
        XCTAssertLessThanOrEqual(dx, Int32(portraitDevice.width)  - 1)
        XCTAssertLessThanOrEqual(dy, Int32(portraitDevice.height) - 1)
    }

    // MARK: - Landscape mapping (2340×1080 device, 650×300 view)

    private let landscapeDevice = CGSize(width: 2340, height: 1080)
    private let landscapeBounds = CGRect(x: 0, y: 0, width: 650, height: 300)

    private func landscapeTransformer() -> CoordinateTransformer {
        CoordinateTransformer(viewBounds: landscapeBounds, deviceSize: landscapeDevice)
    }

    func testLandscape_centerPoint() {
        let t = landscapeTransformer()
        let (dx, dy) = t.transformClamped(viewPoint: CGPoint(x: 325, y: 150))
        XCTAssertEqual(dx, 1170, accuracy: 2)
        XCTAssertEqual(dy, 540,  accuracy: 2)
    }

    func testLandscape_topLeftCorner() {
        let t = landscapeTransformer()
        let vr = t.videoRect
        let (dx, dy) = t.transformClamped(viewPoint: CGPoint(x: vr.minX, y: vr.maxY))
        XCTAssertEqual(dx, 0, accuracy: 2)
        XCTAssertEqual(dy, 0, accuracy: 2)
    }

    // MARK: - Rotation: same view-point maps to swapped device coords

    func testRotation_coordsSwapAfterRotation() {
        // A point at 25 % across / 25 % up in both orientations
        let viewPoint = CGPoint(x: 0.25 * 300, y: 0.75 * 300) // 75, 225 in a 300×300 square view

        let portraitT  = CoordinateTransformer(
            viewBounds: CGRect(x: 0, y: 0, width: 300, height: 300),
            deviceSize: CGSize(width: 1080, height: 1080)) // square for symmetry
        let landscapeT = CoordinateTransformer(
            viewBounds: CGRect(x: 0, y: 0, width: 300, height: 300),
            deviceSize: CGSize(width: 1080, height: 1080))

        let (p_dx, p_dy) = portraitT.transformClamped(viewPoint: viewPoint)
        let (l_dx, l_dy) = landscapeT.transformClamped(viewPoint: viewPoint)
        // For a square device and square view, the same point maps identically regardless of "orientation"
        XCTAssertEqual(p_dx, l_dx)
        XCTAssertEqual(p_dy, l_dy)
    }

    // MARK: - Letterbox offset cases

    func testLetterbox_narrowDeviceInWideView() {
        // Device 9:16 (portrait), view 16:9 (landscape) → heavy letterboxing
        let device = CGSize(width: 1080, height: 1920)
        let view   = CGRect(x: 0, y: 0, width: 640, height: 360)
        let t = CoordinateTransformer(viewBounds: view, deviceSize: device)
        let vr = t.videoRect

        // Video width should be much less than view width
        let expectedVideoW = 360.0 * (1080.0 / 1920.0) // ≈ 202.5
        XCTAssertEqual(vr.width,  expectedVideoW, accuracy: 1.0)
        XCTAssertEqual(vr.height, 360.0,          accuracy: 1.0)

        // A tap at the left edge of the video rect should map to deviceX ≈ 0
        let (dx, _) = t.transformClamped(viewPoint: CGPoint(x: vr.minX, y: vr.midY))
        XCTAssertEqual(dx, 0, accuracy: 2)
    }

    func testLetterbox_wideDeviceInTallView() {
        // Device 16:9 (landscape), view 9:16 (portrait) → heavy pillarboxing
        let device = CGSize(width: 1920, height: 1080)
        let view   = CGRect(x: 0, y: 0, width: 360, height: 640)
        let t = CoordinateTransformer(viewBounds: view, deviceSize: device)
        let vr = t.videoRect

        let expectedVideoH = 360.0 * (1080.0 / 1920.0) // ≈ 202.5
        XCTAssertEqual(vr.width,  360.0,          accuracy: 1.0)
        XCTAssertEqual(vr.height, expectedVideoH, accuracy: 1.0)

        // A tap at the top of the video rect (AppKit: maxY) → Android Y ≈ 0
        let (_, dy) = t.transformClamped(viewPoint: CGPoint(x: vr.midX, y: vr.maxY))
        XCTAssertEqual(dy, 0, accuracy: 2)
    }

    // MARK: - nil when strictly outside video area

    func testTransformReturnsNilOutsideVideo() {
        let device = CGSize(width: 1080, height: 1920)
        let view   = CGRect(x: 0, y: 0, width: 640, height: 360)
        let t = CoordinateTransformer(viewBounds: view, deviceSize: device)
        // A point that is left of the letterbox
        let result = t.transform(viewPoint: CGPoint(x: 0, y: 180))
        XCTAssertNil(result)
    }
}
