import Foundation
import Observation
import PanopCatalog
import PanopCore
import PanopXtream
import SwiftData

/// What the user typed into the add-playlist form.
nonisolated enum PlaylistDraft: Sendable {
    case m3uURL(name: String, url: String, guideURL: String?)
    /// A file the user picked. It is copied into the app's own storage, so
    /// refreshing does not depend on the original staying where it was.
    case m3uFile(name: String, fileURL: URL)
    case xtream(name: String, baseURL: String, username: String, password: String)
}

/// A reason a playlist could not be added, in words for the user.
nonisolated struct PlaylistAddError: Error, LocalizedError, Equatable {
    var message: String
    var errorDescription: String? {
        message
    }
}

/// The user's playlists: what is stored, and how to turn one back into
/// something the importer can fetch.
///
/// The list is read with explicit fetches on the cloud container, never
/// `@Query`: a mirrored container re-runs every bound query during CloudKit
/// churn, which freezes tvOS. See docs/adr/0003-two-model-containers.md.
@MainActor
@Observable
final class PlaylistLibrary {
    private(set) var playlists: [PlaylistSummary] = []
    /// Playlists being deleted right now, so the screen can show it and refuse a second tap.
    private(set) var removing: Set<String> = []
    /// Called with a playlist's id once it has been deleted, so what hangs off it can go too.
    var onRemoved: ((String) -> Void)?

    /// Whether logins travel with the playlists: the person wants it and iCloud is on. A closure, so it is
    /// read when it matters. Off until the app says otherwise, so nothing leaves a device by accident.
    var syncsLogins: () -> Bool = { false }
    /// What this device last wrote to or took from each record's login, by playlist id, as a digest.
    var loginMemory: any LoginMemory = DefaultsLoginMemory()

    private let context: ModelContext
    private let credentials: any CredentialStore
    private let sync: SyncService
    private let transport: any HTTPTransport
    private let directory: URL

    init(
        context: ModelContext,
        credentials: any CredentialStore,
        sync: SyncService,
        transport: any HTTPTransport,
        directory: URL
    ) {
        self.context = context
        self.credentials = credentials
        self.sync = sync
        self.transport = transport
        self.directory = directory
        reload()
    }

    func reload() {
        let descriptor = FetchDescriptor<PlaylistRecord>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        playlists = records.map {
            PlaylistSummary(
                id: $0.id,
                name: $0.name,
                kind: $0.kind,
                displayHost: $0.displayHost,
                createdAt: $0.createdAt,
                includesVOD: $0.includesVOD
            )
        }
    }

    /// Another device changed the playlists and it has arrived. New ones appear (and are fetched, if they
    /// can be: their logins come with them or are asked for). One removed there is removed here: its
    /// catalog rows, its login and what hangs off it. Called only after a successful CloudKit import, so a
    /// store that is merely empty never reads as everything having been deleted.
    func applyRemoteChanges() async {
        let before = Set(playlists.map(\.id))
        reload()
        // Logins that arrived go into the Keychain first, so a new playlist can be fetched below.
        reconcileLogins()
        let after = Set(playlists.map(\.id))
        for id in before.subtracting(after) {
            guard !removing.contains(id) else { continue }
            try? await sync.remove(id)
            try? credentials.delete(for: id)
            onRemoved?(id)
        }
        if !after.subtracting(before).isEmpty {
            await refreshStale(maxAge: 12 * 3600)
        }
    }

    /// Brings each playlist's login and its record into line, as the person's setting says: logins go to the
    /// records so other devices can use them, a login that arrived is taken into the Keychain, and with the
    /// setting off they are withdrawn from the records. Safe to run any number of times.
    func reconcileLogins() {
        let records = (try? context.fetch(FetchDescriptor<PlaylistRecord>())) ?? []
        let uploading = syncsLogins()
        var changed = false
        for record in records where record.kind != .localM3U {
            let local = try? credentials.load(for: record.id)
            let action = PlaylistLogins.decide(
                local: local,
                blob: record.encryptedLogin,
                remembered: loginMemory.digest(for: record.id),
                uploading: uploading
            )
            switch action {
            case .none:
                if let blob = record.encryptedLogin {
                    loginMemory.remember(PlaylistLogins.digest(blob), for: record.id)
                }
            case let .upload(blob):
                record.encryptedLogin = blob
                loginMemory.remember(PlaylistLogins.digest(blob), for: record.id)
                changed = true
            case let .adopt(secret):
                if (try? credentials.save(secret, for: record.id)) != nil, let blob = record.encryptedLogin {
                    loginMemory.remember(PlaylistLogins.digest(blob), for: record.id)
                }
            case .withdraw:
                record.encryptedLogin = nil
                loginMemory.forget(for: record.id)
                changed = true
            }
        }
        if changed {
            try? context.save()
        }
    }

    /// Whether any source has movies and series to show. The Movies and Series screens are
    /// offered only then. With no source at all there is nothing to hide yet.
    var offersVOD: Bool {
        playlists.isEmpty || playlists.contains(where: \.includesVOD)
    }

    // MARK: - Adding

    /// Validates, stores and starts syncing a playlist.
    ///
    /// Xtream credentials are checked against the panel first, so a typo is
    /// reported here rather than as a failed sync minutes later.
    ///
    /// - Parameter includeVOD: false for a source that is only wanted for its live channels:
    ///   movies and series are then not downloaded, parsed or stored.
    @discardableResult
    func add(_ draft: PlaylistDraft, includeVOD: Bool = true) async throws -> PlaylistSummary {
        let id = UUID().uuidString
        let prepared = try await prepare(draft, id: id)

        do {
            try credentials.save(prepared.secret, for: id)
        } catch {
            throw PlaylistAddError(message: String(localized: "The login details could not be saved to the Keychain."))
        }

        let record = PlaylistRecord(
            id: id,
            name: prepared.name,
            kind: prepared.kind,
            displayHost: prepared.host,
            localFileName: prepared.localFileName,
            sortOrder: playlists.count,
            includesVOD: includeVOD
        )
        if syncsLogins(), prepared.kind != .localM3U, let blob = PlaylistLogins.encode(prepared.secret) {
            record.encryptedLogin = blob
            loginMemory.remember(PlaylistLogins.digest(blob), for: id)
        }
        context.insert(record)
        do {
            try context.save()
        } catch {
            // Do not leave a secret behind for a playlist that does not exist.
            context.rollback()
            try? credentials.delete(for: id)
            if let file = prepared
                .localFileName
            {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
            throw PlaylistAddError(message: String(localized: "The playlist could not be saved."))
        }

        reload()
        if let descriptor = try? descriptor(for: id) {
            await sync.start(descriptor)
        }
        return PlaylistSummary(
            id: id,
            name: prepared.name,
            kind: prepared.kind,
            displayHost: prepared.host,
            createdAt: record.createdAt,
            includesVOD: includeVOD
        )
    }

    private struct Prepared {
        var name: String
        var kind: PlaylistKind
        var host: String
        var secret: PlaylistSecret
        var localFileName: String?
    }

    private func prepare(_ draft: PlaylistDraft, id: String) async throws -> Prepared {
        switch draft {
        case let .m3uURL(name, url, guideURL):
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let host = Self.webHost(trimmed) else {
                throw PlaylistAddError(
                    message: String(
                        localized: "That is not a valid web address. It should start with http:// or https://."
                    )
                )
            }
            let guide = guideURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if let guide, Self.webHost(guide) == nil {
                throw PlaylistAddError(message: String(localized: "The TV guide address is not a valid web address."))
            }
            return Prepared(
                name: name.nilIfBlank ?? host,
                kind: .remoteM3U,
                host: host,
                secret: PlaylistSecret(url: trimmed, guideURL: guide)
            )

        case let .m3uFile(name, fileURL):
            let fileName = try copyPlaylistFile(fileURL, id: id)
            return Prepared(
                name: name.nilIfBlank ?? fileURL.deletingPathExtension().lastPathComponent,
                kind: .localM3U,
                host: "On this device",
                secret: PlaylistSecret(),
                localFileName: fileName
            )

        case let .xtream(name, baseURL, username, password):
            let credentials = ProviderCredentials(
                baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            let client: XtreamClient
            do {
                client = try XtreamClient(credentials: credentials, transport: transport)
            } catch {
                throw PlaylistAddError(message: SyncErrorMessage.text(for: error))
            }
            do {
                _ = try await client.authenticate()
            } catch {
                throw PlaylistAddError(message: SyncErrorMessage.text(for: error))
            }
            let host = Self.webHost(credentials.baseURL) ?? credentials.baseURL
            return Prepared(
                name: name.nilIfBlank ?? host,
                kind: .xtream,
                host: host,
                secret: PlaylistSecret(
                    url: credentials.baseURL,
                    username: credentials.username,
                    password: credentials.password
                )
            )
        }
    }

    private func copyPlaylistFile(_ source: URL, id: String) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let name = "\(id).m3u"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
        } catch {
            throw PlaylistAddError(message: String(localized: "That file could not be read."))
        }
        return name
    }

    // MARK: - Using and removing

    /// Everything the importer needs, or nil if the playlist or its secret is
    /// missing (for instance a record that synced to a device with no Keychain entry).
    func descriptor(for id: String) throws -> PlaylistDescriptor? {
        guard let record = try fetchRecord(id) else { return nil }
        let secret = try credentials.load(for: id)

        switch record.kind {
        case .remoteM3U:
            guard let url = secret?.url else { return nil }
            return PlaylistDescriptor(
                id: id,
                source: .remoteM3U(url),
                guideURL: secret?.guideURL,
                name: record.name,
                includeVOD: record.includesVOD
            )
        case .localM3U:
            guard let file = record.localFileName else { return nil }
            return PlaylistDescriptor(
                id: id,
                source: .localM3U(path: directory.appendingPathComponent(file).path),
                name: record.name,
                includeVOD: record.includesVOD
            )
        case .xtream:
            guard let secret, let url = secret.url, let user = secret.username,
                  let password = secret.password else { return nil }
            return PlaylistDescriptor(
                id: id,
                source: .xtream(ProviderCredentials(baseURL: url, username: user, password: password)),
                includeVOD: record.includesVOD
            )
        }
    }

    /// Deletes the playlist: its catalog rows, its stored login, any local copy of
    /// its file, and its record.
    ///
    /// **Order matters.** The catalog rows go first, and if that fails nothing
    /// else is touched, so the playlist stays in the list and the delete can be
    /// retried. Deleting the record and login first would leave channels behind
    /// that no screen can reach.
    ///
    /// - Returns: nil on success, or a message for the user.
    @discardableResult
    func remove(_ id: String) async -> String? {
        guard !removing.contains(id) else { return nil }
        removing.insert(id)
        defer { removing.remove(id) }

        do {
            try await sync.remove(id)
        } catch {
            return "This playlist could not be deleted. Nothing was changed, so you can try again."
        }

        // The catalog is clean. A login that will not delete is not worth
        // failing over: the playlist is already gone from every screen.
        try? credentials.delete(for: id)
        if let record = try? fetchRecord(id) {
            if let file = record.localFileName {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
            context.delete(record)
            try? context.save()
        }
        reload()
        onRemoved?(id)
        return nil
    }

    /// Turns movies and series on or off for an existing source.
    ///
    /// Off removes the ones already stored, and the next updates leave them out. On fetches
    /// them: a full re-import, since an unchanged M3U file would otherwise be skipped.
    ///
    /// - Returns: nil on success, or a message for the user.
    @discardableResult
    func setIncludesVOD(_ includes: Bool, for id: String) async -> String? {
        guard let record = try? fetchRecord(id), record.includesVOD != includes else { return nil }
        if !includes {
            // Rows first: if they cannot be removed the source stays as it was.
            do {
                try await sync.dropVOD(id)
            } catch {
                return "The movies and series could not be removed. Nothing was changed, so you can try again."
            }
        }
        record.includesVOD = includes
        do {
            try context.save()
        } catch {
            context.rollback()
            return "That setting could not be saved."
        }
        reload()
        if includes {
            await refresh(id, force: true)
        }
        return nil
    }

    func confirm(_ removal: DeferredRemoval, playlist: String) async throws {
        try await sync.confirm(removal, playlist: playlist)
    }

    /// Updates one playlist. `force` re-imports even a file that has not changed.
    ///
    /// A playlist that cannot be refreshed says why on its row, instead of doing nothing.
    func refresh(_ id: String, force: Bool = false) async {
        guard let descriptor = try? descriptor(for: id) else {
            await sync.report(
                failure: "This playlist's login details are missing on this device. Delete it and add it again.",
                for: id
            )
            return
        }
        await sync.start(descriptor, force: force)
    }

    func refreshAll(force: Bool = false) async {
        for playlist in playlists where !removing.contains(playlist.id) {
            await refresh(playlist.id, force: force)
        }
    }

    /// Stops a sync that is running. What was already imported stays.
    func stop(_ id: String) async {
        await sync.cancel(id)
    }

    /// Refreshes every playlist that has not completed a sync within `maxAge`.
    func refreshStale(maxAge: TimeInterval, now: Date = .now) async {
        for playlist in playlists {
            let last = await sync.lastCompleted(playlist.id)
            if let last, now.timeIntervalSince(last) < maxAge {
                continue
            }
            await refresh(playlist.id)
        }
    }

    // MARK: - Helpers

    private func fetchRecord(_ id: String) throws -> PlaylistRecord? {
        var descriptor = FetchDescriptor<PlaylistRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The host of an http(s) URL, or nil if it is not one.
    nonisolated static func webHost(_ text: String) -> String? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        return host
    }
}

private extension String {
    /// Nil for an empty or all-whitespace string.
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// What a device remembers about the login on each playlist record (see `PlaylistLogins.decide`).
@MainActor
protocol LoginMemory {
    func digest(for playlist: String) -> String?
    func remember(_ digest: String, for playlist: String)
    func forget(for playlist: String)
}

/// In the app's preferences: only a digest, never the login.
@MainActor
struct DefaultsLoginMemory: LoginMemory {
    private var defaults: UserDefaults {
        .standard
    }

    private func key(_ playlist: String) -> String {
        "loginDigest.\(playlist)"
    }

    func digest(for playlist: String) -> String? {
        defaults.string(forKey: key(playlist))
    }

    func remember(_ digest: String, for playlist: String) {
        defaults.set(digest, forKey: key(playlist))
    }

    func forget(for playlist: String) {
        defaults.removeObject(forKey: key(playlist))
    }
}

/// For tests: nothing is written outside the process.
@MainActor
final class InMemoryLoginMemory: LoginMemory {
    private var digests: [String: String] = [:]

    func digest(for playlist: String) -> String? {
        digests[playlist]
    }

    func remember(_ digest: String, for playlist: String) {
        digests[playlist] = digest
    }

    func forget(for playlist: String) {
        digests[playlist] = nil
    }
}
