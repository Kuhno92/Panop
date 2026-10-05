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

    /// Not present in official builds.
    ///
    /// KSPlayer is GPL-3.0, which would relicense Panop and forfeit App Store
    /// distribution. The adapter is compiled only under the
    /// `PANOP_ENABLE_KSPLAYER` condition, for someone who adds the dependency
    /// to their own build and accepts GPL-3.0 for it.
    /// See docs/adr/0002 and THIRD-PARTY-NOTICES.md.
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
        #if PANOP_ENABLE_KSPLAYER
            return allCases
        #else
            return allCases.filter { $0 != .ksPlayer }
        #endif
    }

    /// Default fallback order, most system-integrated first.
    ///
    /// AVPlayer leads because when it works it gives PiP, AirPlay and the best
    /// battery life. The FFmpeg-backed engines follow to pick up what it cannot
    /// open, which on real provider playlists is a substantial share.
    public static var defaultPriority: [PlaybackEngineKind] {
        available.sorted { lhs, rhs in
            let order: [PlaybackEngineKind] = [.avPlayer, .lumeEngine, .aetherEngine, .vlcKit, .ksPlayer]
            let lhsIndex = order.firstIndex(of: lhs) ?? order.count
            let rhsIndex = order.firstIndex(of: rhs) ?? order.count
            return lhsIndex < rhsIndex
        }
    }
}
