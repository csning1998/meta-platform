package vaultops

import (
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	vaultapi "github.com/hashicorp/vault/api"

	"platform/internal/ui"
)

func loadCert(t *testing.T, path string) *x509.Certificate {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	block, _ := pem.Decode(data)
	if block == nil {
		t.Fatalf("no PEM block in %s", path)
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("parse certificate %s: %v", path, err)
	}
	return cert
}

func assertMode(t *testing.T, path string, want os.FileMode) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat %s: %v", path, err)
	}
	if info.Mode().Perm() != want {
		t.Errorf("%s mode = %v, want %v", path, info.Mode().Perm(), want)
	}
}

// fakeEnv is a minimal test-local implementation of the one-method Set(string,string)
// interface TokenSync/Init/Unseal accept. Tests assert on what was recorded.
type fakeEnv struct{ kv map[string]string }

func newFakeEnv() *fakeEnv { return &fakeEnv{kv: map[string]string{}} }

func (e *fakeEnv) Set(k, v string) { e.kv[k] = v }

func discardOut() *ui.Printer { return ui.New(io.Discard, io.Discard) }

// kvv2Handler serves a fake Vault KV-v2 "read" response for exactly one mount/path pair.
func kvv2Handler(t *testing.T, wantPath string, body map[string]interface{}) http.HandlerFunc {
	t.Helper()
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != wantPath {
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"errors":["not found"]}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(body)
	}
}

func newTestVaultClient(t *testing.T, addr string) *vaultapi.Client {
	t.Helper()
	cfg := vaultapi.DefaultConfig()
	cfg.Address = addr
	client, err := vaultapi.NewClient(cfg)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	return client
}

func writePlaybook(t *testing.T, p Paths) {
	t.Helper()
	dir := filepath.Join(p.AnsibleDir, "playbooks")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "operation_playbook.yaml"), []byte("dummy: true\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}
