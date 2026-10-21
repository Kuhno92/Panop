# 0013. An in-process WireGuard tunnel for the app's own traffic

**Status:** accepted (supersedes 0006 for the "route Panop's traffic through a VPN" requirement)

## Context

The owner wants to paste the WireGuard configuration of a commercial VPN (Proton, Mullvad) into
Settings and have every provider connection (playlists, guides, artwork, streams) go through it, on
iPhone, iPad, Mac and Apple TV, under a **personal** Apple Developer account.

A Network Extension packet tunnel is the system-level answer, but App Store Guideline 5.4 reserves VPN
apps for organisation accounts (ADR 0006). So Panop does not offer a VPN service or a system VPN.

## Decision

Panop runs a WireGuard peer **inside its own process** (wireguard-go with its gVisor userspace network
stack: no virtual interface, no root, no entitlement), and exposes it to its own code through two
proxies on `127.0.0.1` (SOCKS5 and HTTP, with a random per-run login so no other app can use them).
Panop points its own connections at those proxies. Nothing else on the device is touched.

- `Packages/PanopTunnel/go`: the Go package. `Scripts/build-tunnel.sh` builds
  `PanopTunnel.xcframework` for iOS, tvOS and macOS (device and simulator) with
  `github.com/sagernet/gomobile` v0.1.13 (the fork sing-box builds its tvOS client with) on stock Go.
  Upstream `golang.zx2c4.com/wireguard` builds unchanged; no SagerNet fork of it is needed.
- Names are resolved **inside** the tunnel (the SOCKS5 proxy dials domain names through the tunnel's
  DNS). The one lookup outside is the VPN endpoint's own hostname, if it is not an IP.
- Nothing logs. Errors name a configuration line, never a value.
- `ProviderNetwork` (ADR-adjacent, see CLAUDE.md) is the one door for provider traffic and fails closed.

## Spike result (2026-10-20)

- Builds for all five targets with the stock toolchain, no Go patches (the iOS CPU-feature patch sing-box
  applies concerns AES/SHA, not ChaCha20-Poly1305 that WireGuard uses).
- Stripped framework: **11.7 MB** per device slice (iOS, tvOS), arm64 only.
- `TunnelSelfTests` (a stand-in VPN server and the real client in one process, a page fetched through
  both proxies, wrong login refused) **passes on the macOS host, the iOS simulator and the tvOS simulator**.
- Not yet measured: throughput and memory on a real Apple TV, and a handshake with a real provider.

## What was measured about the players (macOS, a stand-in proxy that refuses, an origin on a LAN address)

| Engine | Result | So |
|---|---|---|
| LumeEngine | asks the proxy for the origin, with the login; never contacts the origin | supported (`formatOptions["http_proxy"]`) |
| KSPlayer | the same | supported (`formatContextOptions["http_proxy"]`) |
| VLC 4.0.0-a24 | connects straight to the origin, whether `http-proxy` is a media option, an instance option (`VLCMediaPlayer(options:)`) or the `http_proxy` variable | skipped while the tunnel is on |
| AetherEngine | connects straight to the origin: it opens its own `URLSession`s and ignores `http_proxy` | skipped while the tunnel is on |
| AVPlayer | has no per-app proxy | skipped while the tunnel is on |

An engine that cannot use the tunnel is left out of the order (`PlaybackEngineKind.supportsProxy`); if none is left, the
stream fails. Nothing falls back to a direct connection. Consequences: Picture in Picture and AirPlay (AVPlayer) are
unavailable while the tunnel is on.

URLSession was measured too: with a proxy configured it sends public destinations to the proxy and, with the proxy
dead, fails them (no direct fallback). **It bypasses the proxy for private-network addresses** (192.168/16 and the
like), so a provider on a LAN address would connect directly; the tunnel could not reach it anyway.

## Trailers

YouTube's web view (iPhone, iPad, Mac) is given the proxy through its own non-persistent data store. On Apple TV the
trailer is read by YouTubeKit with its own session and played by AVPlayer; neither can use the tunnel, so trailers are
unavailable on Apple TV, and file trailers everywhere, while it is on. CloudKit is the system's and stays outside it.

## Entering the configuration

iPhone, iPad and Mac: paste the whole file, or choose it. Apple TV has no multi-line entry, so it has a form with one
field per setting, filled with the iPhone as the keyboard. Bringing a configuration across through iCloud (as the
sportapi.ai key travels) is possible but needs a new record type in the CloudKit schema; not done.

## Release notes for the owner

- `ITSAppUsesNonExemptEncryption` is now `YES` (it was `NO`). WireGuard's own cryptography is not covered by the exemptions for
  TLS and OS-provided encryption, so **before a build with the tunnel goes to TestFlight or the store it must be
  `YES`**, and App Store Connect will ask the export-compliance questions for each build (mass-market
  self-classification under BIS 740.17(b)(1), an annual self-classification report, and France's declaration for
  distribution there). The tunnel is linked into every build, so a build flag would not avoid this.
- App Review may read the tunnel as VPN functionality (Guideline 5.4). Suggested wording for the review notes: *"Panop
  can optionally send its own connections (playlists, guides, streams) through the user's own WireGuard configuration.
  It is a per-app proxy inside the app; it creates no system VPN, uses no Network Extension and offers no VPN service."*
- `PRIVACY.md` says what the feature keeps (the private key, in this device's Keychain) and sends (the exit-address
  check, when the person taps the button, asks https://api.ipify.org).

## Consequences

- AVPlayer cannot use a per-app proxy, so while the tunnel is on it is left out of the engine order.
- The framework is generated (not committed); a clean checkout needs `Scripts/build-tunnel.sh` once.
- Export compliance changes (`ITSAppUsesNonExemptEncryption`), and App Review may still read this as VPN
  functionality (Guideline 5.4). It is described as a per-app proxy tunnel for the person's own provider
  traffic, and shipped behind one build flag so it can be switched off.
- Licences: wireguard-go MIT, gVisor Apache-2.0, golang.org/x BSD-3-Clause. "WireGuard" is a registered
  trademark of Jason A. Donenfeld; Panop says "WireGuard-compatible" and uses no logo.
