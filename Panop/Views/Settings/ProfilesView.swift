import SwiftUI

/// The people who use the app: each has their own favourites, history and hidden titles, and their own
/// adult-content filter. Switching to one with the filter off asks for the PIN, if there is one.
struct ProfilesView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(UserStateStore.self) private var userState
    @Environment(ParentalControls.self) private var parental

    @State private var adding = false
    @State private var newName = ""
    @State private var renaming: Profile?
    @State private var renamed = ""
    @State private var pinPurpose: PINPurpose?
    @State private var afterPIN: (() -> Void)?

    var body: some View {
        List {
            Section {
                ForEach(profiles.profiles) { profile in
                    Button { choose(profile) } label: {
                        HStack {
                            Text(profile.name)
                            Spacer()
                            if profile.hidesAdult {
                                Image(systemName: "lock.shield")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Adult content hidden")
                            }
                            if profile.id == profiles.currentID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("In use")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename…", systemImage: "pencil") {
                            renamed = profile.name
                            renaming = profile
                        }
                        if profile.id != profiles.profiles.first?.id {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(profile) }
                        }
                    }
                }
            } footer: {
                Text("Each profile keeps its own favourites, what it has watched and hidden, and its own adult filter.")
            }
            Section {
                Button("Add profile…") { adding = true }
                    .disabled(!profiles.canAdd)
            }
        }
        .pageBackdrop()
        .navigationTitle("Profiles")
        .alert("New profile", isPresented: $adding) {
            TextField("Name", text: $newName)
            Button("Add") {
                profiles.add(name: newName)
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("It starts with adult content hidden.")
        }
        .alert("Rename profile", isPresented: Binding(get: { renaming != nil }, set: {
            if !$0 {
                renaming = nil
            }
        })) {
            TextField("Name", text: $renamed)
            Button("Rename") {
                if let renaming {
                    profiles.rename(renaming.id, to: renamed)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .sheet(item: $pinPurpose) { purpose in
            PINSheet(purpose: purpose) { afterPIN?() }
        }
    }

    /// Switches to a profile, after the PIN when that would take the adult filter off.
    private func choose(_ profile: Profile) {
        guard profile.id != profiles.currentID else { return }
        if parental.hasPIN, profiles.removesAdultFilter(switchingTo: profile.id) {
            afterPIN = { profiles.switchTo(profile.id) }
            pinPurpose = .confirm
        } else {
            profiles.switchTo(profile.id)
        }
    }

    /// Deleting loses a person's history, so with a PIN set it asks for it.
    private func delete(_ profile: Profile) {
        let remove = {
            userState.deleteProfileData(profile.id)
            profiles.delete(profile.id)
        }
        if parental.hasPIN {
            afterPIN = remove
            pinPurpose = .confirm
        } else {
            remove()
        }
    }
}

/// A menu to change profile quickly, shown only when there is more than one.
struct ProfileMenu: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(ParentalControls.self) private var parental
    @State private var pinFor: Profile?

    var body: some View {
        if profiles.profiles.count > 1 {
            Menu {
                ForEach(profiles.profiles) { profile in
                    Button {
                        choose(profile)
                    } label: {
                        if profile.id == profiles.currentID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            } label: {
                Label(profiles.current.name, systemImage: "person.crop.circle")
            }
            .accessibilityLabel("Profile")
            .sheet(item: $pinFor) { profile in
                PINSheet(purpose: .confirm) { profiles.switchTo(profile.id) }
            }
        }
    }

    private func choose(_ profile: Profile) {
        if parental.hasPIN, profiles.removesAdultFilter(switchingTo: profile.id) {
            pinFor = profile
        } else {
            profiles.switchTo(profile.id)
        }
    }
}
