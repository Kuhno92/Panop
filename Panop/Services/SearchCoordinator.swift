import Observation
import SwiftUI

/// The tab bar's search icon is a request, not a place: choosing it asks the screen on show to open its own search
/// field. The coordinator carries the request; each screen answers it only when it is the one the request is for.
@MainActor
@Observable
final class SearchCoordinator {
    private(set) var tick = 0
    private(set) var target = AppTab.home

    func request(for tab: AppTab) {
        target = tab
        tick &+= 1
    }
}

/// Search for the screen it is on: the system's search field, opened when the tab bar's search icon is chosen
/// while this screen is showing. What is typed belongs to this screen, so on Series it searches series and on Live
/// TV channels.
struct ScreenSearch: ViewModifier {
    @Binding var text: String
    let tab: AppTab
    let prompt: LocalizedStringKey
    /// Apple TV shows the field only once there is something to search: before the first playlist its keyboard,
    /// half the screen, would sit above a message about adding one.
    let isOffered: Bool

    @Environment(SearchCoordinator.self) private var coordinator
    @State private var presented = false

    func body(content: Content) -> some View {
        #if os(tvOS)
            if isOffered {
                searchable(content)
            } else {
                content
            }
        #else
            searchable(content)
        #endif
    }

    private func searchable(_ content: Content) -> some View {
        #if os(tvOS)
            // The field is always on the screen there, and cannot be opened from outside: Search is a screen of its
            // own.
            content.searchable(text: $text, prompt: prompt)
        #else
            content
                .searchable(text: $text, isPresented: $presented, prompt: prompt)
                .onChange(of: coordinator.tick) {
                    if coordinator.target == tab {
                        presented = true
                    }
                }
        #endif
    }
}
