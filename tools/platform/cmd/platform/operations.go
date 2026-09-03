package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/apenella/go-ansible/v2/pkg/playbook"

	"platform/internal/ansibleops"
	"platform/internal/config"
	"platform/internal/gitalyops"
	"platform/internal/libvirtops"
	"platform/internal/packerops"
	"platform/internal/sshops"
	"platform/internal/terraformops"
	"platform/internal/ui"
	"platform/internal/vaultops"
)

// Operation handlers shared between Cobra command execution and interactive menu dispatching.

func (a *app) generateVaultTLS(ctx context.Context) error {
	if !a.out.PromptConfirm(a.in, "Type 'Y' or 'y' to confirm execution: ") {
		a.out.Print(ui.Info, "Cancelled.")
		return nil
	}
	return vaultops.GenerateTLS(ctx, a.newVaultPaths(), a.out)
}

func (a *app) initVault(ctx context.Context) error {
	return vaultops.Init(ctx, a.newVaultPaths(), a.out, a.env)
}

func (a *app) unsealVault(ctx context.Context) error {
	return vaultops.UnsealBastion(ctx, a.newVaultPaths(), a.out, a.env)
}

func (a *app) enableVaultKV(ctx context.Context) error {
	return vaultops.EnableKVEngine(ctx, a.newVaultPaths(), a.out)
}

func (a *app) unsealProdVault(ctx context.Context) error {
	inv := a.env.Get(config.KeyProdVaultInventoryFile)
	return vaultops.UnsealProduction(ctx, a.newVaultPaths(), inv, a.out)
}

func (a *app) generateSSHKey(keyName string, overwrite bool) error {
	path, err := sshops.GenerateKey(a.home, keyName, overwrite, a.out)
	if err != nil {
		return err
	}
	a.env.Set(config.KeySSHPrivateKey, path)
	if err := a.env.Save(); err != nil {
		return err
	}
	a.out.Print(ui.Info, "In Terraform: ssh_private_key_path = \""+path+"\"")
	a.out.Print(ui.Info, "In Packer: ssh_public_key_path  = \""+path+".pub\"")
	return nil
}

func (a *app) verifySSHConnectivity() error {
	if !sshops.KeyExists(a.env.Get(config.KeySSHPrivateKey)) {
		return fmt.Errorf("SSH_PRIVATE_KEY not set or missing; execute 'platform ssh keygen' first")
	}
	return sshops.VerifyConnectivity(a.home, a.out)
}

func (a *app) verifyEnvironment() error {
	var missing []string
	group := ""
	for _, c := range config.VerifyNativeEnvironment() {
		if c.Group != group {
			a.out.Print(ui.Step, "Checking "+c.Group+"...")
			group = c.Group
		}
		if c.Installed {
			a.out.Print(ui.Info, c.Name+": Installed")
		} else {
			a.out.Print(ui.Warn, c.Name+": Missing")
			missing = append(missing, c.Name)
		}
	}
	a.out.PrintDivider("")
	if len(missing) > 0 {
		return fmt.Errorf("verification failed: missing required tools: %s", strings.Join(missing, ", "))
	}
	a.out.Print(ui.OK, "Verification successful: All required tools are installed.")
	return nil
}

const hypervisorInventoryYAML = "---\nall:\n  hosts:\n    localhost:\n      ansible_connection: local\n"

// runHypervisorPlaybook writes a throwaway inventory into a.ansibleDir. The implicit
// localhost inventory carries no directory against which Ansible resolves group_vars.
func (a *app) runHypervisorPlaybook(ctx context.Context) error {
	inventory, err := os.CreateTemp(a.ansibleDir, "inventory-hypervisor-baseline-*.yaml")
	if err != nil {
		return fmt.Errorf("ansible-playbook: create temporary inventory: %w", err)
	}
	defer func() { _ = os.Remove(inventory.Name()) }()

	if _, err := inventory.WriteString(hypervisorInventoryYAML); err != nil {
		_ = inventory.Close()
		return fmt.Errorf("ansible-playbook: write temporary inventory: %w", err)
	}
	if err := inventory.Close(); err != nil {
		return fmt.Errorf("ansible-playbook: close temporary inventory: %w", err)
	}

	target := filepath.Join("ansible", "playbooks", "playbook_hypervisor.yaml")
	opts := &playbook.AnsiblePlaybookOptions{
		AskBecomePass: true,
		Inventory:     inventory.Name(),
	}
	if err := ansibleops.RunPlaybook(ctx, a.ansibleDir, a.root, target, opts); err != nil {
		return fmt.Errorf("ansible-playbook: %w", err)
	}
	a.out.Print(ui.OK, "Hypervisor configuration applied.")
	return nil
}

func (a *app) purgeAllPackerArtifacts() error {
	return packerops.Clean(a.packerDir, "all", getConfiguredPackerBases(a.env), a.packerCache, a.out)
}

func (a *app) buildPackerImage(ctx context.Context, base string) error {
	env, err := buildPackerExecutionEnv(ctx, a)
	if err != nil {
		return err
	}

	if base == "all" {
		if err := packerops.Clean(a.packerDir, "all", getConfiguredPackerBases(a.env), a.packerCache, a.out); err != nil {
			return err
		}
		for _, b := range getConfiguredPackerBases(a.env) {
			if err := packerops.Build(ctx, a.packerDir, b, env, a.out); err != nil {
				return err
			}
		}
		return nil
	}

	if !packerops.BaseExists(a.packerDir, base) {
		return fmt.Errorf("buildPackerImage: unknown Packer base %q", base)
	}
	if err := packerops.Clean(a.packerDir, base, nil, a.packerCache, a.out); err != nil {
		return err
	}
	return packerops.Build(ctx, a.packerDir, base, env, a.out)
}

func buildPackerExecutionEnv(ctx context.Context, a *app) ([]string, error) {
	addr, token, caCert, err := vaultops.ResolveContext(ctx, a.newVaultPaths(), "dev", "")
	if err != nil {
		return nil, err
	}

	// a.env.Environ() already carries PKR_VAR_NET_BRIDGE/PKR_VAR_NET_DEVICE (BootstrapEnv sets
	// both unconditionally, including an empty-string bridge for the container/SLIRP strategy).
	base := append(os.Environ(), a.env.Environ()...)
	base = append(base, "VAULT_ADDR="+addr, "VAULT_TOKEN="+token, "VAULT_CACERT="+caCert)
	return base, nil
}

func (a *app) confirmGitalyRevertPrecheck(ctx context.Context) error {
	if !a.out.PromptConfirm(a.in, "Type 'Y' or 'y' to confirm execution: ") {
		a.out.Print(ui.Info, "Operation aborted by user.")
		return nil
	}
	return gitalyops.VerifyStandaloneRevert(ctx, a.ansibleDir, a.out)
}

func (a *app) purgeLibvirtResources() error {
	if !a.out.PromptConfirm(a.in, "Type 'Y' or 'y' to confirm execution: ") {
		a.out.Print(ui.Info, "Operation aborted by user.")
		return nil
	}
	if err := libvirtops.EnsureServices(a.out); err != nil {
		return err
	}
	return libvirtops.Purge(a.out)
}

func (a *app) purgeAllInfrastructure() error {
	if !a.out.PromptConfirm(a.in, "Type 'Y' or 'y' to confirm execution: ") {
		a.out.Print(ui.Info, "Operation aborted by user.")
		return nil
	}
	if err := libvirtops.EnsureServices(a.out); err != nil {
		return err
	}
	if err := libvirtops.Purge(a.out); err != nil {
		return err
	}
	return terraformops.ReportCleanupStatus(a.terraform, "all", getConfiguredTerraformLayers(a.env), a.out)
}

func (a *app) switchStrategy() error {
	a.out.Print(ui.Info, "Switching strategy...")
	a.out.Print(ui.Info, "Cleaning Terraform plugins/cache (keeping state)...")
	_ = os.RemoveAll(filepath.Join(a.terraform, ".terraform"))
	_ = os.Remove(filepath.Join(a.terraform, ".terraform.lock.hcl"))
	a.out.PrintDivider("")

	next := config.StrategyContainer
	if a.env.Get(config.KeyEnvironmentStrategy) == config.StrategyContainer {
		next = config.StrategyNative
	}
	net := config.ComputePackerNetConfig(next, a.out)
	a.env.Set(config.KeyPKRVarNetBridge, net.Bridge)
	a.env.Set(config.KeyPKRVarNetDevice, net.Device)
	a.env.Set(config.KeyEnvironmentStrategy, next)
	if err := a.env.Save(); err != nil {
		return err
	}
	a.out.Print(ui.Info, "Strategy 'ENVIRONMENT_STRATEGY' in .env updated to '"+next+"'.")
	return nil
}
