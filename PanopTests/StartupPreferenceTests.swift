import Foundation
@testable import Panop
import PanopCatalog
import SwiftData
import Testing

@Suite("Startup preference")
struct StartupPreferenceTests {
    @Test(arguments: [
        (StartupAction.home, AppTab.home),
        (.live, .live),
        (.movies, .movies),
        (.series, .series)
    ])
    func `a screen is opened as chosen`(action: StartupAction, tab: AppTab) {
        let plan = StartupPreference.plan(action: action, channel: "", offersVOD: true)

        #expect(plan == StartupPreference.Plan(tab: tab, channel: nil))
    }

    @Test(arguments: [StartupAction.movies, .series])
    func `a screen that is not offered opens Home instead`(action: StartupAction) {
        let plan = StartupPreference.plan(action: action, channel: "", offersVOD: false)

        #expect(plan.tab == .home)
    }

    @Test
    func `a chosen channel opens Live TV and is started`() {
        let plan = StartupPreference.plan(action: .channel, channel: "p|c1", offersVOD: true)

        #expect(plan == StartupPreference.Plan(tab: .live, channel: "p|c1"))
    }

    @Test
    func `play a channel with none chosen is just Live TV`() {
        let plan = StartupPreference.plan(action: .channel, channel: "", offersVOD: true)

        #expect(plan == StartupPreference.Plan(tab: .live, channel: nil))
    }

    @Test
    func `stored settings are read, and nothing stored means Home`() throws {
        let suite = "startup-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(StartupPreference.current(offersVOD: true, defaults: defaults).tab == .home)

        defaults.set("channel", forKey: StartupPreference.actionKey)
        defaults.set("p|c1", forKey: StartupPreference.channelKey)

        #expect(StartupPreference.current(offersVOD: true, defaults: defaults).channel == "p|c1")
    }

    @Test
    func `a stored value this version does not know is Home`() throws {
        let suite = "startup-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("somethingNew", forKey: StartupPreference.actionKey)

        #expect(StartupPreference.current(offersVOD: true, defaults: defaults).tab == .home)
    }

    @Test
    @MainActor
    func `the chosen channel is found by playlist and id, and a missing one is nil`() throws {
        let context = try ModelContext(PanopContainers.makeCatalog(inMemory: true))
        context.insert(CatalogEntryRecord(playlist: "a", entry: CatalogEntry(id: "c1", kind: .live, name: "From A")))
        context.insert(CatalogEntryRecord(playlist: "b", entry: CatalogEntry(id: "c1", kind: .live, name: "From B")))
        try context.save()

        #expect(StartupPreference.channel(for: "b|c1", in: context)?.name == "From B")
        #expect(StartupPreference.channel(for: "a|c1", in: context)?.name == "From A")
        #expect(StartupPreference.channel(for: "c|c1", in: context) == nil, "right id, other playlist")
        #expect(StartupPreference.channel(for: "a|gone", in: context) == nil)
    }
}
