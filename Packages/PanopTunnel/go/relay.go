package tunnel

import (
	"bufio"
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/base64"
	"io"
	"net/http"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// The relay is for players that cannot be given a proxy (AVPlayer, VLC, AetherEngine). They are given an address on
// 127.0.0.1 instead:
//
//	http://127.0.0.1:<port>/<secret>/<base64url of the real address>/<name>
//
// and the relay fetches the real address through the tunnel. The secret is random for each run, so no other app on
// the device can use the relay as a way out; the name is only there so the player still sees ".m3u8" or ".ts".
//
// An HLS playlist is rewritten as it passes, so its segments, keys and variants come back through the relay too.
// Redirects are not followed here but handed to the player with the address rewritten, so every hop stays inside.
type relay struct {
	secret    string
	transport *http.Transport
}

func newRelay(secret string, dial dialer) *relay {
	return &relay{
		secret: secret,
		transport: &http.Transport{
			DialContext:           dial,
			DisableCompression:    true,
			MaxIdleConnsPerHost:   4,
			IdleConnTimeout:       30 * time.Second,
			TLSHandshakeTimeout:   15 * time.Second,
			ResponseHeaderTimeout: 30 * time.Second,
		},
	}
}

func (r *relay) server() *http.Server {
	return &http.Server{ReadHeaderTimeout: 15 * time.Second, Handler: http.HandlerFunc(r.handle)}
}

// relayAddress is the address a player is given for an upstream address.
func (r *relay) address(host string, upstream *url.URL) string {
	name := path.Base(upstream.Path)
	if name == "" || name == "." || name == "/" {
		name = "stream"
	}
	encoded := base64.RawURLEncoding.EncodeToString([]byte(upstream.String()))
	return "http://" + host + "/" + r.secret + "/" + encoded + "/" + url.PathEscape(name)
}

func (r *relay) handle(w http.ResponseWriter, req *http.Request) {
	parts := strings.SplitN(strings.TrimPrefix(req.URL.EscapedPath(), "/"), "/", 3)
	if len(parts) < 2 || subtle.ConstantTimeCompare([]byte(parts[0]), []byte(r.secret)) != 1 {
		http.NotFound(w, req)
		return
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		http.NotFound(w, req)
		return
	}
	upstream, err := url.Parse(string(raw))
	if err != nil || (upstream.Scheme != "http" && upstream.Scheme != "https") || upstream.Host == "" {
		http.NotFound(w, req)
		return
	}

	ctx, cancel := context.WithCancel(req.Context())
	defer cancel()
	out, err := http.NewRequestWithContext(ctx, req.Method, upstream.String(), req.Body)
	if err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	for name, values := range req.Header {
		if isHop(name) || strings.EqualFold(name, "Host") || strings.EqualFold(name, "Accept-Encoding") {
			continue
		}
		out.Header[name] = values
	}
	out.Header.Set("Accept-Encoding", "identity")

	resp, err := r.transport.RoundTrip(out)
	if err != nil {
		http.Error(w, "bad gateway", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	host := req.Host
	header := w.Header()
	for name, values := range resp.Header {
		if isHop(name) {
			continue
		}
		header[name] = values
	}
	// A redirect is the player's to follow, back through the relay.
	if resp.StatusCode >= 300 && resp.StatusCode < 400 {
		if location, err := resp.Location(); err == nil {
			header.Set("Location", r.address(host, location))
		}
		w.WriteHeader(resp.StatusCode)
		return
	}

	body := bufio.NewReaderSize(resp.Body, 64*1024)
	if head, _ := body.Peek(7); string(head) == "#EXTM3U" && req.Method != http.MethodHead {
		playlist, err := io.ReadAll(io.LimitReader(body, 8<<20))
		if err != nil {
			http.Error(w, "bad gateway", http.StatusBadGateway)
			return
		}
		rewritten := r.rewritePlaylist(string(playlist), resp.Request.URL, host)
		// The body is no longer the bytes that were asked for, so it goes whole: a player that asked for "bytes=0-"
		// of a playlist (VLC does) is answered 200, not a 206 whose range no longer describes it.
		header.Del("Content-Range")
		header.Del("Etag")
		header.Set("Content-Length", strconv.Itoa(len(rewritten)))
		status := resp.StatusCode
		if status == http.StatusPartialContent {
			status = http.StatusOK
		}
		w.WriteHeader(status)
		_, _ = io.WriteString(w, rewritten)
		return
	}

	w.WriteHeader(resp.StatusCode)
	if req.Method == http.MethodHead {
		return
	}
	// A live stream has no end: flush as it arrives rather than buffering.
	flusher, _ := w.(http.Flusher)
	buffer := make([]byte, 32*1024)
	for {
		n, err := body.Read(buffer)
		if n > 0 {
			if _, werr := w.Write(buffer[:n]); werr != nil {
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

var uriAttribute = regexp.MustCompile(`URI="([^"]*)"`)

// rewritePlaylist points every address in an HLS playlist at the relay: the lines that are addresses (variants,
// segments) and the URI="..." attributes of tags (keys, init segments, renditions). Relative addresses are resolved
// against the playlist's own address first.
func (r *relay) rewritePlaylist(text string, base *url.URL, host string) string {
	resolve := func(reference string) string {
		parsed, err := url.Parse(strings.TrimSpace(reference))
		if err != nil {
			return reference
		}
		target := base.ResolveReference(parsed)
		if target.Scheme != "http" && target.Scheme != "https" {
			return reference
		}
		return r.address(host, target)
	}
	var out bytes.Buffer
	for _, line := range strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n") {
		trimmed := strings.TrimSpace(line)
		switch {
		case trimmed == "":
		case strings.HasPrefix(trimmed, "#"):
			line = uriAttribute.ReplaceAllStringFunc(line, func(match string) string {
				inner := uriAttribute.FindStringSubmatch(match)[1]
				if strings.HasPrefix(inner, "data:") {
					return match
				}
				return `URI="` + resolve(inner) + `"`
			})
		default:
			line = resolve(trimmed)
		}
		out.WriteString(line)
		out.WriteString("\n")
	}
	return out.String()
}
