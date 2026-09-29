# 0006. No VPN integration in v1

**Status:** accepted

## Context

"Automatically enable a VPN when the app opens" was an early requirement. On Apple platforms it
is mostly not achievable as stated.

`NEVPNManager` and `NETunnelProviderManager` control only a tunnel the app itself provides. An
app **cannot** programmatically start a third-party VPN such as NordVPN or Surfshark. There is
no API for it, by design.

Delivering auto-connect therefore means shipping Panop's own tunnel: a Network Extension
packet-tunnel-provider target, a WireGuard or OpenVPN implementation, and the Network Extension
entitlement. App Store Review Guideline 5.4 additionally requires VPN apps to come from an
organization developer account, not an individual one. An IPTV app that also bundles a VPN
attracts materially heavier review scrutiny.

## Decision

No VPN code in v1. No Network Extension target, no entitlement requests.

## Consequences

The stated requirement is not met in v1, and that is a deliberate trade rather than an
oversight. The cost of meeting it (an organization account, a tunnel implementation, an extra
target, and heightened review risk) is disproportionate before the player and catalog work at
all.

Nothing about this decision is hard to reverse. Adding a Network Extension target later does
not disturb the architecture.

If it is revisited, the options in increasing order of effort are:

1. **Detect and warn.** Check VPN status on launch, surface it, optionally gate playback. A
   day's work, no entitlements, no review risk.
2. **In-app proxy.** Route only Panop's stream traffic through a userspace WireGuard or SOCKS5
   tunnel, avoiding any system VPN permission. Works cleanly where the engine accepts a custom
   transport, but AVPlayer will not take a proxy, so coverage would be partial.
3. **Ship a real tunnel.** Full auto-connect via on-demand rules. Requires the organization
   account and the entitlement.
