// Package tunnel runs a WireGuard peer inside the app's own process, with no virtual network interface and
// no system VPN: traffic is handed in through two proxies on 127.0.0.1 (SOCKS5 and HTTP) and leaves through
// the tunnel. Panop points its own connections at those proxies; nothing else on the device is touched.
package tunnel

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

// Tunnel is one running peer. Exposed to Swift through gomobile, so only simple types cross the boundary.
type Tunnel struct {
	mu        sync.Mutex
	dev       *device.Device
	socks     net.Listener
	httpL     net.Listener
	httpSrv   *http.Server
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
	t.dev, t.socks, t.httpL = dev, socks, httpL
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
	t.dev.Close()
	t.dev, t.socks, t.httpL, t.httpSrv = nil, nil, nil, nil
	t.socksPort, t.httpPort = 0, 0
}

func (t *Tunnel) SocksPort() int   { t.mu.Lock(); defer t.mu.Unlock(); return t.socksPort }
func (t *Tunnel) HTTPPort() int    { t.mu.Lock(); defer t.mu.Unlock(); return t.httpPort }
func (t *Tunnel) Username() string { t.mu.Lock(); defer t.mu.Unlock(); return t.user }
func (t *Tunnel) Password() string { t.mu.Lock(); defer t.mu.Unlock(); return t.pass }

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
