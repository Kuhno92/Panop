package tunnel

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
	"testing"
	"time"

	"golang.org/x/crypto/curve25519"
	"golang.org/x/net/proxy"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

func keypair(t *testing.T) (priv, pub [32]byte) {
	t.Helper()
	if _, err := rand.Read(priv[:]); err != nil {
		t.Fatal(err)
	}
	priv[0] &= 248
	priv[31] = (priv[31] & 127) | 64
	p, err := curve25519.X25519(priv[:], curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	copy(pub[:], p)
	return
}

// startServer is a stand-in for the VPN provider: a WireGuard peer on loopback UDP that serves one page at
// 10.9.0.1:80, reachable only through the tunnel.
func startServer(t *testing.T, serverPriv, clientPub [32]byte) (port int) {
	t.Helper()
	tunDev, tnet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.9.0.1")}, []netip.Addr{netip.MustParseAddr("10.9.0.1")}, 1280)
	if err != nil {
		t.Fatal(err)
	}
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	t.Cleanup(dev.Close)
	conf := fmt.Sprintf("private_key=%s\nlisten_port=0\npublic_key=%s\nallowed_ip=10.9.0.2/32\n",
		hex.EncodeToString(serverPriv[:]), hex.EncodeToString(clientPub[:]))
	if err := dev.IpcSet(conf); err != nil {
		t.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		t.Fatal(err)
	}
	l, err := tnet.ListenTCP(&net.TCPAddr{Port: 80})
	if err != nil {
		t.Fatal(err)
	}
	serveDNS(t, tnet)
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "through the tunnel to "+r.Host)
	})
	mux.HandleFunc("/redirect", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/final.ts", http.StatusFound)
	})
	mux.HandleFunc("/final.ts", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "video/mp2t")
		io.WriteString(w, "TS-BYTES user-agent="+r.Header.Get("User-Agent"))
	})
	mux.HandleFunc("/live/index.m3u8", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
		// ServeContent honours Range, as the real servers do (VLC asks for "bytes=0-" and gets a 206).
		http.ServeContent(w, r, "index.m3u8", time.Unix(0, 0), strings.NewReader("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXTINF:4,\nseg1.ts\n#EXTINF:4,\nhttp://10.9.0.1/live/abs.ts?token=a&b=1\n#EXT-X-ENDLIST\n"))
	})
	mux.HandleFunc("/live/seg1.ts", func(w http.ResponseWriter, r *http.Request) {
		http.ServeContent(w, r, "seg1.ts", time.Unix(0, 0), strings.NewReader("0123456789"))
	})
	go http.Serve(l, mux)
	text, _ := dev.IpcGet()
	for _, line := range strings.Split(text, "\n") {
		if v, ok := strings.CutPrefix(line, "listen_port="); ok {
			fmt.Sscanf(v, "%d", &port)
		}
	}
	return port
}

func startClient(t *testing.T) *Tunnel {
	t.Helper()
	serverPriv, serverPub := keypair(t)
	clientPriv, clientPub := keypair(t)
	port := startServer(t, serverPriv, clientPub)
	conf := fmt.Sprintf(`[Interface]
PrivateKey = %s
Address = 10.9.0.2/32
DNS = 10.9.0.1

[Peer]
PublicKey = %s
AllowedIPs = 10.9.0.0/24
Endpoint = 127.0.0.1:%d
PersistentKeepalive = 25
`, base64.StdEncoding.EncodeToString(clientPriv[:]), base64.StdEncoding.EncodeToString(serverPub[:]), port)
	tun := NewTunnel()
	if err := tun.Start(conf); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(tun.Stop)
	return tun
}

func TestHTTPProxyReachesThePeerOnlyThroughTheTunnel(t *testing.T) {
	tun := startClient(t)
	proxyURL, _ := url.Parse(fmt.Sprintf("http://%s:%s@127.0.0.1:%d", tun.Username(), tun.Password(), tun.HTTPPort()))
	client := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)}, Timeout: 10 * time.Second}
	resp, err := client.Get("http://10.9.0.1/")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if !strings.HasPrefix(string(body), "through the tunnel") {
		t.Fatalf("unexpected body %q", body)
	}
	if tun.LastHandshakeUnix() == 0 || tun.RxBytes() == 0 || tun.TxBytes() == 0 {
		t.Fatalf("no handshake or traffic counted: %d %d %d", tun.LastHandshakeUnix(), tun.RxBytes(), tun.TxBytes())
	}
}

func TestSOCKS5ReachesThePeerAndRefusesWrongCredentials(t *testing.T) {
	tun := startClient(t)
	addr := fmt.Sprintf("127.0.0.1:%d", tun.SocksPort())
	d, err := proxy.SOCKS5("tcp", addr, &proxy.Auth{User: tun.Username(), Password: tun.Password()}, proxy.Direct)
	if err != nil {
		t.Fatal(err)
	}
	client := &http.Client{Transport: &http.Transport{Dial: d.Dial}, Timeout: 10 * time.Second}
	resp, err := client.Get("http://10.9.0.1/")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.HasPrefix(string(body), "through the tunnel") {
		t.Fatalf("unexpected body %q", body)
	}

	bad, _ := proxy.SOCKS5("tcp", addr, &proxy.Auth{User: "x", Password: "y"}, proxy.Direct)
	if c, err := bad.Dial("tcp", "10.9.0.1:80"); err == nil {
		c.Close()
		t.Fatal("wrong credentials were accepted")
	}
}

func TestHTTPProxyRefusesWithoutCredentials(t *testing.T) {
	tun := startClient(t)
	client := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(&url.URL{Scheme: "http", Host: fmt.Sprintf("127.0.0.1:%d", tun.HTTPPort())})}, Timeout: 5 * time.Second}
	resp, err := client.Get("http://10.9.0.1/")
	if err == nil {
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusProxyAuthRequired {
			t.Fatalf("status %d", resp.StatusCode)
		}
	}
}

func TestNothingLeavesTheTunnelToTheLocalNetwork(t *testing.T) {
	tun := startClient(t)
	// A server on this machine that must never be reached: the destination is resolved and dialled inside the tunnel.
	direct, _ := net.Listen("tcp", "127.0.0.1:0")
	defer direct.Close()
	hit := make(chan struct{}, 1)
	go func() {
		if c, err := direct.Accept(); err == nil {
			hit <- struct{}{}
			c.Close()
		}
	}()
	d, _ := proxy.SOCKS5("tcp", fmt.Sprintf("127.0.0.1:%d", tun.SocksPort()), &proxy.Auth{User: tun.Username(), Password: tun.Password()}, proxy.Direct)
	if c, err := d.Dial("tcp", direct.Addr().String()); err == nil {
		c.Close()
	}
	select {
	case <-hit:
		t.Fatal("the proxy reached a local address directly")
	case <-time.After(1500 * time.Millisecond):
	}
}

func TestConfigErrorsNameTheLineNotTheKey(t *testing.T) {
	_, err := parseConfig("[Interface]\nPrivateKey = not-a-key-SECRETVALUE\n")
	if err == nil || strings.Contains(err.Error(), "SECRETVALUE") {
		t.Fatalf("error %v", err)
	}
	if !strings.Contains(err.Error(), "line 2") {
		t.Fatalf("no line number in %v", err)
	}
	for name, conf := range map[string]string{
		"no peer":    "[Interface]\nPrivateKey = " + base64.StdEncoding.EncodeToString(make([]byte, 32)) + "\nAddress = 10.0.0.2/32\nDNS = 1.1.1.1\n",
		"no address": "[Interface]\nPrivateKey = " + base64.StdEncoding.EncodeToString(make([]byte, 32)) + "\nDNS = 1.1.1.1\n",
	} {
		if _, err := parseConfig(conf); err == nil {
			t.Errorf("%s was accepted", name)
		}
	}
}

// serveDNS answers every UDP packet on port 53 with its own header marked as a response, which is all the
// readiness probe needs.
func serveDNS(t *testing.T, tnet *netstack.Net) {
	t.Helper()
	pc, err := tnet.ListenUDP(&net.UDPAddr{Port: 53})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { pc.Close() })
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
}

func TestWaitReadyReturnsOnceTheServerAnswers(t *testing.T) {
	tun := startClient(t)
	if err := tun.WaitReady(10); err != nil {
		t.Fatal(err)
	}
}

func TestWaitReadyGivesUpWhenNothingAnswers(t *testing.T) {
	_, pub := keypair(t)
	priv, _ := keypair(t)
	tun := NewTunnel()
	conf := fmt.Sprintf("[Interface]\nPrivateKey = %s\nAddress = 10.9.0.2/32\nDNS = 10.9.0.1\n\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.9.0.0/24\nEndpoint = 127.0.0.1:9\n",
		base64.StdEncoding.EncodeToString(priv[:]), base64.StdEncoding.EncodeToString(pub[:]))
	if err := tun.Start(conf); err != nil {
		t.Fatal(err)
	}
	defer tun.Stop()
	if err := tun.WaitReady(2); err == nil {
		t.Fatal("reported ready with no server")
	}
}

// relayFetch asks the relay for an upstream address, without following redirects.
func relayFetch(t *testing.T, tun *Tunnel, upstream string, header map[string]string) (*http.Response, string) {
	t.Helper()
	u, _ := url.Parse(upstream)
	r := newRelay(tun.RelaySecret(), nil)
	address := r.address(fmt.Sprintf("127.0.0.1:%d", tun.RelayPort()), u)
	return relayGet(t, address, header)
}

func relayGet(t *testing.T, address string, header map[string]string) (*http.Response, string) {
	t.Helper()
	req, _ := http.NewRequest("GET", address, nil)
	for k, v := range header {
		req.Header.Set(k, v)
	}
	client := &http.Client{Timeout: 15 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp, string(b)
}

func TestRelayFetchesThroughTheTunnelAndPassesHeaders(t *testing.T) {
	tun := startClient(t)
	resp, body := relayFetch(t, tun, "http://10.9.0.1/final.ts", map[string]string{"User-Agent": "TestPlayer/1"})
	if resp.StatusCode != 200 || body != "TS-BYTES user-agent=TestPlayer/1" {
		t.Fatalf("%d %q", resp.StatusCode, body)
	}
	if resp.Header.Get("Content-Type") != "video/mp2t" {
		t.Fatalf("content type %q", resp.Header.Get("Content-Type"))
	}
}

func TestRelayHandsRedirectsBackThroughItself(t *testing.T) {
	tun := startClient(t)
	resp, _ := relayFetch(t, tun, "http://10.9.0.1/redirect", nil)
	loc := resp.Header.Get("Location")
	if resp.StatusCode != 302 || !strings.HasPrefix(loc, fmt.Sprintf("http://127.0.0.1:%d/", tun.RelayPort())) {
		t.Fatalf("%d %q", resp.StatusCode, loc)
	}
	_, body := relayGet(t, loc, nil)
	if !strings.HasPrefix(body, "TS-BYTES") {
		t.Fatalf("followed redirect gave %q", body)
	}
}

func TestRelayRewritesAPlaylistSoSegmentsComeBackThroughIt(t *testing.T) {
	tun := startClient(t)
	_, playlist := relayFetch(t, tun, "http://10.9.0.1/live/index.m3u8", nil)
	prefix := fmt.Sprintf("http://127.0.0.1:%d/", tun.RelayPort())
	var segment, absolute, key string
	for _, line := range strings.Split(playlist, "\n") {
		switch {
		case strings.HasPrefix(line, "#EXT-X-KEY"):
			key = line
		case strings.HasPrefix(line, prefix) && strings.HasSuffix(line, "/seg1.ts"):
			segment = line
		case strings.HasPrefix(line, prefix) && strings.Contains(line, "abs.ts"):
			absolute = line
		case line != "" && !strings.HasPrefix(line, "#"):
			t.Fatalf("a line was left pointing past the relay: %q", line)
		}
	}
	if segment == "" || absolute == "" || !strings.Contains(key, `URI="`+prefix) {
		t.Fatalf("not rewritten:\n%s", playlist)
	}
	if strings.Contains(playlist, "10.9.0.1") {
		t.Fatalf("the upstream address is still in the playlist:\n%s", playlist)
	}
	_, body := relayGet(t, segment, nil)
	if body != "0123456789" {
		t.Fatalf("segment %q", body)
	}
	_, abs := relayGet(t, absolute, nil)
	if !strings.HasPrefix(abs, "through the tunnel") {
		t.Fatalf("absolute segment %q", abs)
	}
}

func TestRelayPassesRanges(t *testing.T) {
	tun := startClient(t)
	resp, body := relayFetch(t, tun, "http://10.9.0.1/live/seg1.ts", map[string]string{"Range": "bytes=2-5"})
	if resp.StatusCode != 206 || body != "2345" || resp.Header.Get("Content-Range") != "bytes 2-5/10" {
		t.Fatalf("%d %q %q", resp.StatusCode, body, resp.Header.Get("Content-Range"))
	}
}

func TestRelayRefusesAWrongSecretAndOtherSchemes(t *testing.T) {
	tun := startClient(t)
	u, _ := url.Parse("http://10.9.0.1/final.ts")
	wrong := newRelay("not-the-secret", nil).address(fmt.Sprintf("127.0.0.1:%d", tun.RelayPort()), u)
	if resp, _ := relayGet(t, wrong, nil); resp.StatusCode != 404 {
		t.Fatalf("wrong secret gave %d", resp.StatusCode)
	}
	file, _ := url.Parse("file:///etc/hosts")
	bad := newRelay(tun.RelaySecret(), nil).address(fmt.Sprintf("127.0.0.1:%d", tun.RelayPort()), file)
	if resp, _ := relayGet(t, bad, nil); resp.StatusCode != 404 {
		t.Fatalf("a file address gave %d", resp.StatusCode)
	}
}

func TestRelayAnswersARangedPlaylistWhole(t *testing.T) {
	tun := startClient(t)
	resp, body := relayFetch(t, tun, "http://10.9.0.1/live/index.m3u8", map[string]string{"Range": "bytes=0-"})
	if resp.StatusCode != 200 || resp.Header.Get("Content-Range") != "" {
		t.Fatalf("%d %q", resp.StatusCode, resp.Header.Get("Content-Range"))
	}
	if !strings.HasPrefix(body, "#EXTM3U") || strings.Contains(body, "10.9.0.1/live") {
		t.Fatalf("%q", body)
	}
}
