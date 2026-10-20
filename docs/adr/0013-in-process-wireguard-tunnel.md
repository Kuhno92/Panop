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
- Not yet measured: throughput and memory on a real Apple TV, a real provider handshake, and each
  engine's proxy support (VLC `http-proxy`, FFmpeg `http_proxy`, AVPlayer has none).

## Consequences

- AVPlayer cannot use a per-app proxy, so while the tunnel is on it is left out of the engine order.
- The framework is generated (not committed); a clean checkout needs `Scripts/build-tunnel.sh` once.
- Export compliance changes (`ITSAppUsesNonExemptEncryption`), and App Review may still read this as VPN
  functionality (Guideline 5.4). It is described as a per-app proxy tunnel for the person's own provider
  traffic, and shipped behind one build flag so it can be switched off.
- Licences: wireguard-go MIT, gVisor Apache-2.0, golang.org/x BSD-3-Clause. "WireGuard" is a registered
  trademark of Jason A. Donenfeld; Panop says "WireGuard-compatible" and uses no logo.
