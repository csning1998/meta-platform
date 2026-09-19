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
	if addr != "https://172.16.0.1:8200" {
		t.Errorf("addr = %q, want %q", addr, "https://172.16.0.1:8200")
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
	if addr != "https://172.16.0.1:8200" {
		t.Errorf("addr = %q, want %q", addr, "https://172.16.0.1:8200")
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

	_, _, _, err := ResolveContext(context.Background(), p, "prod", prodAddr)
	if err == nil {
		t.Fatal("ResolveContext(prod, missing token): want error, got nil")
	}
}

func TestContextHandlerProdKVReadFailsYieldsError(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	p := Paths{ProjectRoot: root, Home: home}
	if err := os.WriteFile(p.resolveRootTokenFile(), []byte("s.bastion-token"), 0o600); err != nil {
		t.Fatal(err)
	}
	prodAddr := "https://prod.example"

	_, _, _, err := ResolveContext(context.Background(), p, "prod", prodAddr)
	if err == nil {
		t.Fatal("ResolveContext(prod, failed KV read): want error, got nil")
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
	if caCertDev != p.resolveCACertFile() {
		t.Errorf("dev caCert = %q, want %q", caCertDev, p.resolveCACertFile())
	}
}
