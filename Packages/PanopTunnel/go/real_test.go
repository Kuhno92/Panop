package tunnel

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"testing"
	"time"

	"golang.org/x/net/proxy"
)

// TestRealProvider runs against a real WireGuard file (PANOP_WG_CONF), e.g. a Proton download kept in .secrets.
// It prints the exit address, never the file.
func TestRealProvider(t *testing.T) {
	path := os.Getenv("PANOP_WG_CONF")
	if path == "" {
		t.Skip("PANOP_WG_CONF not set")
	}
	text, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	tun := NewTunnel()
	if err := tun.Start(string(text)); err != nil {
		t.Fatal(err)
	}
	defer tun.Stop()
	start := time.Now()
	if err := tun.WaitReady(20); err != nil {
		t.Fatal(err)
	}
	t.Logf("ready after %v", time.Since(start))

	get := func(c *http.Client) string {
		resp, err := c.Get("https://api.ipify.org")
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		b, _ := io.ReadAll(resp.Body)
		return string(b)
	}
	pu, _ := url.Parse(fmt.Sprintf("http://%s:%s@127.0.0.1:%d", tun.Username(), tun.Password(), tun.HTTPPort()))
	t.Logf("exit via HTTP proxy:  %s", get(&http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(pu)}, Timeout: 20 * time.Second}))
	d, _ := proxy.SOCKS5("tcp", fmt.Sprintf("127.0.0.1:%d", tun.SocksPort()), &proxy.Auth{User: tun.Username(), Password: tun.Password()}, proxy.Direct)
	t.Logf("exit via SOCKS5:      %s", get(&http.Client{Transport: &http.Transport{Dial: d.Dial}, Timeout: 20 * time.Second}))
	t.Logf("direct (no tunnel):   %s", get(&http.Client{Timeout: 20 * time.Second}))
	t.Logf("handshake %d, rx %d, tx %d", tun.LastHandshakeUnix(), tun.RxBytes(), tun.TxBytes())

	// Throughput: pull 20 MB through the tunnel.
	t0 := time.Now()
	resp, err := (&http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(pu)}, Timeout: 60 * time.Second}).Get("https://speed.cloudflare.com/__down?bytes=20000000")
	if err == nil {
		n, _ := io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		t.Logf("downloaded %d bytes in %v = %.1f Mbit/s", n, time.Since(t0), float64(n)*8/time.Since(t0).Seconds()/1e6)
	} else {
		t.Logf("throughput probe failed: %v", err)
	}
}
