import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

@Suite("Film page")
struct MovieDetailTests {
    @Test
    func `the line under the title lists what is known, in order, and skips the rest`() {
        let full = MovieMeta.line(year: 1979, genre: "Horror, Sci-Fi, Thriller", durationSeconds: 7020, rating: 8.5)
        #expect(full == "1979 · Horror, Sci-Fi · 1 h 57 min · ★ 8.5")

        #expect(MovieMeta.line(year: nil, genre: nil, durationSeconds: nil, rating: nil).isEmpty)
        #expect(MovieMeta.line(year: 2021, genre: nil, durationSeconds: nil, rating: 0) == "2021")
        #expect(MovieMeta.line(year: nil, genre: " , ", durationSeconds: 30, rating: nil).isEmpty)
    }

    @Test(arguments: [(3000, "50 min"), (5400, "1 h 30 min"), (3629, "1 h 0 min"), (89, "1 min")])
    func `lengths read as hours and minutes`(seconds: Int, text: String) {
        #expect(MovieMeta.length(seconds) == text)
    }

    @Test
    @MainActor
    func `a reference carries what is needed to play, and nothing live`() throws {
        let context = try ModelContext(PanopContainers.makeCatalog(inMemory: true))
        let record = CatalogEntryRecord(playlist: "p", entry: CatalogEntry(
            id: "movie:7",
            kind: .movie,
            name: "Alien",
            groupName: "Horror",
            iconURL: "http://i/a.jpg",
            streamURL: "http://h/movie/u/p/7.mkv",
            remoteID: "7",
            containerExtension: "mkv",
            rating: 8.4,
            plot: "In space."
        ))
        context.insert(record)

        let movie = MovieReference(record)

        #expect(movie.id == "p|movie:7")
        #expect(movie.target.kind == .movie)
        #expect(movie.target.streamURL == "http://h/movie/u/p/7.mkv")
        #expect(movie.target.remoteID == "7")
        #expect(movie.rating == 8.4)
        #expect(movie.plot == "In space.")
    }
}
