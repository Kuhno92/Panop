/// The `tvg-*` and related attributes carried on an M3U `#EXTINF` line.
///
/// Every field is optional because providers are wildly inconsistent about
/// which they emit, and a missing attribute is normal rather than an error.
public struct ChannelAttributes: Sendable, Equatable, Hashable, Codable {
    /// Ties the entry to an EPG channel. The single most important attribute.
    public var tvgID: String?
    public var tvgName: String?
    public var tvgLogo: String?
    /// Provider's own grouping, such as "Sports" or "DE | Nachrichten".
    public var groupTitle: String?
    /// Hours to shift EPG times by, as written. Parsing is deferred to the EPG layer.
    public var tvgShift: String?
    /// Catch-up/archive support, typically "default", "append", "shift" or "flussonic".
    public var catchup: String?
    public var catchupSource: String?
    /// How many days of catch-up the provider claims to retain.
    public var catchupDays: String?

    public init(
        tvgID: String? = nil,
        tvgName: String? = nil,
        tvgLogo: String? = nil,
        groupTitle: String? = nil,
        tvgShift: String? = nil,
        catchup: String? = nil,
        catchupSource: String? = nil,
        catchupDays: String? = nil
    ) {
        self.tvgID = tvgID
        self.tvgName = tvgName
        self.tvgLogo = tvgLogo
        self.groupTitle = groupTitle
        self.tvgShift = tvgShift
        self.catchup = catchup
        self.catchupSource = catchupSource
        self.catchupDays = catchupDays
    }

    public var isEmpty: Bool {
        tvgID == nil && tvgName == nil && tvgLogo == nil && groupTitle == nil
            && tvgShift == nil && catchup == nil && catchupSource == nil && catchupDays == nil
    }
}
