import SwiftUI

/// Search for the screen it is on: a magnifier at the leading edge, just under the section bar, that opens
/// into a field with a way to close it again. What is typed belongs to that screen, so on Series it searches
/// series, on Live TV channels.
///
/// The inset is always there and only its content comes and goes, because changing a screen's structure when
/// the first playlist loads rebuilt it before (see `ChannelSearch`).
struct ExpandingSearch: ViewModifier {
    @Binding var text: String
    /// Kept by the screen, not here: a screen that swaps its content for the results as the first letter is typed
    /// would otherwise take this row with it and close the field under the person's finger.
    @Binding var isOpen: Bool
    let prompt: LocalizedStringKey
    let isOffered: Bool

    func body(content: Content) -> some View {
        content
        #if os(tvOS)
            // The magnifier is at the left edge, and focus moving down from it would find nothing below it where
            // the content is centred. The content as one section, as wide as the screen, is found from anywhere.
            .focusSection()
        #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                if isOffered {
                    SearchRow(text: $text, open: $isOpen, prompt: prompt)
                }
            }
    }
}

private struct SearchRow: View {
    @Binding var text: String
    @Binding var open: Bool
    let prompt: LocalizedStringKey

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Image(systemName: "magnifyingglass")
                    .font(Self.iconFont)
                    .foregroundStyle(open ? Color.secondary : Color.primary)
                    .frame(width: Self.size, height: Self.size)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            if open {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("searchField")
                    .transition(.opacity)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Self.iconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: Self.size, height: Self.size)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
                .transition(.opacity)
            }
        }
        // A field that lost focus because the screen under it changed takes it back, so a word typed quickly is not
        // cut off after its first letter.
        .onChange(of: text) {
            if open, !focused {
                focused = true
            }
        }
        .padding(.horizontal, open ? 6 : 0)
        .frame(maxWidth: open ? .infinity : Self.size + 0, alignment: .leading)
        .background {
            Capsule().fill(.regularMaterial).opacity(open ? 1 : 0)
        }
        .padding(.horizontal, Self.edge)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(tvOS)
            // The magnifier sits at the left, off the tab bar's centre, and focus going down would step past it
            // to whatever is below. A section as wide as the screen catches it.
            .focusSection()
        #endif
        #if !os(iOS)
        .onExitCommand(perform: close)
        #endif
    }

    private func toggle() {
        if open {
            close()
        } else {
            show()
        }
    }

    private func show() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { open = true }
        focused = true
    }

    private func close() {
        focused = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            open = false
            text = ""
        }
    }

    private static var size: CGFloat {
        #if os(tvOS)
            64
        #else
            36
        #endif
    }

    private static var edge: CGFloat {
        #if os(tvOS)
            60
        #else
            16
        #endif
    }

    private static var iconFont: Font {
        #if os(tvOS)
            .title3
        #else
            .body.weight(.semibold)
        #endif
    }
}
