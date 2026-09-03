// Package gitalyops provides Gitaly cluster operations and safety pre-checks.
package gitalyops

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/apenella/go-ansible/v2/pkg/playbook"

	"platform/internal/ansibleops"
	"platform/internal/ui"
)

// VerifyStandaloneRevert runs the Ansible safety pre-check before reverting Gitaly nodes to standalone mode.
func VerifyStandaloneRevert(ctx context.Context, ansibleDir string, out *ui.Printer) error {
	inventoryFile := filepath.Join(ansibleDir, "inventory-core-gitlab-praefect.yaml")
	playbookFile := filepath.Join(ansibleDir, "playbooks", "operation_playbook.yaml")

	if _, err := os.Stat(inventoryFile); err != nil {
		return fmt.Errorf("gitalyops: inventory file not found at %s: %w", inventoryFile, err)
	}
	if _, err := os.Stat(playbookFile); err != nil {
		return fmt.Errorf("gitalyops: playbook file not found at %s: %w", playbookFile, err)
	}

	opts := &playbook.AnsiblePlaybookOptions{Inventory: inventoryFile, Tags: "gitaly-revert-standalone"}
	if err := ansibleops.RunPlaybook(ctx, ansibleDir, "", playbookFile, opts); err != nil {
		return fmt.Errorf("gitalyops: pre-check FAILED, do NOT proceed with Terraform revert: %w", err)
	}

	out.Print(ui.OK, "[Gitaly] Pre-check passed. Gitaly-0 has all repositories.")
	out.Print(ui.Info, "Safe to proceed:")
	out.Print(ui.Info, "  1. Remove Praefect nodes from terraform.tfvars")
	out.Print(ui.Info, "  2. Run: terraform apply")
	return nil
}
