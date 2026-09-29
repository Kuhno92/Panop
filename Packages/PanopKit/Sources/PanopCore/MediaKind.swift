/// What sort of thing a stream points at.
///
/// Providers rarely label this explicitly, so it is usually inferred. Treat it
/// as a strong hint rather than ground truth.
public enum MediaKind: String, Sendable, Codable, CaseIterable {
    case live
    case movie
    case series
    case unknown
}
