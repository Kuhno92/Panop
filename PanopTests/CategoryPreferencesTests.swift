import Foundation
@testable import Panop
import PanopCore
import SwiftData
import Testing

@Suite("Category preferences")
@MainActor
struct CategoryPreferencesTests {
    private let provider = ["News", "Sport", "Kids", "Music"]

    private func makeStore(_ container: ModelContainer? = nil) throws -> UserStateStore {
        try UserStateStore(context: ModelContext(container ?? PanopContainers.makeCloud(inMemory: true)))
    }

    @Test
    func `adult categories are hidden with the person's own while the switch is on, and shown when it is off`() throws {
        let store = try makeStore()
        store.adultCategoryNames[MediaKind.movie.rawValue] = ["VOD - ADULT +18"]
        store.setCategoryHidden(true, name: "Documentaries", kind: .movie)

        #expect(store.hiddenCategories(of: .movie) == ["VOD - ADULT +18", "Documentaries"])
        #expect(store.visibleCategories(["Action", "VOD - ADULT +18", "Documentaries"], kind: .movie) == ["Action"])

        store.hidesAdult = false

        #expect(store.hiddenCategories(of: .movie) == ["Documentaries"])
        #expect(store.userHiddenCategories(of: .movie) == ["Documentaries"])
    }

    @Test
    func `adult categories of one kind do not hide another kind's`() throws {
        let store = try makeStore()
        store.adultCategoryNames[MediaKind.live.rawValue] = ["FOR ADULTS"]

        #expect(store.hiddenCategories(of: .live) == ["FOR ADULTS"])
        #expect(store.hiddenCategories(of: .series).isEmpty)
    }

    @Test
    func `with no choices the provider's order stands`() throws {
        let store = try makeStore()

        #expect(store.arranged(provider, kind: .live) == provider)
        #expect(store.visibleCategories(provider, kind: .live) == provider)
    }

    @Test
    func `a category moves earlier or later, and the rest keep their places`() throws {
        let store = try makeStore()

        store.moveCategory("Kids", by: -1, among: provider, kind: .live)
        #expect(store.arranged(provider, kind: .live) == ["News", "Kids", "Sport", "Music"])

        store.moveCategory("News", by: 1, among: provider, kind: .live)
        #expect(store.arranged(provider, kind: .live) == ["Kids", "News", "Sport", "Music"])
    }

    @Test
    func `the first cannot move up and the last cannot move down`() throws {
        let store = try makeStore()

        store.moveCategory("News", by: -1, among: provider, kind: .live)
        store.moveCategory("Music", by: 1, among: provider, kind: .live)

        #expect(store.arranged(provider, kind: .live) == provider)
    }

    @Test
    func `a category the provider adds later follows the ones already placed`() throws {
        let store = try makeStore()
        store.moveCategory("Music", by: -1, among: provider, kind: .live)

        let later = provider + ["Docs"]

        #expect(store.arranged(later, kind: .live) == ["News", "Sport", "Music", "Kids", "Docs"])
    }

    @Test
    func `a hidden category is left out of what is shown, but not of what is managed`() throws {
        let store = try makeStore()

        store.setCategoryHidden(true, name: "Sport", kind: .live)

        #expect(store.visibleCategories(provider, kind: .live) == ["News", "Kids", "Music"])
        #expect(store.arranged(provider, kind: .live).contains("Sport"))
        #expect(store.hiddenCategories(of: .live) == ["Sport"])

        store.setCategoryHidden(false, name: "Sport", kind: .live)
        #expect(store.visibleCategories(provider, kind: .live) == provider)
    }

    @Test
    func `each kind has its own choices`() throws {
        let store = try makeStore()

        store.setCategoryHidden(true, name: "Drama", kind: .series)
        store.moveCategory("Sport", by: -1, among: provider, kind: .live)

        #expect(store.hiddenCategories(of: .live).isEmpty)
        #expect(store.hiddenCategories(of: .series) == ["Drama"])
        #expect(store.arranged(provider, kind: .movie) == provider)
    }

    @Test
    func `choices survive a new launch`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let first = try makeStore(container)
        first.setCategoryHidden(true, name: "Kids", kind: .live)
        first.moveCategory("Music", by: -1, among: provider, kind: .live)

        let later = try makeStore(container)

        #expect(later.hiddenCategories(of: .live) == ["Kids"])
        #expect(later.arranged(provider, kind: .live) == ["News", "Sport", "Music", "Kids"])
    }

    @Test
    func `reset puts back the provider's order and shows everything, leaving no rows`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let store = try makeStore(container)
        store.setCategoryHidden(true, name: "Kids", kind: .live)
        store.moveCategory("Music", by: -1, among: provider, kind: .live)

        store.resetCategories(kind: .live)

        #expect(store.arranged(provider, kind: .live) == provider)
        #expect(store.hiddenCategories(of: .live).isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<CategoryPreference>()) == 0)
    }

    @Test
    func `showing a category that was only hidden leaves no row behind`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let store = try makeStore(container)

        store.setCategoryHidden(true, name: "Kids", kind: .live)
        store.setCategoryHidden(false, name: "Kids", kind: .live)

        #expect(try ModelContext(container).fetchCount(FetchDescriptor<CategoryPreference>()) == 0)
    }
}
