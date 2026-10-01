import PanopPlayback

/// Plain-language text for what the coordinator reports.
nonisolated enum PlaybackMessages {
    static func text(for notice: PlaybackNotice) -> String {
        switch notice {
        case let .fellBack(from, to, _):
            "\(from.displayName) couldn't open this stream, so Panop is using \(to.displayName)."
        case let .reconnecting(_, reason):
            // An open that failed is not a dropped connection: saying so sent a
            // bad address down the wrong diagnosis.
            switch reason.code {
            case .network: "The connection dropped. Reconnecting…"
            default: "Couldn't open the stream. Trying again…"
            }
        }
    }

    static func text(for failure: PlaybackFailure) -> String {
        let tried = failure.attempts.filter { $0.error != nil }.map(\.engine.displayName)
        let missing = failure.attempts.filter { $0.error == nil }.map(\.engine.displayName)

        var text: String = switch failure.lastError?.code {
        case .unsupportedFormat, .decodeFailed:
            "The available players can't open this stream's format."
        case .network:
            "Couldn't reach this stream. Check your connection, and that the provider is up."
        case .secureConnectionFailed:
            "A secure connection to this stream could not be made."
        case .invalidAddress:
            "This stream's address isn't valid. Check the link, or refresh the playlist."
        case .openFailed:
            "This stream wouldn't open."
        case .cancelled, .internalError, nil:
            missing.isEmpty ? "Playback failed." : "This stream needs a player Panop doesn't have yet."
        }
        if !tried.isEmpty {
            text += " Tried: \(unique(tried).joined(separator: ", "))."
        }
        if !missing.isEmpty, failure.lastError != nil {
            text += " Not available yet: \(unique(missing).joined(separator: ", "))."
        }
        return text
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
