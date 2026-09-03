package gitalyops

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"platform/internal/ui"
)

func newTestPrinter() *ui.Printer {
	return ui.New(io.Discard, io.Discard)
}

func TestRevertToStandalonePrecheck_MissingInventory(t *testing.T) {
	ansibleDir := t.TempDir()

	err := VerifyStandaloneRevert(context.Background(), ansibleDir, newTestPrinter())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "inventory file not found") {
		t.Errorf("error %q does not contain %q", err.Error(), "inventory file not found")
	}
	wantPath := filepath.Join(ansibleDir, "inventory-core-gitlab-praefect.yaml")
	if !strings.Contains(err.Error(), wantPath) {
		t.Errorf("error %q does not contain expected path %q", err.Error(), wantPath)
	}
}

func TestRevertToStandalonePrecheck_MissingPlaybook_NoPlaybooksDir(t *testing.T) {
	ansibleDir := t.TempDir()
	inventoryFile := filepath.Join(ansibleDir, "inventory-core-gitlab-praefect.yaml")
	if err := os.WriteFile(inventoryFile, []byte(""), 0o644); err != nil {
		t.Fatalf("failed to seed inventory file: %v", err)
	}

	err := VerifyStandaloneRevert(context.Background(), ansibleDir, newTestPrinter())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "playbook file not found") {
		t.Errorf("error %q does not contain %q", err.Error(), "playbook file not found")
	}
}

func TestRevertToStandalonePrecheck_MissingPlaybook_EmptyPlaybooksDir(t *testing.T) {
	ansibleDir := t.TempDir()
	inventoryFile := filepath.Join(ansibleDir, "inventory-core-gitlab-praefect.yaml")
	if err := os.WriteFile(inventoryFile, []byte(""), 0o644); err != nil {
		t.Fatalf("failed to seed inventory file: %v", err)
	}
	if err := os.Mkdir(filepath.Join(ansibleDir, "playbooks"), 0o755); err != nil {
		t.Fatalf("failed to create playbooks dir: %v", err)
	}

	err := VerifyStandaloneRevert(context.Background(), ansibleDir, newTestPrinter())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "playbook file not found") {
		t.Errorf("error %q does not contain %q", err.Error(), "playbook file not found")
	}
}

func TestRevertToStandalonePrecheck_BothFilesPresent_ExecFails(t *testing.T) {
	if _, err := exec.LookPath("ansible-playbook"); err == nil {
		t.Skip("ansible-playbook found on PATH; skipping since exec outcome would depend on the real binary")
	}

	ansibleDir := t.TempDir()
	inventoryFile := filepath.Join(ansibleDir, "inventory-core-gitlab-praefect.yaml")
	if err := os.WriteFile(inventoryFile, []byte(""), 0o644); err != nil {
		t.Fatalf("failed to seed inventory file: %v", err)
	}
	if err := os.Mkdir(filepath.Join(ansibleDir, "playbooks"), 0o755); err != nil {
		t.Fatalf("failed to create playbooks dir: %v", err)
	}
	playbookFile := filepath.Join(ansibleDir, "playbooks", "operation_playbook.yaml")
	if err := os.WriteFile(playbookFile, []byte(""), 0o644); err != nil {
		t.Fatalf("failed to seed playbook file: %v", err)
	}

	err := VerifyStandaloneRevert(context.Background(), ansibleDir, newTestPrinter())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "pre-check FAILED, do NOT proceed with Terraform revert") {
		t.Errorf("error %q does not contain expected wrapping message", err.Error())
	}
}

func TestRevertToStandalonePrecheck_InventoryIsDirectory(t *testing.T) {
	ansibleDir := t.TempDir()
	inventoryFile := filepath.Join(ansibleDir, "inventory-core-gitlab-praefect.yaml")
	if err := os.Mkdir(inventoryFile, 0o755); err != nil {
		t.Fatalf("failed to create inventory as directory: %v", err)
	}

	// os.Stat succeeds on a directory. The inventory check passes
	// and the function proceeds to the (missing) playbook check.
	err := VerifyStandaloneRevert(context.Background(), ansibleDir, newTestPrinter())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if strings.Contains(err.Error(), "inventory file not found") {
		t.Errorf("expected inventory check to pass since os.Stat succeeds on a directory, got %q", err.Error())
	}
	if !strings.Contains(err.Error(), "playbook file not found") {
		t.Errorf("error %q does not contain %q", err.Error(), "playbook file not found")
	}
}

func TestRevertToStandalonePrecheck_PlaybookIsDirectory(t *testing.T) {
	if _, err := exec.LookPath("ansible-playbook"); err == nil {
		t.Skip("ansible-playbook found on PATH; skipping since exec outcome would depend on the real binary")
	}

	ansibleDir := t.TempDir()
	inventoryFile := filepath.Join(ansibleDir, "inventory-core-gitlab-praefect.yaml")
	if err := os.WriteFile(inventoryFile, []byte(""), 0o644); err != nil {
		t.Fatalf("failed to seed inventory file: %v", err)
	}
	playbookFile := filepath.Join(ansibleDir, "playbooks", "operation_playbook.yaml")
	if err := os.MkdirAll(playbookFile, 0o755); err != nil {
		t.Fatalf("failed to create playbook as directory: %v", err)
	}

	// os.Stat succeeds on a directory. Both existence checks pass, and the
	// function proceeds to exec.Command.
	err := VerifyStandaloneRevert(context.Background(), ansibleDir, newTestPrinter())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "pre-check FAILED, do NOT proceed with Terraform revert") {
		t.Errorf("error %q does not contain expected wrapping message", err.Error())
	}
}

func TestRevertToStandalonePrecheck_TrailingSlashNoDoubleSlash(t *testing.T) {
	base := t.TempDir()

	withoutSlash := base
	withSlash := base + string(os.PathSeparator)

	errNoSlash := VerifyStandaloneRevert(context.Background(), withoutSlash, newTestPrinter())
	errWithSlash := VerifyStandaloneRevert(context.Background(), withSlash, newTestPrinter())

	if errNoSlash == nil || errWithSlash == nil {
		t.Fatal("expected errors from both invocations (missing inventory file)")
	}

	doubleSlash := string(os.PathSeparator) + string(os.PathSeparator)
	if strings.Contains(errNoSlash.Error(), doubleSlash) {
		t.Errorf("error for ansibleDir without trailing slash contains double slash: %q", errNoSlash.Error())
	}
	if strings.Contains(errWithSlash.Error(), doubleSlash) {
		t.Errorf("error for ansibleDir with trailing slash contains double slash: %q", errWithSlash.Error())
	}

	wantPath := filepath.Join(base, "inventory-core-gitlab-praefect.yaml")
	if !strings.Contains(errNoSlash.Error(), wantPath) {
		t.Errorf("error %q does not contain expected joined path %q", errNoSlash.Error(), wantPath)
	}
	if !strings.Contains(errWithSlash.Error(), wantPath) {
		t.Errorf("error %q does not contain expected joined path %q", errWithSlash.Error(), wantPath)
	}
}
