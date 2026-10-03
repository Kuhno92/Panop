import Foundation
@testable import Panop
import SwiftData
import Testing

@Suite("Profiles")
@MainActor
struct ProfileTests {
    private func defaults() -> UserDefaults {
        let name = "panop-profile-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func state(_ container: ModelContainer, profile: String) -> UserStateStore {
        UserStateStore(context: ModelContext(container), profile: profile)
    }

    // MARK: - The list

    @Test
    func `there is always a first profile, which keeps the adult filter as it was`() {
        let store = defaults()
        store.set(false, forKey: UserStateStore.hideAdultKey)

        let profiles = ProfileStore(defaults: store)

        #expect(profiles.profiles.map(\.name) == ["Main"])
        #expect(profiles.currentID == "")
        #expect(profiles.current.hidesAdult == false)
    }

    @Test
    func `profiles are added, renamed and kept across a restart`() {
        let store = defaults()
        let profiles = ProfileStore(defaults: store)
        let kids = profiles.add(name: "  Kids ")
        profiles.switchTo(kids?.id ?? "")
        profiles.rename(kids?.id ?? "", to: "Little ones")

        let again = ProfileStore(defaults: store)

        #expect(again.profiles.map(\.name) == ["Main", "Little ones"])
        #expect(again.current.name == "Little ones")
        #expect(again.current.hidesAdult, "a new profile starts with the filter on")
        #expect(ProfileStore.savedCurrentID(defaults: store) == kids?.id)
    }

    @Test
    func `an empty name is refused and there is a limit`() {
        let profiles = ProfileStore(defaults: defaults())
        #expect(profiles.add(name: "   ") == nil)
        for index in 1 ..< ProfileStore.limit {
            #expect(profiles.add(name: "P\(index)") != nil)
        }
        #expect(profiles.add(name: "One too many") == nil)
        #expect(profiles.profiles.count == ProfileStore.limit)
    }

    @Test
    func `the first profile cannot be deleted, and deleting the one in use goes back to it`() {
        let profiles = ProfileStore(defaults: defaults())
        let kids = profiles.add(name: "Kids")
        profiles.switchTo(kids?.id ?? "")

        #expect(!profiles.delete(""))
        #expect(profiles.delete(kids?.id ?? ""))

        #expect(profiles.currentID == "")
        #expect(profiles.profiles.count == 1)
    }

    @Test
    func `the adult filter is per profile`() {
        let profiles = ProfileStore(defaults: defaults())
        let kids = profiles.add(name: "Kids")
        profiles.setHidesAdult(false, for: "")

        #expect(profiles.profiles.first?.hidesAdult == false)
        #expect(profiles.profiles.first { $0.id == kids?.id }?.hidesAdult == true)
    }

    // MARK: - What each one has

    @Test
    func `favourites, history and hidden titles belong to one profile`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let main = state(container, profile: "")
        main.toggleFavorite("p|a")
        main.markPlayed("p|b")
        main.setHidden(true, for: "p|c")

        let kids = state(container, profile: "kids")

        #expect(kids.favorites.isEmpty && kids.recents.isEmpty && kids.hidden.isEmpty)
        kids.toggleFavorite("p|z")
        #expect(main.favorites == ["p|a"], "a change in another profile does not reach this one")
        main.reload()
        #expect(main.favorites == ["p|a"])
        #expect(main.recents == ["p|b"])
    }

    @Test
    func `the same title can be a favourite of one profile and not of another`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let main = state(container, profile: "")
        let kids = state(container, profile: "kids")

        main.toggleFavorite("p|a")
        kids.toggleFavorite("p|a")
        kids.toggleFavorite("p|a")

        #expect(main.isFavorite("p|a"))
        #expect(!kids.isFavorite("p|a"))
    }

    @Test
    func `switching profile shows the other one's state and keeps both`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let store = state(container, profile: "")
        store.toggleFavorite("p|main")

        store.switchProfile("kids")
        #expect(store.favorites.isEmpty)
        store.toggleFavorite("p|kid")
        #expect(store.favorites == ["p|kid"])

        store.switchProfile("")
        #expect(store.favorites == ["p|main"])
    }

    @Test
    func `category choices belong to one profile`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let main = state(container, profile: "")
        main.setCategoryHidden(true, name: "News", kind: .live)

        let kids = state(container, profile: "kids")

        #expect(main.userHiddenCategories(of: .live) == ["News"])
        #expect(kids.userHiddenCategories(of: .live).isEmpty)
    }

    @Test
    func `deleting a profile removes its state and no one else's`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let main = state(container, profile: "")
        main.toggleFavorite("p|a")
        let kids = state(container, profile: "kids")
        kids.toggleFavorite("p|b")
        kids.setCategoryHidden(true, name: "News", kind: .live)

        main.deleteProfileData("kids")

        #expect(state(container, profile: "kids").favorites.isEmpty)
        #expect(state(container, profile: "kids").userHiddenCategories(of: .live).isEmpty)
        #expect(state(container, profile: "").favorites == ["p|a"])
    }

    @Test
    func `forgetting a playlist removes it from every profile`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let main = state(container, profile: "")
        main.toggleFavorite("gone|1")
        let kids = state(container, profile: "kids")
        kids.toggleFavorite("gone|2")
        kids.toggleFavorite("kept|3")

        main.forget(playlist: "gone")

        #expect(state(container, profile: "").favorites.isEmpty)
        #expect(state(container, profile: "kids").favorites == ["kept|3"])
    }
}
