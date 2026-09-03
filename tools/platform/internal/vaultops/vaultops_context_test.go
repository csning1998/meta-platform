package vaultops

import (
	"context"
	"os"
	"testing"
)

func TestContextHandlerNonProdRootTokenFileMissing(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	p := Paths{ProjectRoot: root, Home: home}

	addr, token, caCert, err := ResolveContext(context.Background(), p, "dev", "https://prod.example")
	if err != nil {
		t.Fatalf("ContextHandler: %v", err)
	}
	if addr != BastionVaultAddr {
		t.Errorf("addr = %q, want %q", addr, BastionVaultAddr)
	}
	if token != "" {
		t.Errorf("token = %q, want empty", token)
	}
	if caCert != p.resolveCACertFile() {
		t.Errorf("caCert = %q, want %q", caCert, p.resolveCACertFile())
	}
}

func TestContextHandlerNonProdTrimsToken(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	p := Paths{ProjectRoot: root, Home: home}
	if err := os.WriteFile(p.resolveRootTokenFile(), []byte("  s.dev-token  \n"), 0o600); err != nil {
		t.Fatal(err)
	}

	addr, token, caCert, err := ResolveContext(context.Background(), p, "dev", "https://prod.example")
	if err != nil {
		t.Fatalf("ContextHandler: %v", err)
	}
	if addr != BastionVaultAddr {
		t.Errorf("addr = %q, want %q", addr, BastionVaultAddr)
	}
	if token != "s.dev-token" {
		t.Errorf("token = %q, want s.dev-token", token)
	}
	if caCert != p.resolveCACertFile() {
		t.Errorf("caCert = %q, want %q", caCert, p.resolveCACertFile())
	}
}

func TestContextHandlerProdBastionTokenMissing(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	p := Paths{ProjectRoot: root, Home: home}
	prodAddr := "https://prod.example"

	addr, token, caCert, err := ResolveContext(context.Background(), p, "prod", prodAddr)
	if err != nil {
		t.Fatalf("ContextHandler: %v", err)
	}
	if addr != prodAddr {
		t.Errorf("addr = %q, want %q", addr, prodAddr)
	}
	if token != "" {
		t.Errorf("token = %q, want empty", token)
	}
	if caCert != p.resolveProdCACertFile() {
		t.Errorf("caCert = %q, want %q", caCert, p.resolveProdCACertFile())
	}
}

func TestContextHandlerProdKVReadFailsYieldsEmptyTokenNoError(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	p := Paths{ProjectRoot: root, Home: home}
	if err := os.WriteFile(p.resolveRootTokenFile(), []byte("s.bastion-token"), 0o600); err != nil {
		t.Fatal(err)
	}
	prodAddr := "https://prod.example"

	addr, token, caCert, err := ResolveContext(context.Background(), p, "prod", prodAddr)
	if err != nil {
		t.Fatalf("ContextHandler: %v", err)
	}
	if addr != prodAddr {
		t.Errorf("addr = %q, want %q", addr, prodAddr)
	}
	if token != "" {
		t.Errorf("token = %q, want empty (KV read against unreachable Bastion Vault fails silently)", token)
	}
	if caCert != p.resolveProdCACertFile() {
		t.Errorf("caCert = %q, want %q", caCert, p.resolveProdCACertFile())
	}
}

func TestContextHandlerCACertConsistentAcrossTargets(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	p := Paths{ProjectRoot: root, Home: home}

	_, _, caCertDev, err := ResolveContext(context.Background(), p, "dev", "https://prod.example")
	if err != nil {
		t.Fatalf("ResolveContext(dev): %v", err)
	}
	_, _, caCertProd, err := ResolveContext(context.Background(), p, "prod", "https://prod.example")
	if err != nil {
		t.Fatalf("ResolveContext(prod): %v", err)
	}

	// The dev branch returns p.resolveCACertFile(). The prod branch returns p.resolveProdCACertFile() by design.
	if caCertDev != p.resolveCACertFile() {
		t.Errorf("dev caCert = %q, want %q", caCertDev, p.resolveCACertFile())
	}
	if caCertProd != p.resolveProdCACertFile() {
		t.Errorf("prod caCert = %q, want %q", caCertProd, p.resolveProdCACertFile())
	}
}
