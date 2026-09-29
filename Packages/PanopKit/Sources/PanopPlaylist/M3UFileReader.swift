import Foundation
import PanopCore

/// Reads an M3U file from disk in chunks and streams entries to a handler.
///
/// A thin convenience over ``M3UParser``. The parser itself does no I/O, which
/// is what keeps it trivially testable and portable; this type is where file
/// access is isolated.
public enum M3UFileReader {
    public enum Error: Swift.Error, Equatable {
        case cannotOpen(path: String)
    }

    /// Default read size. Large enough that syscall overhead disappears, small
    /// enough that peak memory stays flat on a constrained device.
    public static let defaultChunkSize = 512 * 1024

    /// Parses `path`, invoking `onBatch` as entries complete.
    ///
    /// Batches arrive in file order. The handler is called on the calling
    /// thread, so a caller writing to a database should batch its transactions
    /// rather than saving per call.
    ///
    /// - Returns: the playlist header, complete once the whole file is read.
    @discardableResult
    public static func read(
        contentsOfFile path: String,
        chunkSize: Int = defaultChunkSize,
        onBatch: ([PlaylistEntry]) throws -> Void
    ) throws -> PlaylistHeader {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw Error.cannotOpen(path: path)
        }
        defer { try? handle.close() }

        var parser = M3UParser()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            let entries = parser.consume(chunk)
            if !entries.isEmpty {
                try onBatch(entries)
            }
        }

        let remaining = parser.finish()
        if !remaining.isEmpty {
            try onBatch(remaining)
        }
        return parser.header
    }

    /// Reads only enough of the file to recover the `#EXTM3U` header.
    ///
    /// Used on the skip-if-unchanged path, where the EPG URLs are needed but
    /// re-parsing 80,000 entries is not.
    public static func readHeader(contentsOfFile path: String) throws -> PlaylistHeader {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw Error.cannotOpen(path: path)
        }
        defer { try? handle.close() }

        var parser = M3UParser()
        if let chunk = try handle.read(upToCount: 64 * 1024) {
            _ = parser.consume(chunk)
        }
        return parser.header
    }
}
