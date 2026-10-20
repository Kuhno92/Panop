package tunnel

import (
	"context"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type dialer func(ctx context.Context, network, address string) (net.Conn, error)

// pipe copies both ways until either side ends, then closes both.
func pipe(a, b net.Conn) {
	done := make(chan struct{}, 2)
	cp := func(dst, src net.Conn) {
		_, _ = io.Copy(dst, src)
		done <- struct{}{}
	}
	go cp(a, b)
	go cp(b, a)
	<-done
	_ = a.Close()
	_ = b.Close()
	<-done
}

// serveSOCKS5 accepts CONNECT with a username and password, and resolves names through dial (so inside the tunnel).
func serveSOCKS5(l net.Listener, user, pass string, dial dialer) {
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		go handleSOCKS5(c, user, pass, dial)
	}
}

func handleSOCKS5(c net.Conn, user, pass string, dial dialer) {
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(15 * time.Second))
	head := make([]byte, 2)
	if _, err := io.ReadFull(c, head); err != nil || head[0] != 5 {
		return
	}
	methods := make([]byte, head[1])
	if _, err := io.ReadFull(c, methods); err != nil {
		return
	}
	hasAuth := false
	for _, m := range methods {
		hasAuth = hasAuth || m == 2
	}
	if !hasAuth {
		_, _ = c.Write([]byte{5, 0xFF})
		return
	}
	_, _ = c.Write([]byte{5, 2})

	ver := make([]byte, 1)
	if _, err := io.ReadFull(c, ver); err != nil || ver[0] != 1 {
		return
	}
	u, err := readLenPrefixed(c)
	if err != nil {
		return
	}
	p, err := readLenPrefixed(c)
	if err != nil {
		return
	}
	if subtle.ConstantTimeCompare(u, []byte(user))&subtle.ConstantTimeCompare(p, []byte(pass)) != 1 {
		_, _ = c.Write([]byte{1, 1})
		return
	}
	_, _ = c.Write([]byte{1, 0})

	req := make([]byte, 4)
	if _, err := io.ReadFull(c, req); err != nil || req[0] != 5 {
		return
	}
	if req[1] != 1 {
		reply(c, 7)
		return
	}
	var host string
	switch req[3] {
	case 1:
		b := make([]byte, 4)
		if _, err := io.ReadFull(c, b); err != nil {
			return
		}
		host = net.IP(b).String()
	case 4:
		b := make([]byte, 16)
		if _, err := io.ReadFull(c, b); err != nil {
			return
		}
		host = net.IP(b).String()
	case 3:
		b, err := readLenPrefixed(c)
		if err != nil {
			return
		}
		host = string(b)
	default:
		reply(c, 8)
		return
	}
	pb := make([]byte, 2)
	if _, err := io.ReadFull(c, pb); err != nil {
		return
	}
	port := int(pb[0])<<8 | int(pb[1])

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	remote, err := dial(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		reply(c, 4)
		return
	}
	reply(c, 0)
	_ = c.SetDeadline(time.Time{})
	pipe(c, remote)
}

func readLenPrefixed(c net.Conn) ([]byte, error) {
	n := make([]byte, 1)
	if _, err := io.ReadFull(c, n); err != nil {
		return nil, err
	}
	b := make([]byte, n[0])
	_, err := io.ReadFull(c, b)
	return b, err
}

func reply(c net.Conn, code byte) {
	_, _ = c.Write([]byte{5, code, 0, 1, 0, 0, 0, 0, 0, 0})
}

// newHTTPProxy serves CONNECT (for https) and absolute-URI requests (for http), with Basic proxy credentials.
func newHTTPProxy(user, pass string, dial dialer) *http.Server {
	transport := &http.Transport{
		DialContext:           dial,
		DisableCompression:    true,
		MaxIdleConnsPerHost:   4,
		IdleConnTimeout:       30 * time.Second,
		ResponseHeaderTimeout: 30 * time.Second,
	}
	want := "Basic " + base64.StdEncoding.EncodeToString([]byte(user+":"+pass))
	return &http.Server{
		ReadHeaderTimeout: 15 * time.Second,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if subtle.ConstantTimeCompare([]byte(r.Header.Get("Proxy-Authorization")), []byte(want)) != 1 {
				w.Header().Set("Proxy-Authenticate", `Basic realm="panop"`)
				http.Error(w, "proxy authentication required", http.StatusProxyAuthRequired)
				return
			}
			if r.Method == http.MethodConnect {
				connect(w, r, dial)
				return
			}
			forward(w, r, transport)
		}),
	}
}

func connect(w http.ResponseWriter, r *http.Request, dial dialer) {
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	remote, err := dial(ctx, "tcp", r.Host)
	if err != nil {
		http.Error(w, "bad gateway", http.StatusBadGateway)
		return
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		_ = remote.Close()
		return
	}
	client, _, err := hj.Hijack()
	if err != nil {
		_ = remote.Close()
		return
	}
	_, _ = client.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
	pipe(client, remote)
}

var hopHeaders = []string{"Connection", "Proxy-Connection", "Proxy-Authorization", "Keep-Alive", "Te", "Trailer", "Transfer-Encoding", "Upgrade"}

func forward(w http.ResponseWriter, r *http.Request, transport *http.Transport) {
	if !r.URL.IsAbs() || (r.URL.Scheme != "http") {
		http.Error(w, "absolute http URL expected", http.StatusBadRequest)
		return
	}
	out := r.Clone(r.Context())
	out.RequestURI = ""
	for _, h := range hopHeaders {
		out.Header.Del(h)
	}
	resp, err := transport.RoundTrip(out)
	if err != nil {
		status := http.StatusBadGateway
		if errors.Is(err, context.Canceled) {
			status = 499
		}
		http.Error(w, "bad gateway", status)
		return
	}
	defer resp.Body.Close()
	for k, v := range resp.Header {
		if isHop(k) {
			continue
		}
		w.Header()[k] = v
	}
	w.WriteHeader(resp.StatusCode)
	// A live stream has no end: flush as it arrives rather than buffering.
	flusher, _ := w.(http.Flusher)
	buf := make([]byte, 32*1024)
	for {
		n, err := resp.Body.Read(buf)
		if n > 0 {
			if _, werr := w.Write(buf[:n]); werr != nil {
				return
			}
			if flusher != nil {
				flusher.Flush()
			}
		}
		if err != nil {
			return
		}
	}
}

func isHop(h string) bool {
	for _, x := range hopHeaders {
		if strings.EqualFold(x, h) {
			return true
		}
	}
	return false
}
