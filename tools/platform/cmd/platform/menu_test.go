package main

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"platform/internal/ui"
)

func TestPrintEnvironmentBannerToleratesUnreadableEnvFile(t *testing.T) {
	dir := t.TempDir()
	// config.Load(path) errors when path is a directory, exercising the guarded branch that
	// used to dereference a nil *config.Env before printEnvironmentBanner checked the error.
	if err := os.MkdirAll(filepath.Join(dir, ".env"), 0o700); err != nil {
		t.Fatalf("mkdir .env: %v", err)
	}

	var out bytes.Buffer
	a := &app{root: dir, out: ui.New(&out, io.Discard)}

	a.printEnvironmentBanner()

	if !strings.Contains(out.String(), "Environment: "+strings.ToUpper("native")) {
		t.Errorf("output = %q, want it to fall back to the native strategy default", out.String())
	}
}

func TestPrintEnvironmentBannerMissingEnvFileDefaultsToNative(t *testing.T) {
	dir := t.TempDir() // no .env written; config.Load tolerates a missing file with err == nil

	var out bytes.Buffer
	a := &app{root: dir, out: ui.New(&out, io.Discard)}

	a.printEnvironmentBanner()

	if !strings.Contains(out.String(), "Environment: NATIVE") {
		t.Errorf("output = %q, want it to default to NATIVE when .env does not exist", out.String())
	}
	if strings.Contains(out.String(), "PODMAN") {
		t.Errorf("output = %q, want no Engine line for the native default", out.String())
	}
}

func TestPrintEnvironmentBannerContainerStrategyPrintsPodmanEngine(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(`ENVIRONMENT_STRATEGY="container"`+"\n"), 0o600); err != nil {
		t.Fatalf("write .env: %v", err)
	}

	var out bytes.Buffer
	a := &app{root: dir, out: ui.New(&out, io.Discard)}

	a.printEnvironmentBanner()

	if !strings.Contains(out.String(), "Environment: CONTAINER") {
		t.Errorf("output = %q, want Environment: CONTAINER", out.String())
	}
	if !strings.Contains(out.String(), "Engine: PODMAN") {
		t.Errorf("output = %q, want the PODMAN engine line for container strategy", out.String())
	}
}

// Validates printVaultStatusBanner execution when a Production Vault CA certificate exists and a.env is uninitialized (nil).
// Execution MUST NOT panic or block when evaluating Vault configuration status.
func TestPrintVaultStatusBannerToleratesNilEnv(t *testing.T) {
	dir := t.TempDir()
	terraform := filepath.Join(dir, "terraform")
	caCertPath := filepath.Join(terraform, "layers", "shared-vault-frontend", "tls", "bootstrap-ca.crt")
	if err := os.MkdirAll(filepath.Dir(caCertPath), 0o755); err != nil {
		t.Fatalf("mkdir CA cert dir: %v", err)
	}
	if err := os.WriteFile(caCertPath, []byte("not-a-real-cert"), 0o644); err != nil {
		t.Fatalf("write fake CA cert: %v", err)
	}

	a := &app{root: dir, terraform: terraform, env: nil, out: ui.New(io.Discard, io.Discard)}

	done := make(chan struct{})
	go func() {
		defer close(done)
		a.printVaultStatusBanner(context.Background())
	}()

	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("printVaultStatusBanner did not return within bound (nil a.env must not hang or panic)")
	}
}
