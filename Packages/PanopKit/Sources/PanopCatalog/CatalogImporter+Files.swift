import Foundation
import PanopCore

/// A playlist on local disk, ready to parse.
struct PreparedFile {
    var path: String
    var digest: String
    /// True for a download, which the caller deletes when done.
    var isTemporary: Bool
}

extension CatalogImporter {
    /// Gets the playlist onto disk and digests it, without ever holding it in
    /// memory. A 500 MB playlist is normal.
    func prepare(_ source: M3USource) async throws -> PreparedFile {
        switch source {
        case let .file(path):
            try PreparedFile(path: path, digest: digestOfFile(at: path), isTemporary: false)
        case let .remote(url, secrets):
            try await download(url, redacting: secrets)
        }
    }

    private func digestOfFile(at path: String) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { throw CatalogError.cannotReadFile }
        defer { try? handle.close() }
        var digest = ContentDigest()
        while let chunk = try handle.read(upToCount: Self.readSize), !chunk.isEmpty {
            digest.update(chunk)
        }
        return digest.hex
    }

    private func download(_ url: URL, redacting secrets: [String]) async throws -> PreparedFile {
        let path = workingDirectory.appendingPathComponent("panop-\(UUID().uuidString).m3u").path
        guard FileManager.default.createFile(atPath: path, contents: nil),
              let handle = FileHandle(forWritingAtPath: path)
        else { throw CatalogError.cannotReadFile }

        var finished = false
        defer {
            try? handle.close()
            if !finished {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        do {
            let response = try await transport.stream(HTTPRequest(url: url, timeout: 300))
            guard (200 ..< 300).contains(response.statusCode) else {
                throw CatalogError.http(status: response.statusCode)
            }
            var digest = ContentDigest()
            for try await chunk in response.chunks {
                digest.update(chunk)
                try handle.write(contentsOf: chunk)
            }
            finished = true
            return PreparedFile(path: path, digest: digest.hex, isTemporary: true)
        } catch let error as CatalogError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let message = secrets.filter { !$0.isEmpty }.reduce(error.localizedDescription) {
                $0.replacingOccurrences(of: $1, with: "<redacted>")
            }
            throw CatalogError.download(message: message)
        }
    }
}
