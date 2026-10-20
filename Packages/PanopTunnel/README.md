# PanopTunnel

An in-process WireGuard client for Panop's own traffic (ADR 0013).

```
Packages/PanopTunnel/
├── go/            the Go package: config parser, wireguard-go over its userspace netstack, and a SOCKS5
│                  and an HTTP proxy on 127.0.0.1 (random ports, random per-run login)
├── Sources/PanopTunnelKit   a thin Swift target, because Xcode cannot build a package product that is only a binary
├── SelfTest/      a Swift package that runs the end-to-end self-test on the Mac and the simulators
└── build/         generated: PanopTunnel.xcframework (not committed)
```

```bash
Scripts/build-tunnel.sh              # fetches Go 1.26 and SagerNet's gomobile into .build/tools, builds the xcframework
Scripts/ensure-tunnel.sh             # the same, only when the sources changed (the app scripts call it)
Scripts/test-tunnel.sh [macos|ios|tvos]   # builds the self-test variant and runs it on a simulator
(cd Packages/PanopTunnel/go && go test ./...)   # the Go tests, with an in-process stand-in VPN server
```

**Open the Xcode project only after `Scripts/ensure-tunnel.sh` has run once**, or it cannot resolve this package.

- **Why gomobile's fork:** upstream gomobile has no tvOS target; `github.com/sagernet/gomobile` (what sing-box builds
  with) has. Upstream wireguard-go and gVisor build unchanged.
- **gomobile's output is repacked** by the build script: it writes a macOS-style versioned framework for every
  platform, which iOS and tvOS refuse, around a static archive. Each iOS and tvOS slice becomes a shallow static
  framework (arm64 only for the simulators).
- **Nothing logs.** Errors name a configuration line, never a value; the private key is never printed.
- **The self-test** (`go build -tags selftest`) is compiled only into `build-selftest`; the shipped framework has no
  stand-in server in it.
