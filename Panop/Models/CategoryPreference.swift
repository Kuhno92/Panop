import Foundation
import SwiftData

/// What the person has chosen for one category of one kind: hidden, and where it stands among
/// the others. Lives in the **cloud** container with the rest of their state, so it follows the
/// CloudKit rules (every property defaulted, nothing unique, no relationships).
///
/// Keyed by kind and name, not by a provider's category id: two sources that both have "News"
/// are one category to the person, and ids differ between providers.
@Model
final class CategoryPreference {
    var kindRaw: String = ""
    var name: String = ""
    var isHidden: Bool = false
    /// Where the person put it, from 0. -1 for a category they have not placed, which then
    /// follows the placed ones in the order the provider lists it.
    var position: Int = -1

    init(kindRaw: String = "", name: String = "", isHidden: Bool = false, position: Int = -1) {
        self.kindRaw = kindRaw
        self.name = name
        self.isHidden = isHidden
        self.position = position
    }
}
