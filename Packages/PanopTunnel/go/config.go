package tunnel

import (
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"strconv"
	"strings"
)

// parsed is what the userspace device needs from a standard WireGuard .conf.
type parsed struct {
	ipc       string
	addresses []netip.Addr
	dns       []netip.Addr
	mtu       int
}

// parseConfig reads the .conf a provider hands out. Errors name the line, never the value: the private key
// must not reach a log or an error message.
func parseConfig(text string) (*parsed, error) {
	var (
		section              string
		privateKey           string
		peers                int
		publicKey, preshared string
		endpoint, keepalive  string
		allowed              []string
		ipc                  strings.Builder
		out                  = &parsed{mtu: 1280}
		peerOpen             bool
	)
	flushPeer := func() error {
		if !peerOpen {
			return nil
		}
		if publicKey == "" || endpoint == "" || len(allowed) == 0 {
			return errors.New("a [Peer] needs PublicKey, Endpoint and AllowedIPs")
		}
		ipc.WriteString("public_key=" + publicKey + "\n")
		if preshared != "" {
			ipc.WriteString("preshared_key=" + preshared + "\n")
		}
		ipc.WriteString("endpoint=" + endpoint + "\n")
		if keepalive != "" {
			ipc.WriteString("persistent_keepalive_interval=" + keepalive + "\n")
		}
		for _, a := range allowed {
			ipc.WriteString("allowed_ip=" + a + "\n")
		}
		peers++
		publicKey, preshared, endpoint, keepalive, allowed, peerOpen = "", "", "", "", nil, false
		return nil
	}

	for n, raw := range strings.Split(strings.ReplaceAll(text, "\r", ""), "\n") {
		line := strings.TrimSpace(raw)
		if i := strings.IndexByte(line, '#'); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		if line == "" {
			continue
		}
		lineErr := func(msg string) error { return fmt.Errorf("line %d: %s", n+1, msg) }
		if strings.HasPrefix(line, "[") {
			if err := flushPeer(); err != nil {
				return nil, err
			}
			section = strings.ToLower(strings.Trim(line, "[] "))
			if section == "peer" {
				peerOpen = true
			}
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			return nil, lineErr("expected Key = Value")
		}
		key, value = strings.ToLower(strings.TrimSpace(key)), strings.TrimSpace(value)
		switch section {
		case "interface":
			switch key {
			case "privatekey":
				h, err := keyHex(value)
				if err != nil {
					return nil, lineErr("PrivateKey is not a valid key")
				}
				privateKey = h
			case "address":
				for _, p := range strings.Split(value, ",") {
					prefix, err := netip.ParsePrefix(strings.TrimSpace(p))
					if err != nil {
						return nil, lineErr("Address is not valid")
					}
					out.addresses = append(out.addresses, prefix.Addr())
				}
			case "dns":
				for _, p := range strings.Split(value, ",") {
					// A search domain is ignored; only addresses are used.
					if a, err := netip.ParseAddr(strings.TrimSpace(p)); err == nil {
						out.dns = append(out.dns, a)
					}
				}
			case "mtu":
				m, err := strconv.Atoi(value)
				if err != nil || m < 576 || m > 1500 {
					return nil, lineErr("MTU is not valid")
				}
				out.mtu = m
			}
		case "peer":
			switch key {
			case "publickey":
				h, err := keyHex(value)
				if err != nil {
					return nil, lineErr("PublicKey is not a valid key")
				}
				publicKey = h
			case "presharedkey":
				h, err := keyHex(value)
				if err != nil {
					return nil, lineErr("PresharedKey is not a valid key")
				}
				preshared = h
			case "endpoint":
				e, err := resolveEndpoint(value)
				if err != nil {
					return nil, lineErr("Endpoint cannot be resolved")
				}
				endpoint = e
			case "allowedips":
				for _, p := range strings.Split(value, ",") {
					prefix, err := netip.ParsePrefix(strings.TrimSpace(p))
					if err != nil {
						return nil, lineErr("AllowedIPs is not valid")
					}
					allowed = append(allowed, prefix.String())
				}
			case "persistentkeepalive":
				if _, err := strconv.Atoi(value); err != nil {
					return nil, lineErr("PersistentKeepalive is not a number")
				}
				keepalive = value
			}
		}
	}
	if err := flushPeer(); err != nil {
		return nil, err
	}
	if privateKey == "" {
		return nil, errors.New("[Interface] needs a PrivateKey")
	}
	if len(out.addresses) == 0 {
		return nil, errors.New("[Interface] needs an Address")
	}
	if peers != 1 {
		return nil, errors.New("exactly one [Peer] is supported")
	}
	if len(out.dns) == 0 {
		// Names are resolved inside the tunnel; without a server there would be no way to do that.
		return nil, errors.New("[Interface] needs a DNS address")
	}
	out.ipc = "private_key=" + privateKey + "\n" + ipc.String()
	return out, nil
}

func keyHex(b64 string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil || len(raw) != 32 {
		return "", errors.New("bad key")
	}
	return hex.EncodeToString(raw), nil
}

// resolveEndpoint turns host:port into ip:port, because the device's configuration takes addresses only.
// This lookup is the one name resolved outside the tunnel: the tunnel cannot carry its own endpoint's lookup.
func resolveEndpoint(value string) (string, error) {
	host, port, err := net.SplitHostPort(value)
	if err != nil {
		return "", err
	}
	if _, err := netip.ParseAddr(host); err == nil {
		return value, nil
	}
	addrs, err := net.LookupHost(host)
	if err != nil || len(addrs) == 0 {
		return "", errors.New("lookup failed")
	}
	return net.JoinHostPort(addrs[0], port), nil
}
