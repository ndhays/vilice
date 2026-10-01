package app

// The certificates this box actually serves, for `status`.
//
// Asked the way a visitor would ask: a TLS handshake to this box's own port 443, one
// per hostname it serves, and a read of the certificate that comes back. Not a read of
// Caddy's storage — that belongs to the caddy user, and would say what Caddy holds
// rather than what it hands out. Unprivileged, local, and bounded by a short timeout.

import (
	"crypto/tls"
	"crypto/x509"
	"net"
	"sort"
	"strings"
	"sync"
	"time"
)

// CertStatus is one hostname's certificate, as served.
type CertStatus struct {
	Host     string `json:"host"`
	NotAfter string `json:"not_after,omitempty"` // RFC 3339
	Issuer   string `json:"issuer,omitempty"`
	Valid    bool   `json:"valid"`           // chains to a trusted root and names this host
	Error    string `json:"error,omitempty"` // the handshake failed, or the cert did not verify
}

const certTimeout = 3 * time.Second

// certAddr is where the handshake goes. A variable so a test can point it at a local
// listener; on a box it is always this box's own HTTPS port.
var certAddr = "127.0.0.1:443"

// servedHosts is every hostname this box answers for: its apps' hostnames, and on a
// balancer the hosts its edge fronts. Sorted and de-duplicated.
func servedHosts() []string {
	seen := map[string]bool{}
	if apps, err := listApps(); err == nil {
		for _, a := range apps {
			for _, h := range a.Hostnames {
				seen[h] = true
			}
		}
	}
	for _, line := range currentRoutes() {
		for _, h := range strings.FieldsFunc(line, func(r rune) bool { return r == ',' || r == ' ' }) {
			seen[h] = true
		}
	}
	hosts := make([]string, 0, len(seen))
	for h := range seen {
		if h != "" {
			hosts = append(hosts, h)
		}
	}
	sort.Strings(hosts)
	return hosts
}

// collectCerts checks every served host at once. Nil when the box serves no hostname.
func collectCerts() []CertStatus {
	hosts := servedHosts()
	if len(hosts) == 0 {
		return nil
	}
	out := make([]CertStatus, len(hosts))
	var wg sync.WaitGroup
	for i, h := range hosts {
		wg.Add(1)
		go func(i int, h string) {
			defer wg.Done()
			out[i] = checkCert(h, nil)
		}(i, h)
	}
	wg.Wait()
	return out
}

// checkCert does one handshake and reports what came back. `roots` nil means the
// system pool — the one a visitor's browser would use.
func checkCert(host string, roots *x509.CertPool) CertStatus {
	st := CertStatus{Host: host}
	dialer := &net.Dialer{Timeout: certTimeout}
	// Verification is done below, by hand, so an untrusted or expired certificate is
	// still read and reported rather than lost in a failed handshake.
	conn, err := tls.DialWithDialer(dialer, "tcp", certAddr, &tls.Config{
		ServerName:         host,
		InsecureSkipVerify: true, // #nosec G402 -- read-only inspection; verified explicitly below
	})
	if err != nil {
		st.Error = err.Error()
		return st
	}
	defer conn.Close()

	chain := conn.ConnectionState().PeerCertificates
	if len(chain) == 0 {
		st.Error = "no certificate served"
		return st
	}
	leaf := chain[0]
	st.NotAfter = leaf.NotAfter.UTC().Format(time.RFC3339)
	st.Issuer = leaf.Issuer.CommonName
	if st.Issuer == "" && len(leaf.Issuer.Organization) > 0 {
		st.Issuer = leaf.Issuer.Organization[0]
	}

	inter := x509.NewCertPool()
	for _, c := range chain[1:] {
		inter.AddCert(c)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{DNSName: host, Roots: roots, Intermediates: inter}); err != nil {
		st.Error = err.Error()
		return st
	}
	st.Valid = true
	return st
}
