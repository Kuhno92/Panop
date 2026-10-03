import Foundation
import Observation

/// One person using the app: their own favourites, history, hidden titles and category choices, and
/// their own adult-content filter.
nonisolated struct Profile: Codable, Identifiable, Equatable, Hashable {
    /// Empty for the first profile, which owns everything saved before profiles existed.
    var id: String
    var name: String
    var hidesAdult: Bool
}

/// The list of profiles and which one is in use, kept in the app's defaults.
///
/// Only the list lives here. What a profile has watched is in the user-state rows, marked with its id
/// (see `UserStateStore.profile`). The list stays on this device for now: syncing it waits for the
/// CloudKit container.
@MainActor
@Observable
final class ProfileStore {
    static let listKey = "profiles"
    static let currentKey = "currentProfile"
    static let limit = 8

    private(set) var profiles: [Profile]
    private(set) var currentID: String

    private let defaults: UserDefaults

    /// Where the list is kept: the app's defaults, or under UI tests a store wiped at each launch so a
    /// run never meets the last one's profiles.
    static let runDefaults: UserDefaults = {
        guard UITestMode.isActive else { return .standard }
        let name = "panop-uitest-profiles"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }()

    init(defaults: UserDefaults = ProfileStore.runDefaults) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.listKey).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) }
        // The first profile keeps the adult filter as it was set before there were profiles.
        let hides = defaults.object(forKey: UserStateStore.hideAdultKey) as? Bool ?? true
        let list = saved.flatMap { $0.isEmpty ? nil : $0 } ?? [Profile(id: "", name: "Main", hidesAdult: hides)]
        let wanted = defaults.string(forKey: Self.currentKey) ?? ""
        profiles = list
        currentID = list.contains { $0.id == wanted } ? wanted : list[0].id
        save()
    }

    /// The profile in use when the app starts, known before the store exists: user state opens on it.
    static func savedCurrentID(defaults: UserDefaults = ProfileStore.runDefaults) -> String {
        defaults.string(forKey: currentKey) ?? ""
    }

    var current: Profile {
        profiles.first { $0.id == currentID } ?? profiles[0]
    }

    var canAdd: Bool {
        profiles.count < Self.limit
    }

    @discardableResult
    func add(name: String, hidesAdult: Bool = true) -> Profile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canAdd else { return nil }
        let profile = Profile(id: UUID().uuidString, name: trimmed, hidesAdult: hidesAdult)
        profiles.append(profile)
        save()
        return profile
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        save()
    }

    /// The first profile cannot be deleted: it owns what was saved before, and there is always one.
    /// Deleting the one in use switches to the first.
    @discardableResult
    func delete(_ id: String) -> Bool {
        guard id != profiles.first?.id, let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: index)
        if currentID == id {
            currentID = profiles[0].id
        }
        save()
        return true
    }

    /// Whether moving to `id` would take the adult filter off for whoever is using the app now. With a PIN
    /// set, that is what the PIN is asked for: a child must not step around the filter by switching.
    func removesAdultFilter(switchingTo id: String) -> Bool {
        guard let target = profiles.first(where: { $0.id == id }) else { return false }
        return current.hidesAdult && !target.hidesAdult
    }

    func switchTo(_ id: String) {
        guard profiles.contains(where: { $0.id == id }), id != currentID else { return }
        currentID = id
        save()
    }

    func setHidesAdult(_ hides: Bool, for id: String? = nil) {
        let target = id ?? currentID
        guard let index = profiles.firstIndex(where: { $0.id == target }) else { return }
        profiles[index].hidesAdult = hides
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.listKey)
        }
        defaults.set(currentID, forKey: Self.currentKey)
    }
}
