import Foundation

/// Every number the rails depend on, in one place. Nothing here is learned: they are plain
/// thresholds, chosen by looking at a real provider's data, and meant to be tuned by hand.
public struct RailRules: Sendable, Equatable {
    /// A rail with fewer titles than this is not drawn.
    public var minimumRailSize = 5
    /// Titles in a rail.
    public var railSize = 20

    /// "New releases" are from this year or the one before.
    public var newReleaseYears = 1
    public var newReleaseMinimumRating = 6.5

    public var topRatedMinimum = 7.5
    /// A rating this high on a provider's list is almost always a single vote, so it is not trusted.
    public var ratingCeiling = 9.4

    public var classicsBeforeYear = 2000
    public var classicsMinimumRating = 7.0
    public var decadeMinimumRating = 6.5
    public var maxDecadeRails = 2

    public var maxGenreRails = 3
    public var genreMinimumRating = 6.5

    public var franchiseMinimumTitles = 3
    public var maxFranchiseRails = 2

    /// How many of the strongest seeds get a "Because you watched" rail of their own.
    public var becauseRails = 2
    /// Candidates scoring below this against a seed are not alike enough to suggest.
    public var similarityMinimum = 0.22

    /// Titles opened at least this often are "most watched".
    public var mostWatchedMinimumPlays = 2

    // Weights of what makes two titles alike (see ``Similarity``). They add up past 1 on purpose:
    // few titles have all of it, and the score is capped at 1.
    public var genreWeight = 0.40
    public var castWeight = 0.15
    public var categoryWeight = 0.15
    public var yearWeight = 0.10
    public var ratingWeight = 0.05
    public var franchiseWeight = 0.40
    /// Years apart at which two titles stop counting as of the same time.
    public var yearSpan = 15.0

    public static let standard = RailRules()

    public init() {}
}
