// Xcode cannot build a package product that is only a binary target ("PanopTunnel-product ... no such
// file"), so the product is this thin target, which carries the framework along.
@_exported import PanopTunnel
