import Foundation
import PanopCore
import PanopPlayback

struct StreamDetailRow: Identifiable {
    let label: String
    let value: String
    var id: String {
        label
    }
}

struct StreamDetailSection: Identifiable {
    let title: String
    let rows: [StreamDetailRow]
    var id: String {
        title
    }
}

/// What to show a person who asks "what is this stream doing?": the address (without its login), where it leads,
/// whether it goes through the VPN and why, how the player and the tunnel are, and what the player found in it.
/// Nothing here carries a login, a key or a path; it is safe to copy and send.
@MainActor
enum StreamDetails {
    static func sections(for model: PlayerModel, lookup: [String]? = nil) -> [StreamDetailSection] {
        [stream(model, lookup: lookup), route(model), player(model), format(model)].filter { !$0.rows.isEmpty }
    }

    static func text(_ sections: [StreamDetailSection]) -> String {
        sections.map { section in
            section.title + "\n" + section.rows.map { "  \($0.label): \($0.value)" }.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    // MARK: - Sections

    private static func stream(_ model: PlayerModel, lookup: [String]?) -> StreamDetailSection {
        var rows: [StreamDetailRow] = []
        let address = model.currentAddress ?? ""
        rows.append(row("Address", ProxyEndpoint.redacted(address) ?? String(localized: "Not a network address")))
        rows.append(row("Leads to", localityText(ProxyEndpoint.locality(of: address))))
        if let host = URL(string: address)?.host, isName(host) {
            rows.append(row("Host is", String(localized: "a name (only a lookup shows where it leads)")))
        }
        if let lookup {
            rows.append(row(
                "Lookup on this device",
                lookup.isEmpty ? String(localized: "no answer") : lookup.map(describe).joined(separator: "\n")
            ))
        }
        if let hint = StreamInfoText.containerHint(address: address).flatMap(StreamInfoText.container) {
            rows.append(row("Type from the address", hint))
        }
        return StreamDetailSection(title: String(localized: "Stream"), rows: rows)
    }

    private static func route(_ model: PlayerModel) -> StreamDetailSection {
        let network = ProviderNetwork.shared
        let tunnel = TunnelController.shared
        let address = model.currentAddress ?? ""
        let locality = ProxyEndpoint.locality(of: address)
        var rows: [StreamDetailRow] = []
        if network.tunnelIsOn {
            let through = network.proxy != nil && ProxyEndpoint.applies(to: address)
            rows.append(row("Through the VPN", through ? String(localized: "yes") : String(localized: "no")))
            if through, let kind = model.coordinatorKind {
                rows.append(row(
                    "Through",
                    kind.supportsProxy ? String(localized: "the proxy") : String(localized: "the relay inside Panop")
                ))
            }
            if !through {
                rows.append(row("Why not", whyNot(locality: locality, hasProxy: network.proxy != nil)))
            }
            rows.append(row("Built-in VPN", tunnelText(tunnel.state)))
            if let server = tunnel.config?.endpointHost {
                rows.append(row("VPN server", server))
            }
            if let proxy = network.proxy {
                rows.append(row(
                    "Proxy on this device",
                    "127.0.0.1:\(proxy.socksPort) (SOCKS5), 127.0.0.1:\(proxy.httpPort) (HTTP)"
                ))
            }
            if tunnel.state == .connected {
                rows.append(row("Received through the VPN", bytes(tunnel.counters.received)))
                rows.append(row("Sent through the VPN", bytes(tunnel.counters.sent)))
                if let shake = tunnel.counters.lastHandshake {
                    rows.append(row("Last handshake", shake.formatted(.relative(presentation: .numeric))))
                }
            }
        } else {
            rows.append(row("Through the VPN", String(localized: "no (the built-in VPN is off)")))
        }
        let monitor = SystemVPNMonitor.shared
        rows.append(row(
            "VPN active on the device",
            monitor.isVPNActive ? String(localized: "yes") : String(localized: "no")
        ))
        if UserDefaults.standard.bool(forKey: SystemVPNMonitor.requireKey) {
            rows.append(row("Require a VPN", String(localized: "on")))
        }
        if let block = network.block {
            rows.append(row("Connections held", block.description))
        }
        return StreamDetailSection(title: String(localized: "Route"), rows: rows)
    }

    private static func player(_ model: PlayerModel) -> StreamDetailSection {
        var rows: [StreamDetailRow] = []
        rows.append(row("Player", model.engineName ?? String(localized: "none yet")))
        rows.append(row("State", statusText(model.status)))
        if let join = model.joinTime {
            rows.append(row("Time to the first picture", String(format: "%.1f s", join)))
        }
        if let duration = model.duration {
            rows.append(row("Length", PlayerTime.text(duration)))
        }
        rows.append(row("Audio tracks", String(model.audioTracks.count)))
        rows.append(row("Subtitle tracks", String(model.subtitleTracks.count)))
        if let notice = model.notice {
            rows.append(row("Notice", notice))
        }
        if let failure = model.failureText {
            rows.append(row("Problem", failure))
        }
        return StreamDetailSection(title: String(localized: "Player"), rows: rows)
    }

    private static func format(_ model: PlayerModel) -> StreamDetailSection {
        guard let info = model.streamInfo
        else { return StreamDetailSection(title: String(localized: "Format"), rows: []) }
        var rows: [StreamDetailRow] = []
        if let container = info.container {
            rows.append(row("Container", container))
        }
        if let codec = info.videoCodec {
            rows.append(row("Video codec", codec))
        }
        if let width = info.width, let height = info.height {
            rows.append(row("Picture size", "\(width) × \(height)"))
        }
        if let rate = info.frameRate {
            rows.append(row("Frame rate", String(format: "%.2f", rate)))
        }
        if let hdr = info.hdr {
            rows.append(row("HDR", hdr))
        }
        if let codec = info.audioCodec {
            rows.append(row("Audio codec", codec))
        }
        if let channels = info.audioChannels {
            rows.append(row("Audio channels", String(channels)))
        }
        if info.audioIsAtmos {
            rows.append(row("Dolby Atmos", String(localized: "yes")))
        }
        return StreamDetailSection(title: String(localized: "Format"), rows: rows)
    }

    // MARK: - Words

    private static func row(_ label: String.LocalizationValue, _ value: String) -> StreamDetailRow {
        StreamDetailRow(label: String(localized: label), value: value)
    }

    private static func localityText(_ locality: ProxyEndpoint.Locality) -> String {
        switch locality {
        case .internet: String(localized: "the internet")
        case .privateNetwork: String(localized: "the local network (a private address)")
        case .loopback: String(localized: "this device")
        case .localName: String(localized: "the local network (a .local name)")
        case .notWeb: String(localized: "not an http address")
        }
    }

    private static func whyNot(locality: ProxyEndpoint.Locality, hasProxy: Bool) -> String {
        switch locality {
        case .privateNetwork, .loopback, .localName:
            String(localized: "it is on the local network, which the VPN does not reach")
        case .notWeb:
            String(localized: "it is not an http address")
        case .internet:
            if hasProxy {
                String(localized: "unknown")
            } else {
                String(localized: "the VPN is not connected, so nothing is sent")
            }
        }
    }

    private static func tunnelText(_ state: TunnelController.State) -> String {
        switch state {
        case .off: String(localized: "off")
        case .connecting: String(localized: "connecting")
        case .connected: String(localized: "connected")
        case .failed(.noConfiguration): String(localized: "no configuration")
        case .failed(.unreachable): String(localized: "the server did not answer")
        case let .failed(.invalid(detail)): detail
        case let .failed(.startFailed(detail)): detail
        }
    }

    private static func statusText(_ status: PlaybackStatus) -> String {
        switch status {
        case .idle: String(localized: "idle")
        case .connecting: String(localized: "connecting")
        case .buffering: String(localized: "buffering")
        case .playing: String(localized: "playing")
        case .paused: String(localized: "paused")
        case .reconnecting: String(localized: "reconnecting")
        case .ended: String(localized: "ended")
        case .failed: String(localized: "failed")
        }
    }

    private static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }

    private static func isName(_ host: String) -> Bool {
        host.contains(where: \.isLetter) && !host.contains(":")
    }

    private static func describe(_ address: String) -> String {
        let place = switch ProxyEndpoint.locality(ofHost: address) {
        case .internet: String(localized: "internet")
        case .privateNetwork: String(localized: "local network")
        case .loopback: String(localized: "this device")
        case .localName, .notWeb: ""
        }
        return place.isEmpty ? address : "\(address) (\(place))"
    }

    /// The addresses a name leads to, as this device's resolver says. Slow: not on the main thread.
    nonisolated static func resolve(_ host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
            ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil
        )
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &found) == 0, let first = found else { return [] }
        defer { freeaddrinfo(found) }
        var result: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ai_next }) {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                entry.pointee.ai_addr,
                entry.pointee.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let text = String(cString: buffer)
                if !result.contains(text) {
                    result.append(text)
                }
            }
        }
        return result
    }
}
