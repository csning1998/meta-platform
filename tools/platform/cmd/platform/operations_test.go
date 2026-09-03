package main

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"platform/internal/config"
	"platform/internal/ui"
)

func TestBuildPackerExecutionEnvDoesNotDuplicateNetVars(t *testing.T) {
	dir := t.TempDir()
	env, err := config.Load(filepath.Join(dir, ".env"))
	if err != nil {
		t.Fatalf("config.Load: %v", err)
	}
	env.Set(config.KeyPKRVarNetBridge, "")
	env.Set(config.KeyPKRVarNetDevice, "virtio-net")

	a := &app{
		root: dir,
		home: dir,
		env:  env,
		out:  ui.New(io.Discard, io.Discard),
	}

	got, err := buildPackerExecutionEnv(context.Background(), a)
	if err != nil {
		t.Fatalf("buildPackerExecutionEnv: %v", err)
	}

	assertSingleEnvEntry(t, got, config.KeyPKRVarNetBridge, config.KeyPKRVarNetBridge+"=")
	assertSingleEnvEntry(t, got, config.KeyPKRVarNetDevice, config.KeyPKRVarNetDevice+"=virtio-net")
}

func TestBuildPackerImageRejectsUnknownBaseAndPreservesStaleOutput(t *testing.T) {
	dir := t.TempDir()
	packerDir := filepath.Join(dir, "packer")
	if err := os.MkdirAll(filepath.Join(packerDir, "distro"), 0o755); err != nil {
		t.Fatalf("mkdir distro: %v", err)
	}
	if err := os.WriteFile(filepath.Join(packerDir, "distro", "ubuntu-24.pkrvars.hcl"), nil, 0o644); err != nil {
		t.Fatalf("write var file: %v", err)
	}
	// Stale output left over under the typo'd name from a prior, since-renamed base. The var
	// file no longer exists, but Clean(base, ...) would still remove output/<base> unless
	// buildPackerImage validates the base first.
	staleOutputDir := filepath.Join(packerDir, "output", "ubuntu-25")
	if err := os.MkdirAll(staleOutputDir, 0o755); err != nil {
		t.Fatalf("mkdir stale output: %v", err)
	}
	if err := os.WriteFile(filepath.Join(staleOutputDir, "disk.qcow2"), []byte("fake"), 0o644); err != nil {
		t.Fatalf("write fake artifact: %v", err)
	}

	env, err := config.Load(filepath.Join(dir, ".env"))
	if err != nil {
		t.Fatalf("config.Load: %v", err)
	}
	a := &app{root: dir, home: dir, packerDir: packerDir, env: env, out: ui.New(io.Discard, io.Discard)}

	err = a.buildPackerImage(context.Background(), "ubuntu-25")
	if err == nil || !strings.Contains(err.Error(), "unknown Packer base") {
		t.Fatalf("buildPackerImage(typo base) = %v, want error containing %q", err, "unknown Packer base")
	}

	if _, statErr := os.Stat(filepath.Join(staleOutputDir, "disk.qcow2")); statErr != nil {
		t.Errorf("stale output for the typo'd base was removed before validation: %v", statErr)
	}
}

func TestBuildPackerExecutionEnvNetVarCombinations(t *testing.T) {
	cases := []struct {
		name       string
		bridge     string
		device     string
		wantBridge string
		wantDevice string
	}{
		{"both empty", "", "", config.KeyPKRVarNetBridge + "=", config.KeyPKRVarNetDevice + "="},
		{"both set", "virbr0", "virtio-net", config.KeyPKRVarNetBridge + "=virbr0", config.KeyPKRVarNetDevice + "=virtio-net"},
		{"only device set", "", "e1000", config.KeyPKRVarNetBridge + "=", config.KeyPKRVarNetDevice + "=e1000"},
		{"only bridge set", "br1", "", config.KeyPKRVarNetBridge + "=br1", config.KeyPKRVarNetDevice + "="},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			env, err := config.Load(filepath.Join(dir, ".env"))
			if err != nil {
				t.Fatalf("config.Load: %v", err)
			}
			env.Set(config.KeyPKRVarNetBridge, c.bridge)
			env.Set(config.KeyPKRVarNetDevice, c.device)

			a := &app{root: dir, home: dir, env: env, out: ui.New(io.Discard, io.Discard)}

			got, err := buildPackerExecutionEnv(context.Background(), a)
			if err != nil {
				t.Fatalf("buildPackerExecutionEnv: %v", err)
			}

			assertSingleEnvEntry(t, got, config.KeyPKRVarNetBridge, c.wantBridge)
			assertSingleEnvEntry(t, got, config.KeyPKRVarNetDevice, c.wantDevice)
			assertSingleEnvEntry(t, got, "VAULT_ADDR", "VAULT_ADDR=https://127.0.0.1:8200")
		})
	}
}

func assertSingleEnvEntry(t *testing.T, environ []string, key, want string) {
	t.Helper()
	var matches []string
	for _, kv := range environ {
		if strings.HasPrefix(kv, key+"=") {
			matches = append(matches, kv)
		}
	}
	if len(matches) != 1 {
		t.Fatalf("%s appears %d times in env, want exactly 1: %v", key, len(matches), matches)
	}
	if matches[0] != want {
		t.Errorf("%s = %q, want %q", key, matches[0], want)
	}
}
