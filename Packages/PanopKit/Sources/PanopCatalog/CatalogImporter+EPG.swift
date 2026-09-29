import Foundation
import PanopCore
import PanopEPG

public extension CatalogImporter {
    /// Imports an XMLTV guide, keeping only programmes that overlap `window`.
    ///
    /// Stored programmes that have already ended are dropped. Stored programmes
    /// still in the window that the new guide no longer lists (the provider
    /// rescheduled them) are dropped too, but only after the guide read to its
    /// closing tag and only if that is a believable amount. A guide that fails
    /// or is cut off part-way throws and removes nothing.
    ///
    /// - Parameter redacting: strings to scrub from error messages, usually the
    ///   account's username and password when they are in the URL.
    func importEPG(
        playlist: String,
        url: URL,
        window: ClosedRange<Date>,
        redacting secrets: [String] = []
    ) async throws -> EPGImportReport {
        let before = try await store.programmeCount(playlist: playlist, endingAfter: window.lowerBound)
        let batches = EPGBatches(
            transport: transport,
            url: url,
            window: window,
            batchSize: batchSize,
            redacting: secrets
        )

        var report = EPGImportReport()
        var seen = Set<UInt64>()
        var seenChannels = Set<String>()
        var processed = 0

        for try await batch in batches {
            var channels: [EPGChannel] = []
            var programmes: [EPGProgramme] = []
            for element in batch {
                switch element {
                case let .channel(channel): channels.append(channel)
                case let .programme(programme): programmes.append(programme)
                }
            }
            try await store.upsertEPGChannels(channels, playlist: playlist)
            report.channels += channels.count
            report.programmes += try await store.upsertProgrammes(programmes, playlist: playlist)
            for programme in programmes {
                let key = ProgrammeKey(programme)
                seen.insert(key.hash64)
                seenChannels.insert(key.channelKey)
            }
            processed += programmes.count
            progress?(ImportProgress(kind: nil, processed: processed))
        }

        // Only reached when the guide read cleanly to `</tv>`.
        report.removedExpired = try await store.removeProgrammes(endedBefore: window.lowerBound, playlist: playlist)
        let sweep = try await sweepProgrammes(
            seen: seen,
            seenChannels: seenChannels,
            before: before,
            playlist: playlist,
            from: window.lowerBound
        )
        report.removedStale = sweep.removed
        report.deferredStale = sweep.deferred
        return report
    }
}
