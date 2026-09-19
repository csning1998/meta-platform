package vaultops

import (
	"os"
	"strings"
	"testing"
)

func TestTokenSyncNeitherFileExists(t *testing.T) {
	home := t.TempDir()
	p := Paths{ProjectRoot: t.TempDir(), Home: home}
	env := newFakeEnv()

	token, err := SyncVaultToken(p, env)
	if err != nil {
		t.Fatalf("TokenSync: %v", err)
	}
	if token != "" {
		t.Errorf("token = %q, want empty", token)
	}
	if len(env.kv) != 0 {
		t.Errorf("env.Set was called: %v", env.kv)
	}
}

func TestTokenSyncFromRootTokenFile(t *testing.T) {
	home := t.TempDir()
	p := Paths{ProjectRoot: t.TempDir(), Home: home}
	if err := os.WriteFile(p.resolveRootTokenFile(), []byte("  s.xyz  \n"), 0o600); err != nil {
		t.Fatal(err)
	}
	env := newFakeEnv()

	token, err := SyncVaultToken(p, env)
	if err != nil {
		t.Fatalf("TokenSync: %v", err)
	}
	if token != "s.xyz" {
		t.Errorf("token = %q, want s.xyz", token)
	}
	if env.kv["VAULT_TOKEN"] != "s.xyz" {
		t.Errorf("env.Set(VAULT_TOKEN) = %v, want s.xyz", env.kv)
	}
	data, err := os.ReadFile(p.resolveRootTokenFile())
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "s.xyz" {
		t.Errorf("resolveRootTokenFile content = %q, want %q", data, "s.xyz")
	}
}

func TestTokenSyncEmptyTokenFileErrors(t *testing.T) {
	home := t.TempDir()
	p := Paths{ProjectRoot: t.TempDir(), Home: home}
	if err := os.WriteFile(p.resolveRootTokenFile(), []byte("   \n"), 0o600); err != nil {
		t.Fatal(err)
	}
	env := newFakeEnv()

	_, err := SyncVaultToken(p, env)
	if err == nil {
		t.Fatal("TokenSync: want error for empty token file, got nil")
	}
	if !strings.Contains(err.Error(), "failed to extract a valid token") {
		t.Errorf("error = %q, want it to contain 'failed to extract a valid token'", err.Error())
	}
}
