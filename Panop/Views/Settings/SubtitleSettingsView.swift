import SwiftUI

/// How subtitles look, with a preview over a picture-like background.
struct SubtitleSettingsView: View {
    @AppStorage(SubtitleStyle.key) private var style = SubtitleStyle.standard

    var body: some View {
        Form {
            Section {
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [.gray, .white, .blue.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    SubtitleText(text: "The quick brown fox jumps over the lazy dog.", style: style)
                        .padding(.bottom, style.raised ? 54 : 14)
                        .padding(.horizontal, 12)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of the subtitle style")
            } footer: {
                Text(
                    "Panop draws subtitles itself with the Lume player. The system player follows this once you change it."
                )
            }
            Section {
                Picker("Size", selection: $style.size) {
                    ForEach(SubtitleStyle.Size.allCases) { Text($0.title).tag($0) }
                }
                Picker("Colour", selection: $style.tint) {
                    ForEach(SubtitleStyle.Tint.allCases) { Text($0.title).tag($0) }
                }
                Picker("Background", selection: $style.backdrop) {
                    ForEach(SubtitleStyle.Backdrop.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Raise subtitles", isOn: $style.raised)
            }
            Section {
                Button("Reset to standard", role: .destructive) { style = .standard }
                    .disabled(!style.isCustomised)
            }
        }
        .pageBackdrop()
        .navigationTitle("Subtitles")
    }
}
