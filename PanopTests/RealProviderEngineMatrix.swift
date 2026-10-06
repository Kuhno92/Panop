#if os(macOS)
    import AetherEngine
    import Foundation
    @testable import Panop
    import PanopCore
    import PanopPlayback
    import Testing

    /// Which engine plays which kind of stream, tried on a real provider's streams.
    ///
    /// Off unless both `PANOP_DEV_XTREAM=url|username|password` and `PANOP_ENGINE_MATRIX=1` are set. The login is read
    /// from the environment only and never written down: the results file names streams by kind and number, not
    /// address.
    /// Each stream is opened by each engine in turn, one at a time (a provider allows few connections), and counts as
    /// played only if the engine says it is playing and its position then moves.
    ///
    ///     TEST_RUNNER_PANOP_DEV_XTREAM='http://host:9191|user|pass' TEST_RUNNER_PANOP_ENGINE_MATRIX=1 \
    ///       PANOP_ONLY=RealProviderEngineMatrix Scripts/test-app.sh macos
    ///
    /// Results are appended to `/tmp/panop-engine-matrix.txt`, one line per attempt.
    @Suite(
        "Real provider engine matrix",
        .enabled(if: ProcessInfo.processInfo.environment["PANOP_DEV_XTREAM"] != nil
            && ProcessInfo.processInfo.environment["PANOP_ENGINE_MATRIX"] != nil),
        .serialized,
        .engineGate
    )
    @MainActor
    struct RealProviderEngineMatrix {
        private struct Login {
            var base: String
            var user: String
            var password: String
        }

        private struct Stream {
            var label: String
            var url: String
            var kind: MediaKind
            /// The engines to try it with: all of them, or one where each needs a channel of its own.
            var engines: [PlaybackEngineKind]?
        }

        private func login() throws -> Login {
            let parts = (ProcessInfo.processInfo.environment["PANOP_DEV_XTREAM"] ?? "").split(separator: "|")
                .map(String.init)
            try #require(parts.count == 3)
            return Login(base: parts[0], user: parts[1], password: parts[2])
        }

        private func api(_ login: Login, _ action: String, _ extra: String = "") async throws -> Any {
            let address = "\(login.base)/player_api.php?username=\(login.user)&password=\(login.password)&action=\(action)\(extra)"
            let (data, _) = try await URLSession.shared.data(from: URL(string: address)!)
            return try JSONSerialization.jsonObject(with: data)
        }

        /// `count` entries spread evenly over the list, so a sample is not one category.
        private func spread<T>(_ items: [T], _ count: Int) -> [T] {
            guard items.count > count, count > 0 else { return items }
            return (0 ..< count).map { items[$0 * items.count / count] }
        }

        private func record(_ line: String) {
            let url = URL(fileURLWithPath: "/tmp/panop-engine-matrix.txt")
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }

        /// Whether the address answers with media within a few seconds. A provider lists many channels that are down
        /// and
        /// refuses a second connection, so streams are checked one at a time before the engines are asked to play them.
        private func answers(_ address: String, ranged: Bool, transportStream: Bool = false) async -> Bool {
            guard let url = URL(string: address) else { return false }
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("VLC/3.0", forHTTPHeaderField: "User-Agent")
            if ranged {
                request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
            }
            defer { Task { try? await Task.sleep(for: .seconds(1.5)) } }
            guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode,
                  status == 200 || status == 206 else { return false }
            var first: UInt8?
            do {
                for try await byte in bytes {
                    first = byte
                    break
                }
            } catch {
                return false
            }
            try? await Task.sleep(for: .seconds(1.5))
            return transportStream ? first == 0x47 : first != nil
        }

        private func streams(_ login: Login) async throws -> [Stream] {
            var result: [Stream] = []
            let live = try await (api(login, "get_live_streams") as? [[String: Any]]) ?? []
            let liveIDs = live.compactMap { ($0["stream_id"] as? Int) ?? Int("\($0["stream_id"] ?? "")") }
            var working: [Int] = []
            for id in spread(liveIDs, 90) where working.count < 16 {
                if await answers(
                    "\(login.base)/live/\(login.user)/\(login.password)/\(id).ts",
                    ranged: false,
                    transportStream: true
                ) {
                    working.append(id)
                }
            }
            record("live channels that answer: \(working.count)")
            // A provider restarts a channel after a client leaves it, and a channel just left fails for a while. So
            // each attempt gets a channel of its own: the engines take turns over the channels, and every channel
            // here carries the same kind of stream (H.264 and AAC in MPEG-TS).
            let order: [PlaybackEngineKind] = [.avPlayer, .lumeEngine, .aetherEngine, .vlcKit, .ksPlayer]
            for (index, id) in working.enumerated() {
                let address = "\(login.base)/live/\(login.user)/\(login.password)/\(id)"
                let engine = order[index % order.count]
                let isTransportStream = index < 12
                result.append(Stream(
                    label: isTransportStream ? "live-ts" : "live-hls-address",
                    url: address + (isTransportStream ? ".ts" : ".m3u8"),
                    kind: .live,
                    engines: [engine]
                ))
            }
            let vod = try await (api(login, "get_vod_streams") as? [[String: Any]]) ?? []
            func films(_ ext: String, _ count: Int) async -> [Stream] {
                let matching = vod.filter { ($0["container_extension"] as? String) == ext }
                let ids = matching.compactMap { ($0["stream_id"] as? Int) ?? Int("\($0["stream_id"] ?? "")") }
                var found: [Stream] = []
                for id in spread(ids, count * 3) where found.count < count {
                    let address = "\(login.base)/movie/\(login.user)/\(login.password)/\(id).\(ext)"
                    if await answers(address, ranged: true) {
                        found.append(Stream(label: "film-\(ext) #\(found.count + 1)", url: address, kind: .movie))
                    }
                }
                return found
            }
            result += await films("mkv", 6) + films("mp4", 4)
            let series = try await (api(login, "get_series") as? [[String: Any]]) ?? []
            let seriesIDs = series.compactMap { ($0["series_id"] as? Int) ?? Int("\($0["series_id"] ?? "")") }
            var episodes: [Stream] = []
            for id in spread(seriesIDs, 12) where episodes.count < 4 {
                guard let info = try await api(login, "get_series_info", "&series_id=\(id)") as? [String: Any],
                      let seasons = info["episodes"] as? [String: Any] else { continue }
                let first = seasons.values.compactMap { $0 as? [[String: Any]] }.flatMap(\.self).first
                if let first, let episodeID = first["id"], let ext = first["container_extension"] as? String {
                    let address = "\(login.base)/series/\(login.user)/\(login.password)/\(episodeID).\(ext)"
                    if await answers(address, ranged: true) {
                        episodes.append(Stream(
                            label: "episode-\(ext) #\(episodes.count + 1)",
                            url: address,
                            kind: .series
                        ))
                    }
                }
            }
            return result + episodes
        }

        // MARK: - One attempt

        private func make(_ kind: PlaybackEngineKind) -> (engine: any PlaybackEngine, window: SurfaceWindow?)? {
            switch kind {
            case .avPlayer:
                return (AVPlayerEngine(), nil)
            case .vlcKit:
                let engine = VLCEngine()
                return (engine, SurfaceWindow(engine.surface))
            case .lumeEngine:
                let engine = LumePlaybackEngine()
                return (engine, SurfaceWindow(engine.surface))
            case .aetherEngine:
                guard let engine = AetherPlaybackEngine() else { return nil }
                let view = AetherPlayerView()
                engine.player.bind(view: view)
                return (engine, SurfaceWindow(view))
            case .ksPlayer:
                let engine = KSPlayerEngine()
                return (engine, SurfaceWindow(engine.surface))
            }
        }

        /// What a load came to, filled in by the task that ran it so that the wait never blocks on it.
        private final class LoadBox {
            var result: Result<Void, Error>?
        }

        private func elapsed(_ since: ContinuousClock.Instant) -> String {
            let span = ContinuousClock.now - since
            return String(format: "%.1fs", Double(span.components.seconds) + Double(span.components.attoseconds) / 1e18)
        }

        private func attempt(_ kind: PlaybackEngineKind, _ stream: Stream) async -> String {
            guard let made = make(kind) else { return "not available" }
            let engine = made.engine
            var events: [PlaybackEvent] = []
            let collector = Task { for await event in engine.events {
                events.append(event)
            } }
            defer {
                collector.cancel()
                made.window?.close()
            }
            let began = ContinuousClock.now
            let item = PlaybackItem(
                url: stream.url,
                title: nil,
                headers: [:],
                userAgent: nil,
                startPosition: nil,
                mediaKind: stream.kind
            )
            let box = LoadBox()
            let loading = Task { @MainActor in
                do {
                    try await engine.load(item)
                    box.result = .success(())
                } catch {
                    box.result = .failure(error)
                }
            }
            let budget = stream.kind == .live ? 25.0 : 40.0
            let deadline = ContinuousClock.now + .seconds(budget)
            while box.result == nil, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            switch box.result {
            case .success:
                break
            case let .failure(error):
                let failure = error as? PlaybackError
                await engine.stop()
                return "load failed: \(failure?.code.rawValue ?? "error") \((failure?.message ?? "\(error)").prefix(70))"
            case nil:
                loading.cancel()
                await engine.stop()
                return "no answer in \(Int(budget)) s"
            }
            let loaded = elapsed(began)
            let outcome = await playing(engine, events: { events })
            await engine.stop()
            return outcome.replacingOccurrences(of: "{open}", with: loaded)
        }

        /// Plays, and waits for the position to move by a second, or for the engine to say it failed.
        private func playing(_ engine: any PlaybackEngine, events: () -> [PlaybackEvent]) async -> String {
            engine.play()
            let began = ContinuousClock.now
            var startPosition: Double?
            let deadline = ContinuousClock.now + .seconds(20)
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
                for event in events() {
                    if case let .failed(error) = event {
                        return "failed while playing: \(error.code.rawValue) \((error.message ?? "").prefix(60))"
                    }
                }
                guard engine.state == .playing else { continue }
                startPosition = startPosition ?? engine.position ?? 0
                if let position = engine.position, let start = startPosition, position - start >= 1.0 {
                    return "plays (open {open}, moving after \(elapsed(began)))"
                }
            }
            return "opened ({open}) but did not play: state \(engine.state.rawValue)"
        }

        @Test
        func `which engine plays which stream`() async throws {
            let login = try login()
            let all = try await streams(login)
            try? FileManager.default.removeItem(atPath: "/tmp/panop-engine-matrix.txt")
            record("streams: \(all.count)")
            // Narrowing, to look at one case closely: PANOP_MATRIX_ENGINES=VLC,LumeEngine and
            // PANOP_MATRIX_STREAMS=live-ts.
            let engineFilter = (ProcessInfo.processInfo.environment["PANOP_MATRIX_ENGINES"] ?? "").split(separator: ",")
                .map(String.init)
            let streamFilter = (ProcessInfo.processInfo.environment["PANOP_MATRIX_STREAMS"] ?? "").split(separator: ",")
                .map(String.init)
            for stream in all where streamFilter.isEmpty || streamFilter.contains(where: stream.label.hasPrefix) {
                let isLive = stream.kind == .live
                for kind in stream.engines ?? [
                    PlaybackEngineKind.avPlayer,
                    .lumeEngine,
                    .aetherEngine,
                    .vlcKit,
                    .ksPlayer
                ]
                    where engineFilter.isEmpty || engineFilter.contains(kind.displayName)
                {
                    // The provider allows one connection: wait until it will answer again, so a failure below is
                    // the engine's and not the provider still holding the last connection open.
                    var free = isLive
                    for _ in 0 ..< 8 where !free {
                        free = await answers(
                            stream.url,
                            ranged: stream.kind != .live,
                            transportStream: stream.url.hasSuffix(".ts")
                        )
                        if !free {
                            try? await Task.sleep(for: .seconds(4))
                        }
                    }
                    guard free else {
                        record("\(stream.label) | \(kind.displayName) | skipped: the provider did not answer")
                        continue
                    }
                    let outcome = await attempt(kind, stream)
                    record("\(stream.label) | \(kind.displayName) | \(outcome)")
                    // Let the provider close the connection before the next one opens.
                    try? await Task.sleep(for: .seconds(isLive ? 15 : 3))
                }
            }
            #expect(!all.isEmpty)
        }
    }
#endif
