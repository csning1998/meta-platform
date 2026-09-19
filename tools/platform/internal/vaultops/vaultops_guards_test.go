package vaultops

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUnsealProductionNoInventoryDiscovered(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	p := Paths{ProjectRoot: root, AnsibleDir: t.TempDir(), Home: home}

	err := UnsealProduction(context.Background(), p, "", discardOut())
	if err == nil {
		t.Fatal("UnsealProduction: want error, got nil")
	}
	if !strings.Contains(err.Error(), "no Production Vault inventory discovered") {
		t.Errorf("error = %q, want it to contain %q", err.Error(), "no Production Vault inventory discovered")
	}
}

func TestUnsealProductionInventoryFileNotFound(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	p := Paths{ProjectRoot: root, AnsibleDir: t.TempDir(), Home: home}
	missingInventory := filepath.Join(t.TempDir(), "does-not-exist")

	err := UnsealProduction(context.Background(), p, missingInventory, discardOut())
	if err == nil {
		t.Fatal("UnsealProduction: want error, got nil")
	}
	if !strings.Contains(err.Error(), "inventory file not found at") {
		t.Errorf("error = %q, want it to contain %q", err.Error(), "inventory file not found at")
	}
}

func TestUnsealProductionPlaybookFileNotFound(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	ansibleDir := t.TempDir() // no playbooks/operation_playbook.yaml under here
	p := Paths{ProjectRoot: root, AnsibleDir: ansibleDir, Home: home}

	inventory := filepath.Join(t.TempDir(), "inventory")
	if err := os.WriteFile(inventory, []byte("dummy"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := UnsealProduction(context.Background(), p, inventory, discardOut())
	if err == nil {
		t.Fatal("UnsealProduction: want error, got nil")
	}
	if !strings.Contains(err.Error(), "playbook file not found at") {
		t.Errorf("error = %q, want it to contain %q", err.Error(), "playbook file not found at")
	}
}

func TestUnsealProductionRootTokenFileNotFound(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir() // no .vault-token here
	ansibleDir := t.TempDir()
	p := Paths{ProjectRoot: root, AnsibleDir: ansibleDir, Home: home}

	writePlaybook(t, p)
	inventory := filepath.Join(t.TempDir(), "inventory")
	if err := os.WriteFile(inventory, []byte("dummy"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := UnsealProduction(context.Background(), p, inventory, discardOut())
	if err == nil {
		t.Fatal("UnsealProduction: want error, got nil")
	}
	if !strings.Contains(err.Error(), "bootstrap Vault root token not found at") {
		t.Errorf("error = %q, want it to contain %q", err.Error(), "bootstrap Vault root token not found at")
	}
}

func TestUnsealProductionProdCACertNotFound(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	ansibleDir := t.TempDir()
	p := Paths{ProjectRoot: root, AnsibleDir: ansibleDir, TerraformDir: t.TempDir(), Home: home}

	writePlaybook(t, p)
	if err := os.WriteFile(p.resolveRootTokenFile(), []byte("s.token"), 0o600); err != nil {
		t.Fatal(err)
	}
	inventory := filepath.Join(t.TempDir(), "inventory")
	if err := os.WriteFile(inventory, []byte("dummy"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := UnsealProduction(context.Background(), p, inventory, discardOut())
	if err == nil {
		t.Fatal("UnsealProduction: want error, got nil")
	}
	if !strings.Contains(err.Error(), "Production Vault CA cert not found at") {
		t.Errorf("error = %q, want it to contain %q", err.Error(), "Production Vault CA cert not found at")
	}
}

func TestUnsealProductionAllGuardsPassReachesExecStage(t *testing.T) {
	if _, err := os.Stat("/usr/bin/env"); err != nil {
		t.Skip("no /usr/bin/env available to sanity-check PATH lookups")
	}

	root := t.TempDir()
	home := t.TempDir()
	ansibleDir := t.TempDir()
	tfDir := t.TempDir()
	p := Paths{ProjectRoot: root, AnsibleDir: ansibleDir, TerraformDir: tfDir, Home: home}

	writePlaybook(t, p)
	if err := os.WriteFile(p.resolveRootTokenFile(), []byte("s.token"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(p.resolveProdCACertFile()), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p.resolveProdCACertFile(), []byte("dummy-ca"), 0o644); err != nil {
		t.Fatal(err)
	}
	inventory := filepath.Join(t.TempDir(), "inventory")
	if err := os.WriteFile(inventory, []byte("dummy"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := UnsealProduction(context.Background(), p, inventory, discardOut())
	if err == nil {
		t.Skip("ansible-playbook unexpectedly succeeded against a dummy inventory/playbook; cannot assert exec-stage failure deterministically")
	}
	if !strings.Contains(err.Error(), "Production Vault unseal playbook") {
		t.Errorf("error = %q, want it to contain %q (confirms exec stage was reached, not an earlier guard)",
			err.Error(), "Production Vault unseal playbook")
	}
}
