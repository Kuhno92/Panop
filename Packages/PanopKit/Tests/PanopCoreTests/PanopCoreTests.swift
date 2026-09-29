@testable import PanopCore
import Testing

@Suite("PlaylistEntry")
struct PlaylistEntryTests {
    @Test
    func `epg match key prefers tvg-id`() {
        let entry = PlaylistEntry(
            name: "Display",
            url: "http://e/1.ts",
            attributes: ChannelAttributes(tvgID: "ard.de", tvgName: "ARD")
        )
        #expect(entry.epgMatchKey == "ard.de")
    }

    @Test
    func `epg match key falls back to tvg-name then display name`() {
        let withName = PlaylistEntry(
            name: "Display",
            url: "http://e/1.ts",
            attributes: ChannelAttributes(tvgName: "ARD")
        )
        #expect(withName.epgMatchKey == "ARD")

        let bare = PlaylistEntry(name: "Display", url: "http://e/1.ts")
        #expect(bare.epgMatchKey == "Display")
    }

    /// Providers emit tvg-id="" constantly, and treating that as a real id
    /// collapses every such channel onto one EPG entry.
    @Test
    func `an empty tvg-id is ignored rather than used as a key`() {
        let entry = PlaylistEntry(
            name: "Display",
            url: "http://e/1.ts",
            attributes: ChannelAttributes(tvgID: "", tvgName: "ARD")
        )
        #expect(entry.epgMatchKey == "ARD")
    }
}

@Suite("ChannelAttributes")
struct ChannelAttributesTests {
    @Test
    func `isEmpty reflects whether anything was set`() {
        #expect(ChannelAttributes().isEmpty)
        #expect(!ChannelAttributes(tvgID: "a").isEmpty)
        #expect(!ChannelAttributes(groupTitle: "News").isEmpty)
    }
}

@Suite("ProviderCredentials")
struct ProviderCredentialsTests {
    /// Credentials reach logs and diagnostic exports by accident. The redaction
    /// is the only thing standing between a support bundle and a leaked account.
    @Test
    func `description redacts the username and password`() {
        let credentials = ProviderCredentials(
            baseURL: "http://provider.example:8080",
            username: "alice",
            password: "hunter2"
        )
        let text = credentials.description
        #expect(!text.contains("alice"))
        #expect(!text.contains("hunter2"))
        #expect(text.contains("provider.example"))
    }
}
