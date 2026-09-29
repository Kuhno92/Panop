import Foundation
@testable import PanopCatalog
import PanopCore
import PanopEPG
import Testing

@Suite("Catalog identity")
struct CatalogIDTests {
    /// Ids are persisted, so the hash must never change between launches or
    /// releases. These are the published FNV-1a 64 test vectors.
    @Test
    func `the hash is stable FNV-1a`() {
        #expect(CatalogID.hash64("") == 0xCBF2_9CE4_8422_2325)
        #expect(CatalogID.hash64("a") == 0xAF63_DC4C_8601_EC8C)
        #expect(CatalogID.hash64("foobar") == 0x8594_4171_F739_67E8)
    }

    @Test
    func `identity for M3U depends on the URL alone`() {
        let url = "http://host/live/u/p/1.ts"
        #expect(CatalogID.m3u(url: url) == CatalogID.m3u(url: url))
        #expect(CatalogID.m3u(url: url) != CatalogID.m3u(url: "http://host/live/u/p/2.ts"))
        #expect(CatalogID.m3u(url: url).hasPrefix("m3u:"))
        #expect(CatalogID.m3u(url: url).count == 4 + 16)
    }

    @Test
    func `hex is zero padded`() {
        #expect(CatalogID.hex(1) == "0000000000000001")
        #expect(CatalogID.hex(UInt64.max) == "ffffffffffffffff")
    }

    @Test
    func `a programme key ignores channel case`() {
        let start = Date(timeIntervalSince1970: 1000)
        let upper = EPGProgramme(channelID: "ARD.de", start: start, stop: start, title: "x")
        let lower = EPGProgramme(channelID: " ard.de ", start: start, stop: start, title: "x")
        #expect(ProgrammeKey(upper) == ProgrammeKey(lower))
        #expect(ProgrammeKey(upper).hash64 == ProgrammeKey(lower).hash64)
    }

    @Test
    func `programme keys order by channel then time`() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)
        let keys = [
            ProgrammeKey(channelKey: "b", start: early),
            ProgrammeKey(channelKey: "a", start: late),
            ProgrammeKey(channelKey: "a", start: early)
        ]
        #expect(keys.sorted() == [
            ProgrammeKey(channelKey: "a", start: early),
            ProgrammeKey(channelKey: "a", start: late),
            ProgrammeKey(channelKey: "b", start: early)
        ])
    }

    @Test
    func `different times give different hashes`() {
        let first = ProgrammeKey(channelKey: "x", start: Date(timeIntervalSince1970: 1000))
        let second = ProgrammeKey(channelKey: "x", start: Date(timeIntervalSince1970: 1001))
        #expect(first.hash64 != second.hash64)
    }

    // MARK: - Prune policy

    @Test
    func `the policy allows small removals and large ones only when proportionate`() {
        let policy = PrunePolicy(maxRemovedFraction: 0.5, alwaysAllowUpTo: 25)
        #expect(policy.allows(removing: 25, of: 25))
        #expect(policy.allows(removing: 0, of: 0))
        #expect(policy.allows(removing: 400, of: 1000))
        #expect(policy.allows(removing: 500, of: 1000))
        #expect(!policy.allows(removing: 501, of: 1000))
        #expect(!policy.allows(removing: 26, of: 26))
    }
}
