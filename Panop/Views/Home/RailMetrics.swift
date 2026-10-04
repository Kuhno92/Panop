import SwiftUI

/// The measures every row of cards shares, so Home, Movies and Series line up and a change is made once.
enum RailMetrics {
    /// Between cards. Apple TV is read from further away and its focused card grows.
    static var spacing: CGFloat {
        #if os(tvOS)
            40
        #else
            12
        #endif
    }

    /// A focused card on Apple TV grows, and the row would clip it.
    static var verticalRoom: CGFloat {
        #if os(tvOS)
            24
        #else
            0
        #endif
    }

    /// A poster in a row. Wide enough that the next one shows at the edge on a phone, which says "scroll".
    static var posterWidth: CGFloat {
        #if os(tvOS)
            200
        #else
            118
        #endif
    }

    /// Between one row and the next.
    static var rowSpacing: CGFloat {
        #if os(tvOS)
            40
        #else
            26
        #endif
    }

    static let posterRadius: CGFloat = 10
}
