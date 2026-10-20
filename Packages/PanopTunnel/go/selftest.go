//go:build selftest

package tunnel

// SelfTest is compiled only into the spike/test build of the framework. It starts a stand-in VPN server and
// the real client in this process and fetches a page through both proxies, so the whole WireGuard path is
// proven on the platform it runs on (including tvOS). It returns "" when everything worked.

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"time"

	"golang.org/x/crypto/curve25519"
	"golang.org/x/net/proxy"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

func selfKeypair() (priv, pub [32]byte) {
	_, _ = rand.Read(priv[:])
	priv[0] &= 248
	priv[31] = (priv[31] & 127) | 64
	p, _ := curve25519.X25519(priv[:], curve25519.Basepoint)
	copy(pub[:], p)
	return
}

func SelfTest() string {
	serverPriv, serverPub := selfKeypair()
	clientPriv, clientPub := selfKeypair()

	tunDev, tnet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.9.0.1")}, []netip.Addr{netip.MustParseAddr("10.9.0.1")}, 1280)
	if err != nil {
		return "server netstack: " + err.Error()
	}
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	defer dev.Close()
	conf := fmt.Sprintf("private_key=%s\nlisten_port=0\npublic_key=%s\nallowed_ip=10.9.0.2/32\n",
		hex.EncodeToString(serverPriv[:]), hex.EncodeToString(clientPub[:]))
	if err := dev.IpcSet(conf); err != nil {
		return "server config: " + err.Error()
	}
	if err := dev.Up(); err != nil {
		return "server up: " + err.Error()
	}
	l, err := tnet.ListenTCP(&net.TCPAddr{Port: 80})
	if err != nil {
		return "server listen: " + err.Error()
	}
	pc, err := tnet.ListenUDP(&net.UDPAddr{Port: 53})
	if err != nil {
		return "server dns: " + err.Error()
	}
	defer pc.Close()
	go func() {
		buf := make([]byte, 512)
		for {
			n, addr, err := pc.ReadFrom(buf)
			if err != nil {
				return
			}
			if n >= 12 {
				buf[2] |= 0x80
				pc.WriteTo(buf[:n], addr)
			}
		}
	}()
	go http.Serve(l, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "through the tunnel") }))
	var port int
	text, _ := dev.IpcGet()
	for _, line := range strings.Split(text, "\n") {
		if v, ok := strings.CutPrefix(line, "listen_port="); ok {
			fmt.Sscanf(v, "%d", &port)
		}
	}

	t := NewTunnel()
	if err := t.Start(fmt.Sprintf("[Interface]\nPrivateKey = %s\nAddress = 10.9.0.2/32\nDNS = 10.9.0.1\n\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.9.0.0/24\nEndpoint = 127.0.0.1:%d\nPersistentKeepalive = 25\n",
		base64.StdEncoding.EncodeToString(clientPriv[:]), base64.StdEncoding.EncodeToString(serverPub[:]), port)); err != nil {
		return "client start: " + err.Error()
	}
	defer t.Stop()
	if err := t.WaitReady(10); err != nil {
		return "ready: " + err.Error()
	}

	check := func(name string, c *http.Client) string {
		resp, err := c.Get("http://10.9.0.1/")
		if err != nil {
			return name + ": " + err.Error()
		}
		defer resp.Body.Close()
		b, _ := io.ReadAll(resp.Body)
		if string(b) != "through the tunnel" {
			return name + ": unexpected body"
		}
		return ""
	}
	proxyURL, _ := url.Parse(fmt.Sprintf("http://%s:%s@127.0.0.1:%d", t.Username(), t.Password(), t.HTTPPort()))
	if r := check("http proxy", &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)}, Timeout: 15 * time.Second}); r != "" {
		return r
	}
	d, _ := proxy.SOCKS5("tcp", fmt.Sprintf("127.0.0.1:%d", t.SocksPort()), &proxy.Auth{User: t.Username(), Password: t.Password()}, proxy.Direct)
	if r := check("socks5", &http.Client{Transport: &http.Transport{Dial: d.Dial}, Timeout: 15 * time.Second}); r != "" {
		return r
	}
	if t.LastHandshakeUnix() == 0 || t.RxBytes() == 0 {
		return "no handshake or traffic counted"
	}
	return ""
}
