import XCTest
import CoreMedia
import AppKit
@testable import DroidMirror

final class DimensionChangeTests: XCTestCase {
    // Valid Baseline Profile H.264 SPS & PPS parameter sets
    // Portrait: 720 x 1280 (aspect 9:16 ~0.5625)
    private let portraitSps = Data([0x67, 0x42, 0x00, 0x1f, 0xf4, 0x05, 0xa0, 0x50, 0xc8])
    // Landscape: 1280 x 720 (aspect 16:9 ~1.7778)
    private let landscapeSps = Data([0x67, 0x42, 0x00, 0x1f, 0xf4, 0x02, 0x80, 0x2d, 0xc8])
    // Universal PPS
    private let pps = Data([0x68, 0xce, 0x3c, 0x80])
    
    // SPS with profile High (0x64), coded 544 x 3840
    private let testSps = Data([
        0x67, 0x64, 0x00, 0x28, 0xac, 0x2b, 0x40, 0x44, 0x07, 0x80, 0x22, 0x40, 0x00, 0x00, 0x03, 0x00, 0x40, 0x00, 0x00, 0x0f, 0x03, 0xc5, 0x8b, 0x67, 0x80
    ])
    
    func testPortraitToLandscapeAndBackMidSession() {
        let parser = H264AnnexBParser()
        
        let nalsPortrait = [
            H264AnnexBParser.NalUnit(type: 7, payload: portraitSps),
            H264AnnexBParser.NalUnit(type: 8, payload: pps)
        ]
        let nalsLandscape = [
            H264AnnexBParser.NalUnit(type: 7, payload: landscapeSps),
            H264AnnexBParser.NalUnit(type: 8, payload: pps)
        ]
        
        // 1. Initial portrait start (720 x 1280)
        let initialUpdate = parser.updateParameters(from: nalsPortrait)
        XCTAssertTrue(initialUpdate, "Initial portrait SPS/PPS should create format description")
        XCTAssertEqual(parser.dimensions?.width, 720)
        XCTAssertEqual(parser.dimensions?.height, 1280)
        XCTAssertNotNil(parser.formatDescription)
        
        // 2. Redundant identical parameter sets mid-stream should NOT trigger spurious re-creations
        let redundantUpdate = parser.updateParameters(from: nalsPortrait)
        XCTAssertFalse(redundantUpdate, "Identical parameter sets should not trigger re-creation")
        
        // 3. Phone rotates to Landscape mid-session (1280 x 720)
        let landscapeUpdate = parser.updateParameters(from: nalsLandscape)
        XCTAssertTrue(landscapeUpdate, "Orientation change to landscape must be detected from new SPS/PPS")
        XCTAssertEqual(parser.dimensions?.width, 1280)
        XCTAssertEqual(parser.dimensions?.height, 720)
        
        // 4. Verify decoding pipeline continues with sample buffers in new landscape dimensions
        let idrNal = H264AnnexBParser.NalUnit(type: 5, payload: Data([0x65, 0x88, 0x84, 0x00]))
        let avccData = parser.createAvccBuffer(from: [idrNal])
        let sample = parser.makeSampleBuffer(from: avccData, pts: CMTime(value: 1000, timescale: 1000))
        XCTAssertNotNil(sample, "Decoding path must remain fully functional with new landscape format description")
        
        // 5. Phone rotates back to Portrait mid-session (720 x 1280)
        let backToPortraitUpdate = parser.updateParameters(from: nalsPortrait)
        XCTAssertTrue(backToPortraitUpdate, "Rotation back to portrait must be detected")
        XCTAssertEqual(parser.dimensions?.width, 720)
        XCTAssertEqual(parser.dimensions?.height, 1280)
        
        // 6. Rapid multi-rotation stress test (rotate back and forth 6 times)
        for i in 1...6 {
            let isLandscape = (i % 2 == 1)
            let nals = isLandscape ? nalsLandscape : nalsPortrait
            let expectedW: CGFloat = isLandscape ? 1280 : 720
            let expectedH: CGFloat = isLandscape ? 720 : 1280
            
            let updated = parser.updateParameters(from: nals)
            XCTAssertTrue(updated, "Turn \(i) rotation change must be detected")
            XCTAssertEqual(parser.dimensions?.width, expectedW)
            XCTAssertEqual(parser.dimensions?.height, expectedH)
        }
    }
    
    func testStartSessionInLandscapeDirectly() {
        let parser = H264AnnexBParser()
        
        let nalsLandscape = [
            H264AnnexBParser.NalUnit(type: 7, payload: landscapeSps),
            H264AnnexBParser.NalUnit(type: 8, payload: pps)
        ]
        
        // Starting directly in Landscape orientation
        let updated = parser.updateParameters(from: nalsLandscape)
        XCTAssertTrue(updated, "Direct landscape start should be accepted")
        XCTAssertEqual(parser.dimensions?.width, 1280)
        XCTAssertEqual(parser.dimensions?.height, 720)
        XCTAssertNotNil(parser.formatDescription)
    }
    
    func testSpsParser() {
        guard let spsInfo = H264AnnexBParser.parseSps(from: testSps) else {
            XCTFail("Failed to parse SPS")
            return
        }
        
        XCTAssertEqual(spsInfo.codedWidth, 544)
        XCTAssertEqual(spsInfo.codedHeight, 3840)
        XCTAssertEqual(spsInfo.displayWidth, 544)
        XCTAssertEqual(spsInfo.displayHeight, 3840)
        
        // Also verify portrait and landscape standard SPS
        guard let portraitInfo = H264AnnexBParser.parseSps(from: portraitSps) else {
            XCTFail("Failed to parse portrait SPS")
            return
        }
        XCTAssertEqual(portraitInfo.displayWidth, 720)
        XCTAssertEqual(portraitInfo.displayHeight, 1280)
        
        guard let landscapeInfo = H264AnnexBParser.parseSps(from: landscapeSps) else {
            XCTFail("Failed to parse landscape SPS")
            return
        }
        XCTAssertEqual(landscapeInfo.displayWidth, 1280)
        XCTAssertEqual(landscapeInfo.displayHeight, 720)
    }
    
    func testAnnexBStartCodeDelimiterExtractionNoTruncation() {
        let parser = H264AnnexBParser()
        
        // Create an Annex-B chunk with 4-byte delimiter, portrait SPS, followed by 3-byte delimiter and PPS
        var chunk = Data()
        // 4-byte start code
        chunk.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        chunk.append(portraitSps)
        // 3-byte start code
        chunk.append(contentsOf: [0x00, 0x00, 0x01])
        chunk.append(pps)
        
        let nals = parser.extractNalUnits(from: chunk)
        XCTAssertEqual(nals.count, 2, "Should extract exactly 2 NAL units")
        XCTAssertEqual(nals[0].type, 7, "First NAL must be SPS (type 7)")
        XCTAssertEqual(nals[0].payload, portraitSps, "SPS payload must match exactly")
        XCTAssertEqual(nals[1].type, 8, "Second NAL must be PPS (type 8)")
        XCTAssertEqual(nals[1].payload, pps, "PPS payload must match exactly")
    }
    
    func testSessionHandlesDimensionChangeWithoutDropping() async {
        let session = await ScrcpySession()
        
        // Simulate initial portrait dimensions
        await session.handleDimensionChange(CGSize(width: 1080, height: 2400))
        var dims = await session.streamDimensions
        XCTAssertEqual(dims.width, 1080)
        XCTAssertEqual(dims.height, 2400)
        
        // Simulate rotation to landscape
        await session.handleDimensionChange(CGSize(width: 2400, height: 1080))
        dims = await session.streamDimensions
        XCTAssertEqual(dims.width, 2400)
        XCTAssertEqual(dims.height, 1080)
        
        // Simulate rotation back to portrait
        await session.handleDimensionChange(CGSize(width: 1080, height: 2400))
        dims = await session.streamDimensions
        XCTAssertEqual(dims.width, 1080)
        XCTAssertEqual(dims.height, 2400)
    }
    
    @MainActor
    func testWindowWillResizeLocksAspectRatioWithHeader() {
        let controller = WindowFrameController.shared
        // Set landscape dimensions 1920x1080 (16:9 ~1.7778)
        controller.handleDimensionChange(to: CGSize(width: 1920, height: 1080))
        
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: (800 / (1920.0 / 1080.0)) + controller.headerHeight),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        controller.register(window: window)
        
        // User drags width to 960pt
        let proposedSize = NSSize(width: 960, height: 500)
        let constrainedSize = controller.windowWillResize(window, to: proposedSize)
        
        let expectedVideoH = 960.0 / (1920.0 / 1080.0) // 540.0
        let expectedTotalH = expectedVideoH + controller.headerHeight // 582.0
        
        XCTAssertEqual(constrainedSize.width, 960, accuracy: 0.1)
        XCTAssertEqual(constrainedSize.height, expectedTotalH, accuracy: 0.1)
    }
    
    @MainActor
    func testMaximizedWindowSizingPortraitAndLandscape() {
        let controller = WindowFrameController.shared
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 400),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        controller.register(window: window)
        
        // 1. Portrait: 864 x 1920 (aspect ~0.45)
        controller.handleDimensionChange(to: CGSize(width: 864, height: 1920))
        let portraitFrame = window.frame
        let expectedPortraitH = visible.height - 16
        let expectedPortraitW = (expectedPortraitH - controller.headerHeight) * (864.0 / 1920.0)
        XCTAssertEqual(portraitFrame.height, expectedPortraitH, accuracy: 1.0, "Portrait window should take full top-to-bottom of visible screen")
        XCTAssertEqual(portraitFrame.width, expectedPortraitW, accuracy: 2.0, "Portrait width should match aspect ratio breath")
        
        // 2. Landscape: 1920 x 864 (aspect ~2.222)
        controller.handleDimensionChange(to: CGSize(width: 1920, height: 864))
        let landscapeFrame = window.frame
        let maxW = visible.width - 24
        XCTAssertEqual(landscapeFrame.width, maxW, accuracy: 2.0, "Landscape window should cover maximum screen width")
    }
}
