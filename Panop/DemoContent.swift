#if DEBUG
    import Foundation
    import ImageIO
    import PanopCatalog
    import PanopCore
    import PanopEPG
    import SwiftData
    import SwiftUI
    #if os(macOS)
        import AppKit
    #endif

    /// Made-up channels with generated logos, and real films whose posters may be shown freely, for the marketing
    /// screenshots
    /// of the App Store
    /// (`PANOP_DEMO=1` with `-panop-uitest`, see `Scripts/make-store-screenshots.sh`). Nothing here is a real title or
    /// logo,
    /// so the screenshots show no one else's work. Debug builds only.
    enum DemoContent {
        static let isActive = UITestMode.isActive && ProcessInfo.processInfo.environment["PANOP_DEMO"] == "1"

        struct Film {
            var name: String
            /// The file in `docs/store-art` with its poster.
            var slug: String
            var year: Int
            var rating: Double
            var genre: String
            var plot: String
        }

        static let channels: [(name: String, group: String)] = [
            ("Panop News", "News"), ("Harbor Sports", "Sports"), ("Nova Cinema", "Movies"), ("Kids Planet", "Family"),
            ("Wild Earth", "Documentary"), ("Pulse Music", "Music"), ("Daily Docs", "Documentary"),
            ("Skyline Weather", "News"), ("Retro Classics", "Movies"), ("Kitchen TV", "Lifestyle"),
            ("Summit Outdoors", "Sports"), ("Studio One", "Entertainment"), ("Metro Traffic", "News"),
            ("Starlight Series", "Entertainment")
        ]

        /// Real films whose posters may be shown freely (see `docs/store-art/CREDITS.md`): Blender Foundation films
        /// under
        /// Creative Commons Attribution, and silent classics in the public domain. The ratings are only round numbers.
        static let films = [
            Film(
                name: "Sintel",
                slug: "sintel",
                year: 2010,
                rating: 7.4,
                genre: "Fantasy",
                plot: "A girl searches for her lost dragon."
            ),
            Film(
                name: "Tears of Steel",
                slug: "tears-of-steel",
                year: 2012,
                rating: 6.5,
                genre: "Science Fiction",
                plot: "Fighters defend Amsterdam from robots."
            ),
            Film(
                name: "Big Buck Bunny",
                slug: "big-buck-bunny",
                year: 2008,
                rating: 6.6,
                genre: "Animation",
                plot: "A giant rabbit has had enough of three rodents."
            ),
            Film(
                name: "Elephants Dream",
                slug: "elephants-dream",
                year: 2006,
                rating: 6.1,
                genre: "Animation",
                plot: "Two men explore a strange machine world."
            ),
            Film(
                name: "Cosmos Laundromat",
                slug: "cosmos-laundromat",
                year: 2015,
                rating: 7.3,
                genre: "Animation",
                plot: "A sheep is offered many lives."
            ),
            Film(
                name: "Spring",
                slug: "spring",
                year: 2019,
                rating: 7.2,
                genre: "Fantasy",
                plot: "A shepherd girl and a spirit of the forest."
            ),
            Film(
                name: "Metropolis",
                slug: "metropolis",
                year: 1927,
                rating: 8.3,
                genre: "Science Fiction",
                plot: "A city of workers lives below the rich."
            ),
            Film(
                name: "Night of the Living Dead",
                slug: "night-of-the-living-dead",
                year: 1968,
                rating: 7.8,
                genre: "Horror",
                plot: "Strangers hold out in a farmhouse."
            ),
            Film(
                name: "The Cabinet of Dr. Caligari",
                slug: "cabinet-of-dr-caligari",
                year: 1920,
                rating: 8.0,
                genre: "Horror",
                plot: "A showman and his sleepwalker."
            ),
            Film(
                name: "The General",
                slug: "the-general",
                year: 1926,
                rating: 8.1,
                genre: "Comedy",
                plot: "A railwayman chases his stolen engine."
            ),
            Film(
                name: "A Trip to the Moon",
                slug: "a-trip-to-the-moon",
                year: 1902,
                rating: 8.0,
                genre: "Fantasy",
                plot: "Astronomers fire a capsule at the moon."
            )
        ]

        /// The address of a generated picture, which the image pipeline draws itself (see `DemoArt`).
        static func art(_ kind: String, _ name: String) -> String {
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return "https://\(DemoArt.host)/\(kind)/\(encoded)"
        }

        /// The films for the hero, as the list rows Home and Movies make theirs from.
        static var heroRows: [CatalogRow] {
            films.prefix(3).enumerated().map { index, film in
                CatalogRow(CatalogEntryRecord(playlist: "demo", entry: CatalogEntry(
                    id: "demohero\(index)",
                    kind: .movie,
                    name: film.name,
                    iconURL: art("poster", film.slug),
                    streamURL: "http://127.0.0.1:9/movie/u/p/hero\(index).mp4",
                    rating: film.rating,
                    plot: film.plot,
                    year: film.year,
                    genre: film.genre
                )))
            }
        }

        @MainActor
        static func seed(_ services: AppServices) async {
            var lines = channels.enumerated().map { index, channel in
                "#EXTINF:-1 tvg-id=\"d\(index)\" tvg-logo=\"\(art("logo", channel.name))\" "
                    + "group-title=\"\(channel.group)\",\(channel.name)\nhttp://127.0.0.1:9/live/\(index).ts"
            }
            lines += films.enumerated().map { index, film in
                "#EXTINF:5400 tvg-logo=\"\(art("poster", film.slug))\" "
                    + "group-title=\"\(index < 6 ? "Open movies" : "Silent classics")\",\(film.name)\nhttp://127.0.0.1:9/movie/u/p/\(index).mp4"
            }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString).m3u")
            do {
                try ("#EXTM3U\n" + lines.joined(separator: "\n") + "\n").write(
                    to: file,
                    atomically: true,
                    encoding: .utf8
                )
                let playlist = try await services.library.add(
                    .m3uFile(name: "My IPTV", fileURL: file),
                    includeVOD: true
                )
                _ = try await services.catalogStore.upsertProgrammes(programmes(), playlist: playlist.id)
                // The import runs on after `add` returns: wait for the rows before writing what the file lacks.
                let expected = channels.count + films.count
                for _ in 0 ..< 100 where count(services.catalogContainer, playlist: playlist.id) < expected {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                decorate(services.catalogContainer, playlist: playlist.id)
                // The lists read the catalog before the ratings were written, and re-read it when what is hidden
                // changes.
                services.userState.setHidden(true, for: "demo|refresh")
                try? await Task.sleep(for: .milliseconds(400))
                services.userState.setHidden(false, for: "demo|refresh")
                func key(_ url: String) -> String {
                    UserStateStore.key(playlist: playlist.id, entry: CatalogID.m3u(url: url))
                }
                for index in [0, 2, 4] {
                    services.userState.toggleFavorite(key("http://127.0.0.1:9/live/\(index).ts"))
                }
                // Recently watched channels, and films left part-way: what Home shows once it has been used.
                for index in [5, 1, 3, 0] {
                    services.userState.markPlayed(key("http://127.0.0.1:9/live/\(index).ts"))
                }
                for (index, position) in [(0, 2900.0), (1, 1500.0), (3, 3900.0)] {
                    let film = key("http://127.0.0.1:9/movie/u/p/\(index).mp4")
                    services.userState.markPlayed(film)
                    services.userState.saveProgress(film, position: position, duration: 5400)
                }
            } catch {
                assertionFailure("demo seed failed: \(error)")
            }
            #if os(macOS)
                // The Mac's screenshots are of a window of exactly 1280 x 800 points, which a Retina display captures
                // as 2560 x 1600 pixels, a size the store takes.
                try? await Task.sleep(for: .seconds(1))
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.isVisible })?.setFrame(
                    NSRect(x: 80, y: 60, width: 1280, height: 800),
                    display: true
                )
            #endif
        }

        /// What is on now and next, for every channel.
        private static func programmes() -> [EPGProgramme] {
            let now = Date.now
            let shows: [[(String, [String])]] = [
                [("Morning Report", ["News"]), ("Business Today", ["News"]), ("City Desk", ["News"])],
                [("Coastal Cup: Final", ["Sport"]), ("Post Match", ["Sport"]), ("Marathon Highlights", ["Sport"])],
                [("Sintel", ["Movie"]), ("Tears of Steel", ["Movie"]), ("Spring", ["Movie"])],
                [("Bubble Island", ["Kids"]), ("Robo Garden", ["Kids"]), ("Story Time", ["Kids"])],
                [
                    ("Rivers of the North", ["Documentary"]),
                    ("Deep Blue", ["Documentary"]),
                    ("Night Safari", ["Documentary"])
                ],
                [("Live Sessions", ["Music"]), ("Top 20", ["Music"]), ("Unplugged", ["Music"])],
                [
                    ("The Salt Trade", ["Documentary"]),
                    ("Lost Railways", ["Documentary"]),
                    ("Modern Builders", ["Documentary"])
                ],
                [("Weather Now", ["News"]), ("Outlook", ["News"]), ("Climate Watch", ["News"])],
                [("Metropolis", ["Movie"]), ("The General", ["Movie"]), ("A Trip to the Moon", ["Movie"])],
                [("Quick Suppers", ["Lifestyle"]), ("Bake Off Weekend", ["Lifestyle"]), ("Market Tour", ["Lifestyle"])],
                [("Peak to Peak", ["Sport"]), ("Trail Notes", ["Sport"]), ("Climbing Stories", ["Sport"])],
                [("The Late Show", ["Talk"]), ("Quiz Night", ["Quiz"]), ("Comedy Hour", ["Comedy"])],
                [("Traffic Update", ["News"]), ("Commute Live", ["News"]), ("Road Safety", ["News"])],
                [("Harbor Lights", ["Series"]), ("Deep Field", ["Series"]), ("Orbit Seven", ["Series"])]
            ]
            var result: [EPGProgramme] = []
            for (index, list) in shows.enumerated() {
                let offsets: [(Double, Double)] = [
                    (-25 - Double(index * 3), 35 + Double(index)),
                    (35 + Double(index), 95 + Double(index)),
                    (95 + Double(index), 160)
                ]
                for (slot, entry) in list.enumerated() {
                    result.append(EPGProgramme(
                        channelID: "d\(index)",
                        start: now.addingTimeInterval(offsets[slot].0 * 60),
                        stop: now.addingTimeInterval(offsets[slot].1 * 60),
                        title: entry.0,
                        categories: entry.1
                    ))
                }
            }
            return result
        }

        @MainActor
        private static func count(_ container: ModelContainer, playlist: String) -> Int {
            (try? ModelContext(container).fetchCount(
                FetchDescriptor<CatalogEntryRecord>(predicate: #Predicate { $0.playlist == playlist })
            )) ?? 0
        }

        /// Ratings, years, genres and plots for what the playlist file has none of.
        @MainActor
        private static func decorate(_ container: ModelContainer, playlist: String) {
            let context = ModelContext(container)
            let all = (try? context
                .fetch(FetchDescriptor<CatalogEntryRecord>(predicate: #Predicate { $0.playlist == playlist }))) ?? []
            let byName = Dictionary(films.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            for record in all {
                guard let film = byName[record.name] else { continue }
                record.rating = film.rating
                record.year = film.year
                record.genre = film.genre
                record.plot = film.plot
            }
            try? context.save()
        }
    }

    /// Draws the pictures `DemoContent` points at, in place of a download.
    enum DemoArt {
        nonisolated static let host = "demo.panop.invalid"

        /// The poster of a real film, from the folder `PANOP_DEMO_ART_DIR` names (`docs/store-art`).
        private static func realPoster(slug: String) -> CGImage? {
            guard let directory = ProcessInfo.processInfo.environment["PANOP_DEMO_ART_DIR"] else { return nil }
            let file = URL(fileURLWithPath: directory).appendingPathComponent(slug + ".jpg")
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        @MainActor
        static func render(_ url: URL) -> CGImage? {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2 else { return nil }
            let name = parts[1]
            if parts[0] == "poster", let real = realPoster(slug: name) {
                return real
            }
            let seed = Double(abs(name.hashValue % 360)) / 360
            let size = switch parts[0] {
            case "poster": CGSize(width: 600, height: 900)
            case "logo": CGSize(width: 256, height: 256)
            default: CGSize(width: 1280, height: 720)
            }
            let hue = (seed * 360).truncatingRemainder(dividingBy: 360) / 360
            let top = Color(hue: hue, saturation: 0.65, brightness: 0.85)
            let bottom = Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.25)
            let view = ZStack {
                LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.14)).frame(width: size.width * 0.9).offset(
                    x: size.width * 0.25,
                    y: -size.height * 0.2
                )
                Circle().fill(.black.opacity(0.14)).frame(width: size.width * 0.7).offset(
                    x: -size.width * 0.3,
                    y: size.height * 0.3
                )
                if parts[0] == "logo" {
                    Text(String(name.prefix(2)).uppercased())
                        .font(.system(size: size.width * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    VStack {
                        Spacer()
                        Text(name)
                            .font(.system(
                                size: size.height * (parts[0] == "poster" ? 0.085 : 0.12),
                                weight: .heavy,
                                design: .serif
                            ))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(radius: 8)
                            .padding(size.width * 0.08)
                            .padding(.bottom, size.height * 0.05)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return renderer.cgImage
        }
    }
#endif
