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

    @Environment(SearchCoordinator.self) private var coordinator
    @State private var open = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(tvOS)
            // No field on the screens there: it was always shown, with its keyboard above the content. Search is a
            // screen of its own, reached by the icon in the top bar (`SearchTabView`).
            content
        #else
            // The field floats over the top of the screen instead of taking room from it, and the screen under it is
            // never rebuilt or moved: putting the system's field in and out reshuffled the page and the hero started
            // over.
            content
                .overlay(alignment: .top) {
                    if open {
                        field
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onChange(of: coordinator.tick) {
                    if coordinator.target == tab {
                        show()
                    }
                }
        #endif
    }

    #if !os(tvOS)
        private var field: some View {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("searchField")
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            #if os(macOS)
                .onExitCommand(perform: close)
            #endif
        }

        private func show() {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { open = true }
            focused = true
        }

        private func close() {
            focused = false
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { open = false }
            text = ""
        }
    #endif
}
