import Foundation
import CoreMedia
import VideoToolbox

public final class H264AnnexBParser: @unchecked Sendable {
    private var spsData: Data?
    private var ppsData: Data?
    public private(set) var formatDescription: CMVideoFormatDescription?
    public private(set) var currentSpsInfo: SpsInfo?
    
    public init() {}
    
    public struct NalUnit {
        public let type: UInt8
        public let payload: Data
        
        public init(type: UInt8, payload: Data) {
            self.type = type
            self.payload = payload
        }
        
        public var isSPS: Bool { type == 7 }
        public var isPPS: Bool { type == 8 }
        public var isIDR: Bool { type == 5 }
        public var isSlice: Bool { type == 1 }
    }
    
    public struct SpsInfo: Equatable, Sendable {
        public let profileIdc: UInt8
        public let levelIdc: UInt8
        public let codedWidth: Int
        public let codedHeight: Int
        public let displayWidth: Int
        public let displayHeight: Int
        public let cropLeft: Int
        public let cropRight: Int
        public let cropTop: Int
        public let cropBottom: Int
        
        public var displaySize: CGSize {
            CGSize(width: displayWidth, height: displayHeight)
        }
        
        public var codedSize: CGSize {
            CGSize(width: codedWidth, height: codedHeight)
        }
    }
    
    public var dimensions: CGSize? {
        if let sps = currentSpsInfo {
            return sps.displaySize
        }
        guard let desc = formatDescription else { return nil }
        let dim = CMVideoFormatDescriptionGetDimensions(desc)
        return CGSize(width: CGFloat(dim.width), height: CGFloat(dim.height))
    }
    
    // MARK: - Annex-B NAL Extraction
    
    private struct StartCodeSpan {
        let prefixStart: Int
        let payloadStart: Int
    }
    
    /// Parses an Annex-B chunk into individual NAL units with exact delimiter boundaries.
    public func extractNalUnits(from data: Data) -> [NalUnit] {
        var nalUnits: [NalUnit] = []
        let count = data.count
        guard count >= 4 else { return [] }
        
        var spans: [StartCodeSpan] = []
        
        data.withUnsafeBytes { rawBuffer in
            let ptr = rawBuffer.bindMemory(to: UInt8.self)
            var i = 0
            while i < count - 2 {
                if ptr[i] == 0 && ptr[i + 1] == 0 {
                    if ptr[i + 2] == 1 {
                        // 3-byte delimiter: 00 00 01
                        spans.append(StartCodeSpan(prefixStart: i, payloadStart: i + 3))
                        i += 3
                        continue
                    } else if i < count - 3 && ptr[i + 2] == 0 && ptr[i + 3] == 1 {
                        // 4-byte delimiter: 00 00 00 01
                        spans.append(StartCodeSpan(prefixStart: i, payloadStart: i + 4))
                        i += 4
                        continue
                    }
                }
                i += 1
            }
        }
        
        guard !spans.isEmpty else { return [] }
        
        for idx in 0..<spans.count {
            let start = spans[idx].payloadStart
            let end = (idx + 1 < spans.count) ? spans[idx + 1].prefixStart : count
            
            guard end > start else { continue }
            let nalPayload = data.subdata(in: start..<end)
            guard let firstByte = nalPayload.first else { continue }
            let nalType = firstByte & 0x1F
            nalUnits.append(NalUnit(type: nalType, payload: nalPayload))
        }
        
        return nalUnits
    }
    
    // MARK: - SPS Bitstream Parsing
    
    /// Removes emulation prevention bytes (0x00 0x00 0x03 -> 0x00 0x00)
    public static func unescapeRbsp(from data: Data) -> Data {
        var rbsp = Data()
        rbsp.reserveCapacity(data.count)
        var zeroCount = 0
        for byte in data {
            if zeroCount >= 2 && byte == 0x03 {
                zeroCount = 0
                continue
            }
            rbsp.append(byte)
            if byte == 0x00 {
                zeroCount += 1
            } else {
                zeroCount = 0
            }
        }
        return rbsp
    }
    
    public final class BitReader {
        private let bytes: [UInt8]
        private var byteOffset: Int = 0
        private var bitOffset: Int = 0 // 0..7 MSB to LSB
        
        public init(data: Data) {
            self.bytes = Array(data)
        }
        
        public var hasMoreBits: Bool {
            return byteOffset < bytes.count
        }
        
        public func readBit() -> UInt32 {
            guard byteOffset < bytes.count else { return 0 }
            let bit = (UInt32(bytes[byteOffset]) >> (7 - bitOffset)) & 1
            bitOffset += 1
            if bitOffset == 8 {
                bitOffset = 0
                byteOffset += 1
            }
            return bit
        }
        
        public func readBits(_ count: Int) -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<count {
                value = (value << 1) | readBit()
            }
            return value
        }
        
        public func readUE() -> UInt32 {
            var leadingZeros = 0
            while byteOffset < bytes.count && readBit() == 0 {
                leadingZeros += 1
                if leadingZeros > 32 { return 0 }
            }
            if leadingZeros == 0 {
                return 0
            }
            let suffix = readBits(leadingZeros)
            return (1 << leadingZeros) - 1 + suffix
        }
        
        public func readSE() -> Int32 {
            let ue = readUE()
            if (ue & 1) == 1 {
                return Int32((ue + 1) >> 1)
            } else {
                return -Int32(ue >> 1)
            }
        }
    }
    
    /// Parses an H.264 SPS payload, computing exact cropped display dimensions.
    public static func parseSps(from spsPayload: Data) -> SpsInfo? {
        guard spsPayload.count >= 4 else { return nil }
        
        let nalHeader = spsPayload[0]
        let nalType = nalHeader & 0x1F
        guard nalType == 7 else { return nil }
        
        let rbsp = unescapeRbsp(from: spsPayload.subdata(in: 1..<spsPayload.count))
        let reader = BitReader(data: rbsp)
        
        let profileIdc = UInt8(reader.readBits(8))
        _ = reader.readBits(8) // constraint flags & reserved
        let levelIdc = UInt8(reader.readBits(8))
        _ = reader.readUE() // seq_parameter_set_id
        
        var chromaFormatIdc: UInt32 = 1 // default is 4:2:0
        let highProfiles: Set<UInt8> = [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135]
        if highProfiles.contains(profileIdc) {
            chromaFormatIdc = reader.readUE()
            if chromaFormatIdc == 3 {
                _ = reader.readBit() // separate_colour_plane_flag
            }
            _ = reader.readUE() // bit_depth_luma_minus8
            _ = reader.readUE() // bit_depth_chroma_minus8
            _ = reader.readBit() // qpprime_y_zero_transform_bypass_flag
            let seqScalingMatrixPresent = reader.readBit()
            if seqScalingMatrixPresent == 1 {
                let count = (chromaFormatIdc != 3) ? 8 : 12
                for i in 0..<count {
                    let seqScalingListPresent = reader.readBit()
                    if seqScalingListPresent == 1 {
                        let size = (i < 6) ? 16 : 64
                        var lastScale = 8
                        var nextScale = 8
                        for _ in 0..<size {
                            if nextScale != 0 {
                                let deltaScale = reader.readSE()
                                nextScale = (lastScale + Int(deltaScale) + 256) % 256
                            }
                            lastScale = (nextScale == 0) ? lastScale : nextScale
                        }
                    }
                }
            }
        }
        
        _ = reader.readUE() // log2_max_frame_num_minus4
        let picOrderCntType = reader.readUE()
        if picOrderCntType == 0 {
            _ = reader.readUE() // log2_max_pic_order_cnt_lsb_minus4
        } else if picOrderCntType == 1 {
            _ = reader.readBit() // delta_pic_order_always_zero_flag
            _ = reader.readSE() // offset_for_non_ref_pic
            _ = reader.readSE() // offset_for_top_to_bottom_field
            let numRefFramesInPicOrderCntCycle = reader.readUE()
            for _ in 0..<numRefFramesInPicOrderCntCycle {
                _ = reader.readSE() // offset_for_ref_frame[i]
            }
        }
        
        _ = reader.readUE() // max_num_ref_frames
        _ = reader.readBit() // gaps_in_frame_num_value_allowed_flag
        
        let picWidthInMbsMinus1 = reader.readUE()
        let picHeightInMapUnitsMinus1 = reader.readUE()
        let frameMbsOnlyFlag = reader.readBit()
        
        if frameMbsOnlyFlag == 0 {
            _ = reader.readBit() // mb_adaptive_frame_field_flag
        }
        _ = reader.readBit() // direct_8x8_inference_flag
        
        let frameCroppingFlag = reader.readBit()
        var cropLeft = 0
        var cropRight = 0
        var cropTop = 0
        var cropBottom = 0
        
        if frameCroppingFlag == 1 {
            cropLeft = Int(reader.readUE())
            cropRight = Int(reader.readUE())
            cropTop = Int(reader.readUE())
            cropBottom = Int(reader.readUE())
        }
        
        let codedWidth = Int(picWidthInMbsMinus1 + 1) * 16
        let codedHeight = Int((2 - frameMbsOnlyFlag) * (picHeightInMapUnitsMinus1 + 1)) * 16
        
        let cropUnitX: Int
        let cropUnitY: Int
        if chromaFormatIdc == 0 { // Monochrome
            cropUnitX = 1
            cropUnitY = Int(2 - frameMbsOnlyFlag)
        } else if chromaFormatIdc == 1 { // 4:2:0
            cropUnitX = 2
            cropUnitY = Int(2 * (2 - frameMbsOnlyFlag))
        } else if chromaFormatIdc == 2 { // 4:2:2
            cropUnitX = 2
            cropUnitY = Int(2 - frameMbsOnlyFlag)
        } else { // 4:4:4
            cropUnitX = 1
            cropUnitY = Int(2 - frameMbsOnlyFlag)
        }
        
        let displayWidth = codedWidth - (cropLeft + cropRight) * cropUnitX
        let displayHeight = codedHeight - (cropTop + cropBottom) * cropUnitY
        
        return SpsInfo(
            profileIdc: profileIdc,
            levelIdc: levelIdc,
            codedWidth: codedWidth,
            codedHeight: codedHeight,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            cropLeft: cropLeft,
            cropRight: cropRight,
            cropTop: cropTop,
            cropBottom: cropBottom
        )
    }
    
    // MARK: - Parameter Sets & Format Description
    
    /// Updates stored SPS/PPS parameter sets and recreates CMVideoFormatDescription if updated.
    /// Returns true only if a new format description was created/updated.
    @discardableResult
    public func updateParameters(from nalUnits: [NalUnit]) -> Bool {
        var updated = false
        for nal in nalUnits {
            if nal.isSPS {
                let previousSize = self.dimensions ?? .zero
                if let parsedInfo = Self.parseSps(from: nal.payload) {
                    DiagnosticsLogger.shared.log(
                        "SPS received: parsed display \(parsedInfo.displayWidth)x\(parsedInfo.displayHeight) (coded \(parsedInfo.codedWidth)x\(parsedInfo.codedHeight), crop L:\(parsedInfo.cropLeft) R:\(parsedInfo.cropRight) T:\(parsedInfo.cropTop) B:\(parsedInfo.cropBottom)), previous: \(Int(previousSize.width))x\(Int(previousSize.height))",
                        category: "CONFIG",
                        level: .info
                    )
                    self.currentSpsInfo = parsedInfo
                } else {
                    DiagnosticsLogger.shared.log("SPS received but failed bitstream parse, length: \(nal.payload.count) bytes, previous: \(Int(previousSize.width))x\(Int(previousSize.height))", category: "CONFIG", level: .warn)
                }
                
                if spsData != nal.payload {
                    spsData = nal.payload
                    updated = true
                }
            } else if nal.isPPS {
                DiagnosticsLogger.shared.log("PPS received: \(nal.payload.count) bytes", category: "CONFIG", level: .debug)
                if ppsData != nal.payload {
                    ppsData = nal.payload
                    updated = true
                }
            }
        }
        
        guard updated, let sps = spsData, let pps = ppsData else {
            return false
        }
        
        var newFormatDesc: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsBuffer in
            pps.withUnsafeBytes { ppsBuffer in
                guard let spsBase = spsBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ppsBase = ppsBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return OSStatus(-1) }
                
                let parameterSetPointers = [spsBase, ppsBase]
                let parameterSetSizes = [sps.count, pps.count]
                
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newFormatDesc
                )
            }
        }
        
        if status == noErr, let desc = newFormatDesc {
            self.formatDescription = desc
            let dim = self.dimensions ?? CGSize(width: CGFloat(CMVideoFormatDescriptionGetDimensions(desc).width), height: CGFloat(CMVideoFormatDescriptionGetDimensions(desc).height))
            DiagnosticsLogger.shared.log("H.264 format description updated: \(Int(dim.width))x\(Int(dim.height))", category: "DECODER", level: .info)
            return true
        } else {
            DiagnosticsLogger.shared.log("Failed to create CMVideoFormatDescription: \(status)", category: "DECODER", level: .error)
            return false
        }
    }
    
    /// Converts a list of NAL units into a single AVCC format Data buffer (4-byte length prefix).
    public func createAvccBuffer(from nalUnits: [NalUnit]) -> Data {
        var avccData = Data()
        for nal in nalUnits {
            if nal.isSlice || nal.isIDR || nal.type == 6 {
                var length = UInt32(nal.payload.count).bigEndian
                withUnsafeBytes(of: &length) { avccData.append(contentsOf: $0) }
                avccData.append(nal.payload)
            }
        }
        return avccData
    }
    
    /// Constructs a CMSampleBuffer from AVCC data and PTS.
    public func makeSampleBuffer(from avccData: Data, pts: CMTime) -> CMSampleBuffer? {
        guard let formatDesc = self.formatDescription, !avccData.isEmpty else { return nil }
        
        var blockBuffer: CMBlockBuffer?
        let status = avccData.withUnsafeBytes { rawBuffer in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: avccData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avccData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        
        guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else { return nil }
        
        let fillStatus = avccData.withUnsafeBytes { rawBuffer in
            CMBlockBufferReplaceDataBytes(
                with: rawBuffer.baseAddress!,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }
        guard fillStatus == kCMBlockBufferNoErr else { return nil }
        
        var sampleTiming = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: CMTime.invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 1,
            sampleSizeArray: [avccData.count],
            sampleBufferOut: &sampleBuffer
        )
        
        guard sampleStatus == noErr, let finalSample = sampleBuffer else { return nil }
        
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(finalSample, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        
        return finalSample
    }
}
