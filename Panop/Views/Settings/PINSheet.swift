import SwiftUI

/// What a PIN is being asked for.
enum PINPurpose: String, Identifiable {
    /// Before turning the adult filter off.
    case unlock
    case create
    case change
    case remove
    /// Just proof that the PIN is known, for something the caller then does.
    case confirm

    var id: String {
        rawValue
    }
}

/// Asks for a PIN in the steps its purpose needs: the current one, or a new one entered twice.
struct PINSheet: View {
    let purpose: PINPurpose
    /// Called once, when the steps are done and right.
    let onDone: () -> Void

    @Environment(ParentalControls.self) private var controls
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case current, new, confirm
    }

    @State private var step: Step
    @State private var entry = ""
    @State private var chosen = ""
    @State private var verified = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    init(purpose: PINPurpose, onDone: @escaping () -> Void) {
        self.purpose = purpose
        self.onDone = onDone
        _step = State(initialValue: purpose == .create ? .new : .current)
    }

    private var prompt: String {
        switch step {
        case .current: "Enter your PIN"
        case .new: "Choose a PIN of 4 to 6 digits"
        case .confirm: "Enter it again"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(prompt, text: $entry)
                        .focused($focused)
                        .onSubmit(submit)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                        .accessibilityLabel(prompt)
                } header: {
                    Text(prompt)
                } footer: {
                    if let message {
                        Text(message).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Continue", action: submit)
                        .disabled(entry.isEmpty)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private var title: String {
        switch purpose {
        case .unlock: "Show adult content"
        case .create: "Set a PIN"
        case .change: "Change PIN"
        case .remove: "Remove PIN"
        case .confirm: "Enter PIN"
        }
    }

    private func submit() {
        let text = entry
        entry = ""
        message = nil
        switch step {
        case .current:
            check(current: text)
        case .new:
            guard ParentalControls.isValid(text) else {
                message = "A PIN is 4 to 6 digits."
                return
            }
            chosen = text
            step = .confirm
        case .confirm:
            guard text == chosen else {
                message = "The two did not match. Choose a PIN again."
                chosen = ""
                step = .new
                return
            }
            controls.setPIN(chosen)
            finish()
        }
    }

    private func check(current text: String) {
        let attempt = purpose == .remove ? controls.removePIN(current: text) : controls.verify(text)
        switch attempt {
        case .accepted:
            verified = text
            switch purpose {
            case .change: step = .new
            default: finish()
            }
        case let .wrong(left):
            message = left == 1 ? "Wrong PIN. One try left before it locks." : "Wrong PIN. \(left) tries left."
        case let .locked(until):
            message = "Too many tries. Try again at \(until.formatted(date: .omitted, time: .shortened))."
        }
    }

    private func finish() {
        onDone()
        dismiss()
    }
}
