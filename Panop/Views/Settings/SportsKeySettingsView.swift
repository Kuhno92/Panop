import SwiftUI

/// The Sports section of Settings on a screen of its own: where the hub, with no key yet, sends the person to enter
/// one, without a search through Settings for it. It is the same section Settings shows.
struct SportsKeySettingsView: View {
    var body: some View {
        Form {
            SportsSettingsSection()
        }
        .formStyle(.grouped)
        .pageBackdrop()
        .navigationTitle("Sports")
    }
}
