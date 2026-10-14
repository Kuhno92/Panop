import Foundation

/// What can go wrong in a call. The cases carry numbers and dates only: never the address, the key or the body,
/// because an error ends up in places such as logs and the request carries the person's key.
public enum SportsError: Error, Equatable, Sendable {
    /// No key, or one the service refused.
    case unauthorized
    /// The day's requests are used up. `resetsAt` is when they come back, if the reply said.
    case dailyLimit(resetsAt: Date?)
    case status(Int)
    /// The reply was not in a shape this app can read at all.
    case undecodable
    /// The service could not be reached.
    case network
}
