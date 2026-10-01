import SwiftUI

/// What to ask when a film or episode was left part-way: pick up there, or start over.
struct ResumeChoice: Identifiable {
    let id = UUID()
    let title: String
    let position: Double
    /// Called with where to start: the position, or nil for the beginning.
    let start: (Double?) -> Void
}

extension View {
    /// Offers "Resume from 32:10" and "Start over" for a film left part-way.
    func resumeDialog(_ choice: Binding<ResumeChoice?>) -> some View {
        confirmationDialog(
            choice.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { choice.wrappedValue != nil },
                set: {
                    if !$0 {
                        choice.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: choice.wrappedValue
        ) { pending in
            Button("Resume from \(PlayerTime.text(pending.position))") { pending.start(pending.position) }
            Button("Start over") { pending.start(nil) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
