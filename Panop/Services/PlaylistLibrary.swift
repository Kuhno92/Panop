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
                createdAt: $0.createdAt
            )
        }
    }

    // MARK: - Adding

    /// Validates, stores and starts syncing a playlist.
    ///
    /// Xtream credentials are checked against the panel first, so a typo is
    /// reported here rather than as a failed sync minutes later.
    @discardableResult
    func add(_ draft: PlaylistDraft) async throws -> PlaylistSummary {
        let id = UUID().uuidString
        let prepared = try await prepare(draft, id: id)

        do {
            try credentials.save(prepared.secret, for: id)
        } catch {
            throw PlaylistAddError(message: "The login details could not be saved to the Keychain.")
        }

        let record = PlaylistRecord(
            id: id,
            name: prepared.name,
            kind: prepared.kind,
            displayHost: prepared.host,
            localFileName: prepared.localFileName,
            sortOrder: playlists.count
        )
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
            throw PlaylistAddError(message: "The playlist could not be saved.")
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
            createdAt: record.createdAt
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
                    message: "That is not a valid web address. It should start with http:// or https://."
                )
            }
            let guide = guideURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if let guide, Self.webHost(guide) == nil {
                throw PlaylistAddError(message: "The TV guide address is not a valid web address.")
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
            throw PlaylistAddError(message: "That file could not be read.")
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
            return PlaylistDescriptor(id: id, source: .remoteM3U(url), guideURL: secret?.guideURL)
        case .localM3U:
            guard let file = record.localFileName else { return nil }
            return PlaylistDescriptor(id: id, source: .localM3U(path: directory.appendingPathComponent(file).path))
        case .xtream:
            guard let secret, let url = secret.url, let user = secret.username,
                  let password = secret.password else { return nil }
            return PlaylistDescriptor(
                id: id,
                source: .xtream(ProviderCredentials(baseURL: url, username: user, password: password))
            )
        }
    }

    /// Deletes the playlist, its catalog rows, its stored credentials and any
    /// local copy of its file.
    func remove(_ id: String) async {
        try? await sync.remove(id)
        try? credentials.delete(for: id)
        if let record = try? fetchRecord(id) {
            if let file = record
                .localFileName
            {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
            context.delete(record)
            try? context.save()
        }
        reload()
    }

    func confirm(_ removal: DeferredRemoval, playlist: String) async throws {
        try await sync.confirm(removal, playlist: playlist)
    }

    func refresh(_ id: String, force: Bool = false) async {
        guard let descriptor = try? descriptor(for: id) else { return }
        await sync.start(descriptor, force: force)
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
