import Foundation

/// What an engine knows of the stream it is playing, in the engine's own words (a libavcodec name, a FourCC, a
/// container name). `StreamInfoText` turns it into what a person reads. Every field is optional: an engine reports
/// what it has, and what it does not have is simply not shown.
public struct StreamInfo: Sendable, Equatable {
    public var container: String?
    public var videoCodec: String?
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    /// "HDR10", "HLG", "Dolby Vision" or "HDR" when the engine knows the picture is high dynamic range.
    public var hdr: String?
    public var audioCodec: String?
    public var audioChannels: Int?
    /// Only an engine that can tell (E-AC-3 with JOC, TrueHD with Atmos) says so; most cannot.
    public var audioIsAtmos = false

    public init(
        container: String? = nil,
        videoCodec: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        hdr: String? = nil,
        audioCodec: String? = nil,
        audioChannels: Int? = nil,
        audioIsAtmos: Bool = false
    ) {
        self.container = container
        self.videoCodec = videoCodec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.hdr = hdr
        self.audioCodec = audioCodec
        self.audioChannels = audioChannels
        self.audioIsAtmos = audioIsAtmos
    }

    public var isEmpty: Bool {
        self == StreamInfo()
    }
}

/// The words for a `StreamInfo`: "MPEG-TS", "1080p50", "HEVC", "HDR10", "Dolby Digital Plus 5.1".
public enum StreamInfoText {
    /// The parts in reading order, none empty: container, picture, video codec, HDR, sound.
    public static func parts(_ info: StreamInfo) -> [String] {
        [
            container(info.container),
            resolution(width: info.width, height: info.height, frameRate: info.frameRate),
            videoCodec(info.videoCodec),
            info.hdr,
            sound(codec: info.audioCodec, channels: info.audioChannels, isAtmos: info.audioIsAtmos)
        ].compactMap(\.self).filter { !$0.isEmpty }
    }

    public static func summary(_ info: StreamInfo) -> String? {
        let parts = parts(info)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A guess at the container from the address, for an engine that cannot say: `.m3u8` is HLS, `.ts` MPEG-TS.
    /// Nil where the address says nothing (many IPTV addresses have no extension).
    public static func containerHint(address: String) -> String? {
        let path = address.split(separator: "?").first.map(String.init) ?? address
        guard let ext = path.split(separator: ".").last?.lowercased(), path.contains(".") else { return nil }
        switch ext {
        case "m3u8", "m3u": return "hls"
        case "ts", "m2ts": return "mpegts"
        case "mp4", "m4v", "mov": return "mp4"
        case "mkv", "webm": return "matroska"
        case "mpd": return "dash"
        case "flv": return "flv"
        case "avi": return "avi"
        default: return nil
        }
    }

    public static func container(_ raw: String?) -> String? {
        guard let name = raw?.lowercased(), !name.isEmpty else { return nil }
        // FFmpeg joins the names a demuxer answers to: "mov,mp4,m4a,3gp,3g2,mj2", "hls,applehttp".
        if name.contains("hls") || name.contains("applehttp") || name.contains("m3u8") {
            return "HLS"
        }
        if name.contains("dash") || name.contains("mpd") {
            return "DASH"
        }
        if name.contains("mpegts") || name == "ts" {
            return "MPEG-TS"
        }
        if name.contains("matroska") || name.contains("webm") || name == "mkv" {
            return "MKV"
        }
        if name.contains("mp4") || name.contains("mov") {
            return "MP4"
        }
        if name.contains("flv") {
            return "FLV"
        }
        if name.contains("avi") {
            return "AVI"
        }
        if name == "mpeg" || name.contains("mpegps") {
            return "MPEG-PS"
        }
        return nil
    }

    /// "4K", "1080p", "720p50": the class of picture by its width (a film cropped to 1920×800 is still a 1080p
    /// picture), then its height; the frame rate is added when it is 50 or more, which is worth knowing.
    public static func resolution(width: Int?, height: Int?, frameRate: Double?) -> String? {
        let across = width ?? 0
        let down = height ?? 0
        guard across > 0 || down > 0 else { return nil }
        let label = if across >= 3200 || down >= 2000 {
            "4K"
        } else if across >= 2400 || down >= 1300 {
            "1440p"
        } else if across >= 1800 || down >= 1000 {
            "1080p"
        } else if across >= 1200 || down >= 700 {
            "720p"
        } else if down > 0 {
            "\(down)p"
        } else {
            "\(across)p"
        }
        if let rate = frameRate, rate >= 49 {
            return label + String(Int(rate.rounded()))
        }
        return label
    }

    public static func videoCodec(_ raw: String?) -> String? {
        guard let name = raw?.lowercased().trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        switch name {
        case "h264", "avc", "avc1", "avc3", "x264": return "H.264"
        case "hevc", "h265", "hvc1", "hev1", "dvh1", "dvhe": return "HEVC"
        case "av1", "av01": return "AV1"
        case "mpeg2video", "mpeg2", "mpg2", "mp2v", "m2v1", "mpgv": return "MPEG-2"
        case "mpeg4", "mp4v", "xvid", "divx": return "MPEG-4"
        case "vp9", "vp09": return "VP9"
        case "vp8", "vp08": return "VP8"
        case "vc1", "wvc1": return "VC-1"
        case "mjpeg", "jpeg": return "MJPEG"
        default: return name.uppercased()
        }
    }

    public static func audioCodec(_ raw: String?, isAtmos: Bool = false) -> String? {
        guard let name = raw?.lowercased().trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        switch name {
        case "eac3", "ec-3", "ec3": return isAtmos ? "Dolby Atmos" : "Dolby Digital Plus"
        case "ac3", "ac-3", "a52", "a52b": return "Dolby Digital"
        case "truehd", "mlp", "mlpa": return isAtmos ? "Dolby Atmos" : "Dolby TrueHD"
        case let dts where dts.hasPrefix("dts") || dts == "dca": return "DTS"
        case "aac", "mp4a", "aac_latm": return "AAC"
        case "mp3", ".mp3": return "MP3"
        case "mpga": return "MPEG Audio"
        case "mp2", "mp2a": return "MP2"
        case "opus": return "Opus"
        case "flac": return "FLAC"
        case "vorbis": return "Vorbis"
        case "pcm_s16le", "pcm_s24le", "lpcm", "pcm": return "PCM"
        default: return name.uppercased()
        }
    }

    public static func channels(_ count: Int?) -> String? {
        switch count {
        case nil, 0: nil
        case 1: "Mono"
        case 2: "Stereo"
        case 3: "2.1"
        case 4: "4.0"
        case 6: "5.1"
        case 7: "6.1"
        case 8: "7.1"
        case let other?: "\(other) ch"
        }
    }

    public static func sound(codec: String?, channels count: Int?, isAtmos: Bool = false) -> String? {
        let name = audioCodec(codec, isAtmos: isAtmos)
        let layout = channels(count)
        switch (name, layout) {
        case let (name?, layout?): return "\(name) \(layout)"
        case let (name?, nil): return name
        case let (nil, layout?): return layout
        default: return nil
        }
    }
}
