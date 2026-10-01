package app

import (
	"crypto/x509"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// The check reads the certificate a visitor would get, and verifies it separately, so
// an untrusted one is still reported — with its expiry — rather than lost.
func TestCheckCertReadsWhatIsServed(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	defer srv.Close()
	old := certAddr
	certAddr = strings.TrimPrefix(srv.URL, "https://")
	defer func() { certAddr = old }()

	roots := x509.NewCertPool()
	roots.AddCert(srv.Certificate())

	// httptest's certificate names example.com; trusted by these roots, it verifies.
	ok := checkCert("example.com", roots)
	if !ok.Valid || ok.NotAfter == "" || ok.Error != "" {
		t.Fatalf("want a valid cert with an expiry, got %+v", ok)
	}

	// Asked for a name it does not carry: still read, reported not valid.
	wrong := checkCert("other.test", roots)
	if wrong.Valid || wrong.NotAfter == "" || wrong.Error == "" {
		t.Errorf("want read-but-invalid, got %+v", wrong)
	}

	// Untrusted by the system pool: read, not valid.
	if st := checkCert("example.com", nil); st.Valid || st.NotAfter == "" {
		t.Errorf("want read-but-untrusted, got %+v", st)
	}
}

func TestCheckCertReportsNothingListening(t *testing.T) {
	old := certAddr
	certAddr = "127.0.0.1:1" // nothing listens on port 1
	defer func() { certAddr = old }()
	st := checkCert("example.com", nil)
	if st.Valid || st.Error == "" || st.NotAfter != "" {
		t.Errorf("want an error and no cert, got %+v", st)
	}
}
