// Package tunnel runs a WireGuard peer inside the app's own process, with no virtual network interface and
// no system VPN: traffic is handed in through two proxies on 127.0.0.1 (SOCKS5 and HTTP) and leaves through
// the tunnel. Panop points its own connections at those proxies; nothing else on the device is touched.
package tunnel

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

// dnsProbe is a standard query for "example.com" A. Any reply proves the tunnel carries traffic both ways.
var dnsProbe = []byte{0x50, 0x4e, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1}

// Tunnel is one running peer. Exposed to Swift through gomobile, so only simple types cross the boundary.
type Tunnel struct {
	mu        sync.Mutex
	dev       *device.Device
	socks     net.Listener
	httpL     net.Listener
	httpSrv   *http.Server
	relayL    net.Listener
	relaySrv  *http.Server
	secret    string
	relayPort int
	tnet      *netstack.Net
	dns       netip.Addr
	user      string
	pass      string
	socksPort int
	httpPort  int
}

func NewTunnel() *Tunnel { return &Tunnel{} }

// Start brings the tunnel up from the text of a standard WireGuard configuration. It returns once the
// proxies listen; the handshake with the server happens on first traffic (see LastHandshakeUnix).
func (t *Tunnel) Start(config string) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.dev != nil {
		return errors.New("already running")
	}
	cfg, err := parseConfig(config)
	if err != nil {
		return err
	}
	tunDev, tnet, err := netstack.CreateNetTUN(cfg.addresses, cfg.dns, cfg.mtu)
	if err != nil {
		return errors.New("could not create the virtual network")
	}
	// Silent: nothing here logs, since addresses and keys must not reach a log.
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	if err := dev.IpcSet(cfg.ipc); err != nil {
		dev.Close()
		return errors.New("the configuration was refused")
	}
	if err := dev.Up(); err != nil {
		dev.Close()
		return errors.New("the tunnel could not start")
	}

	t.user, t.pass = randomHex(8), randomHex(16)
	socks, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		dev.Close()
		return err
	}
	httpL, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		_ = socks.Close()
		dev.Close()
		return err
	}
	relayL, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		_ = socks.Close()
		_ = httpL.Close()
		dev.Close()
		return err
	}
	t.dev, t.socks, t.httpL, t.relayL = dev, socks, httpL, relayL
	t.secret = randomHex(16)
	t.relayPort = relayL.Addr().(*net.TCPAddr).Port
	t.relaySrv = newRelay(t.secret, tnet.DialContext).server()
	go func() { _ = t.relaySrv.Serve(relayL) }()
	t.tnet, t.dns = tnet, cfg.dns[0]
	t.socksPort = socks.Addr().(*net.TCPAddr).Port
	t.httpPort = httpL.Addr().(*net.TCPAddr).Port
	t.httpSrv = newHTTPProxy(t.user, t.pass, tnet.DialContext)
	go serveSOCKS5(socks, t.user, t.pass, tnet.DialContext)
	go func() { _ = t.httpSrv.Serve(httpL) }()
	return nil
}

// Stop closes the proxies and the tunnel. Safe to call twice.
func (t *Tunnel) Stop() {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.dev == nil {
		return
	}
	_ = t.socks.Close()
	_ = t.httpSrv.Close()
	_ = t.relaySrv.Close()
	t.dev.Close()
	t.dev, t.socks, t.httpL, t.httpSrv, t.tnet = nil, nil, nil, nil, nil
	t.socksPort, t.httpPort, t.relayPort = 0, 0, 0
	t.relayL, t.relaySrv, t.secret = nil, nil, ""
}

// WaitReady returns nil once a DNS query sent through the tunnel is answered, which needs the handshake
// to have completed and traffic to flow both ways. It retries once a second until the time is up.
func (t *Tunnel) WaitReady(timeoutSeconds int) error {
	t.mu.Lock()
	tnet, dns := t.tnet, t.dns
	t.mu.Unlock()
	if tnet == nil {
		return errors.New("not running")
	}
	deadline := time.Now().Add(time.Duration(timeoutSeconds) * time.Second)
	for time.Now().Before(deadline) {
		if probe(tnet, dns) {
			return nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	return errors.New("the VPN server did not answer")
}

func probe(tnet *netstack.Net, dns netip.Addr) bool {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	c, err := tnet.DialContext(ctx, "udp", netip.AddrPortFrom(dns, 53).String())
	if err != nil {
		return false
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(time.Second))
	if _, err := c.Write(dnsProbe); err != nil {
		return false
	}
	reply := make([]byte, 512)
	n, err := c.Read(reply)
	return err == nil && n >= 12
}

func (t *Tunnel) SocksPort() int { t.mu.Lock(); defer t.mu.Unlock(); return t.socksPort }
func (t *Tunnel) HTTPPort() int  { t.mu.Lock(); defer t.mu.Unlock(); return t.httpPort }

// RelayPort and RelaySecret make the address a player is given for a stream (see relay.go).
func (t *Tunnel) RelayPort() int      { t.mu.Lock(); defer t.mu.Unlock(); return t.relayPort }
func (t *Tunnel) RelaySecret() string { t.mu.Lock(); defer t.mu.Unlock(); return t.secret }
func (t *Tunnel) Username() string    { t.mu.Lock(); defer t.mu.Unlock(); return t.user }
func (t *Tunnel) Password() string    { t.mu.Lock(); defer t.mu.Unlock(); return t.pass }

// LastHandshakeUnix is the time of the last completed handshake with the server, in Unix seconds, or 0.
func (t *Tunnel) LastHandshakeUnix() int64 { return t.stat("last_handshake_time_sec") }

// RxBytes and TxBytes count what went through the tunnel.
func (t *Tunnel) RxBytes() int64 { return t.stat("rx_bytes") }
func (t *Tunnel) TxBytes() int64 { return t.stat("tx_bytes") }

func (t *Tunnel) stat(key string) int64 {
	t.mu.Lock()
	dev := t.dev
	t.mu.Unlock()
	if dev == nil {
		return 0
	}
	text, err := dev.IpcGet()
	if err != nil {
		return 0
	}
	var total int64
	for _, line := range strings.Split(text, "\n") {
		if k, v, ok := strings.Cut(line, "="); ok && k == key {
			n, _ := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
			if key == "last_handshake_time_sec" {
				if n > total {
					total = n
				}
			} else {
				total += n
			}
		}
	}
	return total
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
