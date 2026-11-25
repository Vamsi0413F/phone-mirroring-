import XCTest
import CoreMedia
@testable import DroidMirror

final class ScrcpyProtocolTests: XCTestCase {
    func testConstantsAndVersion() {
        XCTAssertEqual(ScrcpyConstants.version, "3.1")
        XCTAssertEqual(ScrcpyConstants.serverSha256, "958f0944a62f23b1f33a16e9eb14844c1a04b882ca175a738c16d23cb22b86c0")
        XCTAssertEqual(ScrcpyConstants.videoCodecH264, 0x68323634)
    }
    
    func testPtsBitFlags() {
        let ptsValue: UInt64 = 1_234_567
        let configFlag: UInt64 = ScrcpyConstants.ptsFlagConfig
        let keyframeFlag: UInt64 = ScrcpyConstants.ptsFlagKeyframe
        
        let sampleConfigPacketPts = ptsValue | configFlag
        XCTAssertTrue((sampleConfigPacketPts & configFlag) != 0)
        XCTAssertFalse((sampleConfigPacketPts & keyframeFlag) != 0)
        XCTAssertEqual(sampleConfigPacketPts & ScrcpyConstants.ptsValueMask, ptsValue)
        
        let sampleKeyframePts = ptsValue | keyframeFlag
        XCTAssertFalse((sampleKeyframePts & configFlag) != 0)
        XCTAssertTrue((sampleKeyframePts & keyframeFlag) != 0)
        XCTAssertEqual(sampleKeyframePts & ScrcpyConstants.ptsValueMask, ptsValue)
    }
    
    func testAnnexBParserExtractsNalUnits() {
        let parser = H264AnnexBParser()
        
        // 4-byte start code SPS (type 7: 0x67) + 3-byte start code PPS (type 8: 0x68) + IDR (type 5: 0x65)
        var streamData = Data([0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1f]) // SPS
        streamData.append(contentsOf: [0x00, 0x00, 0x01, 0x68, 0xce, 0x06, 0xe2]) // PPS
        streamData.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84]) // IDR
        
        let nals = parser.extractNalUnits(from: streamData)
        XCTAssertEqual(nals.count, 3)
        
        XCTAssertTrue(nals[0].isSPS)
        XCTAssertEqual(nals[0].payload.first, 0x67)
        
        XCTAssertTrue(nals[1].isPPS)
        XCTAssertEqual(nals[1].payload.first, 0x68)
        
        XCTAssertTrue(nals[2].isIDR)
        XCTAssertEqual(nals[2].payload.first, 0x65)
    }
    
    func testAvccConversionAddsLengthPrefix() {
        let parser = H264AnnexBParser()
        
        let idrNal = H264AnnexBParser.NalUnit(type: 5, payload: Data([0x65, 0x01, 0x02, 0x03]))
        let avcc = parser.createAvccBuffer(from: [idrNal])
        
        // Expected: 4 bytes length (4 in big-endian) + 4 bytes payload = 8 bytes
        XCTAssertEqual(avcc.count, 8)
        let length = avcc.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(length, 4)
        XCTAssertEqual(avcc.subdata(in: 4..<8), idrNal.payload)
    }
}
