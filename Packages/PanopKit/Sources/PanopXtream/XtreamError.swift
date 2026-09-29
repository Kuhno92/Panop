/// Failures from the Xtream client.
///
/// No case carries a URL, a username or a password: request URLs embed the
/// credentials, and these errors get logged.
public enum XtreamError: Error, Equatable, Sendable {
    /// The base URL is not an http(s) URL with a host.
    case invalidBaseURL
    /// The panel answered 200 but refused the login (`auth: 0`).
    case authenticationFailed
    /// A non-2xx HTTP status.
    case http(status: Int)
    /// The body was not the shape the endpoint documents. The panel may be
    /// down, misconfigured, or not an Xtream panel at all.
    case unexpectedResponse
    /// The body ended mid-list. A cut-off catalog is indistinguishable from a
    /// complete short one by content alone, so anything reconciling against it
    /// (deleting what is missing) must treat this as a failed import, never as
    /// "the provider removed these".
    case truncatedResponse
    /// The connection failed before a usable response arrived. The message has
    /// had the credentials scrubbed out.
    case transport(message: String)
}
