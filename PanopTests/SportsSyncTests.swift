import Foundation
@testable import Panop
import SwiftData
import Testing

@Suite("Sports key, the decision")
struct SportsKeySyncDecisionTests {
    private let key = "sk_live_1234567890"
    private let other = "sk_live_other"

    private var blob: Data {
        SportsKeySync.encode(key) ?? Data()
    }

    private var otherBlob: Data {
        SportsKeySync.encode(other) ?? Data()
    }

    private func decide(
        local: String?, blob: Data?, removed: Bool = false, remembered: String? = nil, uploading: Bool = true
    ) -> SportsKeySync.Action {
        SportsKeySync.decide(local: local, blob: blob, removed: removed, remembered: remembered, uploading: uploading)
    }

    @Test
    func `a key this device has and the record lacks is sent`() {
        #expect(decide(local: key, blob: nil) == .upload(blob))
    }

    @Test
    func `a key that arrived on a device with none is taken`() {
        #expect(decide(local: nil, blob: blob) == .adopt(key))
    }

    @Test
    func `the same key on both is left alone, and nothing anywhere is nothing to do`() {
        #expect(decide(local: key, blob: blob) == .none)
        #expect(decide(local: nil, blob: nil) == .none)
    }

    @Test
    func `a blank key is no key`() {
        #expect(SportsKeySync.encode("   \n") == nil)
        #expect(decide(local: "  ", blob: nil) == .none)
        #expect(SportsKeySync.encode(" \(key)\n") == blob)
    }

    @Test
    func `a key changed here, the record still being what this device put there, is sent`() {
        let remembered = SportsKeySync.digest(otherBlob)
        #expect(decide(local: key, blob: otherBlob, remembered: remembered) == .upload(blob))
    }

    @Test
    func `a key changed on another device since stands`() {
        let remembered = SportsKeySync.digest(blob)
        #expect(decide(local: key, blob: otherBlob, remembered: remembered) == .adopt(other))
        // A device that never took part in the sync takes the record's key too.
        #expect(decide(local: key, blob: otherBlob, remembered: nil) == .adopt(other))
    }

    @Test
    func `a key taken out on another device is taken out here`() {
        let remembered = SportsKeySync.digest(blob)
        #expect(decide(local: key, blob: nil, removed: true, remembered: remembered) == .removeLocal)
    }

    @Test
    func `a key typed in here after one was taken out elsewhere is a new key, and is sent`() {
        #expect(decide(local: key, blob: nil, removed: true, remembered: nil) == .upload(blob))
        #expect(decide(local: key, blob: nil, removed: true, remembered: SportsKeySync.digest(otherBlob)) ==
            .upload(blob))
    }

    @Test
    func `with the sync off the record is emptied, and nothing else happens`() {
        #expect(decide(local: key, blob: blob, uploading: false) == .withdraw)
        #expect(decide(local: key, blob: nil, uploading: false) == .none)
        #expect(decide(local: nil, blob: blob, uploading: false) == .withdraw)
    }

    @Test
    func `the digest says nothing of the key`() {
        let digest = SportsKeySync.digest(blob)
        #expect(!digest.contains(key) && digest.count == 64)
    }
}

@MainActor
@Suite("Sports choices, kept for every device")
struct SportsSyncStoreTests {
    private func store() throws -> (SportsSyncStore, ModelContext) {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let context = ModelContext(container)
        return (SportsSyncStore(context: context), context)
    }

    private let premier = SportsLeagueChoice(id: 9, name: "Premier League", country: "England")
    private let bundesliga = SportsLeagueChoice(id: 54, name: "Bundesliga", country: "Germany")

    @Test
    func `leagues are chosen, unchosen and kept in the order they were chosen`() throws {
        let (store, _) = try store()
        store.setLeague(bundesliga, chosen: true, profile: "")
        store.setLeague(premier, chosen: true, profile: "")
        #expect(store.leagues(profile: "") == [bundesliga, premier])
        store.setLeague(bundesliga, chosen: false, profile: "")
        #expect(store.leagues(profile: "") == [premier])
    }

    @Test
    func `choosing a league twice is one choice`() throws {
        let (store, _) = try store()
        store.setLeague(premier, chosen: true, profile: "")
        store.setLeague(premier, chosen: true, profile: "")
        #expect(store.leagues(profile: "").count == 1)
    }

    @Test
    func `each person has their own choices`() throws {
        let (store, _) = try store()
        store.setLeague(premier, chosen: true, profile: "")
        store.setLeague(bundesliga, chosen: true, profile: "anna")
        #expect(store.leagues(profile: "") == [premier])
        #expect(store.leagues(profile: "anna") == [bundesliga])
        store.setSetupDone(true, profile: "anna")
        #expect(store.isSetupDone(profile: "anna") && !store.isSetupDone(profile: ""))
        store.forget(profile: "anna")
        #expect(store.leagues(profile: "anna").isEmpty && !store.isSetupDone(profile: "anna"))
        #expect(store.leagues(profile: "") == [premier])
    }

    @Test
    func `a favourite team keeps its name, short name, logo and league`() throws {
        let (store, _) = try store()
        let team = SportsTeamChoice(id: 17, name: "Bayern Munich", short: "Bayern", logo: "espn-132.png", leagueID: 54)
        store.setTeam(team, chosen: true, profile: "")
        #expect(store.teams(profile: "") == [team])
        #expect(store.isFollowing(team: 17, profile: ""))
        let bare = SportsTeamChoice(id: 18, name: "Alder Town", short: "Alder Town", logo: nil, leagueID: nil)
        store.setTeam(bare, chosen: true, profile: "")
        #expect(store.teams(profile: "").last == bare)
        store.setTeam(team, chosen: false, profile: "")
        #expect(!store.isFollowing(team: 17, profile: ""))
    }

    @Test
    func `the same choice written on two devices is read as one, the newest`() throws {
        let (store, context) = try store()
        let older = SportsPreference(
            profile: "", kind: "league", key: "9", value: "Old name\u{1F}England", at: Date(timeIntervalSince1970: 100)
        )
        let newer = SportsPreference(
            profile: "", kind: "league", key: "9", value: "Premier League\u{1F}England",
            at: Date(timeIntervalSince1970: 200)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()
        #expect(store.leagues(profile: "") == [premier])
        // And the extra row is gone, so it is not read again.
        #expect(try context.fetchCount(FetchDescriptor<SportsPreference>()) == 1)
    }

    @Test
    func `the tab is shown unless the person hid it`() throws {
        let (store, _) = try store()
        #expect(store.showsTab())
        store.setShowsTab(false)
        #expect(!store.showsTab())
        store.setShowsTab(true)
        #expect(store.showsTab())
    }

    @Test
    func `a channel chosen for a league is remembered, and counted`() throws {
        let (store, _) = try store()
        store.rememberChannel("sky", league: 54, profile: "")
        store.rememberChannel("sky", league: 54, profile: "")
        store.rememberChannel("dazn", league: 54, profile: "")
        store.rememberChannel("sky", league: 9, profile: "")
        #expect(store.channelChoices(league: 54, profile: "") == ["sky": 2, "dazn": 1])
        #expect(store.channelChoices(league: 9, profile: "") == ["sky": 1])
        store.forgetChannelChoices(profile: "")
        #expect(store.channelChoices(league: 54, profile: "").isEmpty)
    }

    @Test
    func `resetting starts the setup again and leaves the key`() throws {
        let (store, _) = try store()
        store.setLeague(premier, chosen: true, profile: "")
        store.setSetupDone(true, profile: "")
        store.setKeyBlob(Data("k".utf8))
        store.resetSelections(profile: "")
        #expect(store.leagues(profile: "").isEmpty && !store.isSetupDone(profile: ""))
        #expect(store.keyRecord.blob == Data("k".utf8))
    }

    @Test
    func `the key on the record, and the mark that it was taken out`() throws {
        let (store, _) = try store()
        #expect(store.keyRecord.blob == nil && !store.keyRecord.removed)
        store.setKeyBlob(Data("key".utf8))
        #expect(store.keyRecord.blob == Data("key".utf8))
        store.setKeyBlob(nil, removed: true)
        #expect(store.keyRecord.blob == nil && store.keyRecord.removed)
        store.setKeyBlob(Data("new".utf8))
        #expect(store.keyRecord.blob == Data("new".utf8) && !store.keyRecord.removed)
    }

    @Test
    func `two key records, written by two devices, become the newest one`() throws {
        let (store, context) = try store()
        context.insert(SportsKeyRecord(encryptedKey: Data("old".utf8), at: Date(timeIntervalSince1970: 1)))
        context.insert(SportsKeyRecord(encryptedKey: Data("new".utf8), at: Date(timeIntervalSince1970: 2)))
        try context.save()
        #expect(store.keyRecord.blob == Data("new".utf8))
        #expect(try context.fetchCount(FetchDescriptor<SportsKeyRecord>()) == 1)
    }

    @Test
    func `screens are told when something changed`() throws {
        let (store, _) = try store()
        let before = store.revision
        store.setLeague(premier, chosen: true, profile: "")
        #expect(store.revision > before)
        let afterWrite = store.revision
        store.reloadAfterRemoteChange()
        #expect(store.revision > afterWrite)
    }
}
