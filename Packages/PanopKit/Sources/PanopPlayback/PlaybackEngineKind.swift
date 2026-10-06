/// The playback engines Panop knows about.
public enum PlaybackEngineKind: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {
    /// Apple's AVPlayer. Native PiP, AirPlay and Now Playing, best battery life,
    /// but cannot play raw MPEG-TS over HTTP.
    case avPlayer

    /// libVLC. The broadest format coverage, at the cost of binary size and
    /// weaker system integration.
    case vlcKit

    /// FFmpeg 9 engine built for long-running live IPTV streams.
    case lumeEngine

    /// An FFmpeg demuxer with VideoToolbox decoding and AVPlayer or sample-buffer display (LGPL-3.0 with an
    /// Apple Store exception). Plays raw MPEG-TS and the containers AVPlayer refuses, with hardware decoding
    /// and HDR, and keeps a rewindable window of a live stream.
    case aetherEngine

    /// KSPlayer: an FFmpeg engine with its own Metal renderer and subtitle parsing. GPL-3.0, which is why Panop
    /// is GPL-3.0 as a whole (see LICENSE and docs/adr/0010).
    case ksPlayer

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .avPlayer: "AVPlayer"
        case .vlcKit: "VLC"
        case .lumeEngine: "LumeEngine"
        case .aetherEngine: "AetherEngine"
        case .ksPlayer: "KSPlayer"
        }
    }

    /// Engines actually available to the user in this build.
    ///
    /// Prefer this over `allCases` anywhere a list is shown or a fallback order
    /// is built; `allCases` includes engines that are not linked.
    public static var available: [PlaybackEngineKind] {
        allCases
    }

    /// Goes up whenever the built-in engine order changes (a new engine, or a reorder from measurements). The app drops
    /// what it learned about which engine plays which title when it sees a new number, so the new order is tried
    /// instead of an engine remembered under the old one.
    public static let orderRevision = 2

    /// Default fallback order, most system-integrated first.
    ///
    /// AVPlayer leads because when it works it gives PiP, AirPlay and the best
    /// battery life. The FFmpeg-backed engines follow to pick up what it cannot
    /// open, which on real provider playlists is a substantial share.
    public static var defaultPriority: [PlaybackEngineKind] {
        available.sorted { lhs, rhs in
            let order: [PlaybackEngineKind] = [.avPlayer, .lumeEngine, .vlcKit, .aetherEngine, .ksPlayer]
            let lhsIndex = order.firstIndex(of: lhs) ?? order.count
            let rhsIndex = order.firstIndex(of: rhs) ?? order.count
            return lhsIndex < rhsIndex
        }
    }
}
