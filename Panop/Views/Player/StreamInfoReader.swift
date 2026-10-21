import CoreMedia
import Foundation
import PanopPlayback

/// Reads what a player says about a stream from its `CMFormatDescription`s, which AVPlayer and KSPlayer both
/// hand over, into a `StreamInfo`.
nonisolated enum StreamInfoReader {
    static func fill(
        _ info: inout StreamInfo,
        video: CMFormatDescription?,
        frameRate: Double? = nil,
        isDolbyVision: Bool = false
    ) {
        guard let video else { return }
        let subtype = CMFormatDescriptionGetMediaSubType(video)
        info.videoCodec = fourCC(subtype)
        let size = CMVideoFormatDescriptionGetDimensions(video)
        if size.width > 0, size.height > 0 {
            info.width = Int(size.width)
            info.height = Int(size.height)
        }
        if let frameRate, frameRate > 0 {
            info.frameRate = frameRate
        }
        if isDolbyVision || subtype == 0x6476_6831 /* dvh1 */ || subtype == 0x6476_6865 /* dvhe */ {
            info.hdr = "Dolby Vision"
        } else if let transfer = CMFormatDescriptionGetExtension(
            video, extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ) as? String {
            if transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String {
                info.hdr = "HDR10"
            } else if transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String {
                info.hdr = "HLG"
            }
        }
    }

    static func fill(_ info: inout StreamInfo, audio: CMFormatDescription?) {
        guard let audio else { return }
        info.audioCodec = fourCC(CMFormatDescriptionGetMediaSubType(audio))
        if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(audio)?.pointee, basic.mChannelsPerFrame > 0 {
            info.audioChannels = Int(basic.mChannelsPerFrame)
        }
    }

    /// "avc1", "ec-3": the four characters of a media type code.
    static func fourCC(_ code: UInt32, littleEndian: Bool = false) -> String {
        let shifts: [UInt32] = littleEndian ? [0, 8, 16, 24] : [24, 16, 8, 0]
        let bytes = shifts.map { UInt8((code >> $0) & 0xFF) }
        return (String(bytes: bytes, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }
}
