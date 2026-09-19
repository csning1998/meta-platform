// Package vaultops provides Bastion Vault connectivity resolution and status inspection,
// as well as Production Vault unseal automation.
package vaultops

import (
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"

	"github.com/apenella/go-ansible/v2/pkg/playbook"
	vaultapi "github.com/hashicorp/vault/api"

	"platform/internal/ansibleops"
	"platform/internal/ui"

	"gitlab.com/csning1998-lab/parent-group-governance/tools/governance/pkg/vaultclient"
)

// Paths groups all project-relative and user-relative paths needed by Vault operations.
type Paths struct {
	ProjectRoot        string
	AnsibleDir         string
	TerraformDir       string
	Home               string
	bastionVaultAddr   string
	bastionVaultCACert string
	prodTokenRef       vaultclient.SecretRef
}

// NewPaths constructs Paths for a caller outside this package.
func NewPaths(projectRoot, ansibleDir, terraformDir, home, bastionVaultAddr, bastionVaultCACert string) Paths {
	return Paths{
		ProjectRoot:        projectRoot,
		AnsibleDir:         ansibleDir,
		TerraformDir:       terraformDir,
		Home:               home,
		bastionVaultAddr:   bastionVaultAddr,
		bastionVaultCACert: bastionVaultCACert,
	}
}

// WithProdTokenRef returns a copy of Paths configured with a custom Production Vault token reference.
func (p Paths) WithProdTokenRef(ref vaultclient.SecretRef) Paths {
	p.prodTokenRef = ref
	return p
}

func (p Paths) resolveProdTokenRef() vaultclient.SecretRef {
	if p.prodTokenRef == (vaultclient.SecretRef{}) {
		return ResolveProdTokenRef()
	}
	return p.prodTokenRef
}

func (p Paths) resolveBastionAddr() string {
	if p.bastionVaultAddr != "" {
		return p.bastionVaultAddr
	}
	return "https://172.16.0.1:8200"
}

func (p Paths) resolveTLSDir() string        { return filepath.Join(p.ProjectRoot, "vault", "tls") }
func (p Paths) resolveRootTokenFile() string { return filepath.Join(p.Home, ".vault-token") }
func (p Paths) resolveCACertFile() string {
	if p.bastionVaultCACert != "" {
		return p.bastionVaultCACert
	}
	return filepath.Join(p.resolveTLSDir(), "ca.pem")
}
func (p Paths) resolveProdCACertFile() string {
	return filepath.Join(p.TerraformDir, "layers", "shared-vault-frontend", "tls", "bootstrap-ca.crt")
}

// ProdCACertPath returns the on-disk path where shared-vault-frontend's Terraform output
// writes the Production Vault CA certificate.
func (p Paths) ProdCACertPath() string { return p.resolveProdCACertFile() }

// SealStatus is one Vault instance's reachability, initialization, and seal state.
type SealStatus = vaultclient.SealStatus

// InspectStatusAt queries the Vault instance at addr, verifying its TLS certificate against
// caCert. A zero SealStatus means the instance did not respond.
func InspectStatusAt(ctx context.Context, addr, caCert string) SealStatus {
	return vaultclient.InspectStatus(ctx, vaultclient.Config{
		Address:    addr,
		CACertPath: caCert,
	})
}

// InspectBastionStatus queries Bastion Vault's full seal status.
func InspectBastionStatus(ctx context.Context, p Paths) SealStatus {
	return InspectStatusAt(ctx, p.resolveBastionAddr(), p.resolveCACertFile())
}

// GetBastionStatus checks whether Bastion Vault is reachable and reports its sealed state.
func GetBastionStatus(ctx context.Context, p Paths) (running, sealed bool, err error) {
	client, err := vaultclient.NewClient(vaultclient.Config{
		Address:    p.resolveBastionAddr(),
		CACertPath: p.resolveCACertFile(),
	})
	if err != nil {
		return false, false, err
	}
	return vaultclient.ProbeState(ctx, client)
}

// SyncVaultToken extracts the root token from the user token file and updates the environment.
func SyncVaultToken(p Paths, env interface{ Set(string, string) }) (string, error) {
	return vaultclient.SyncSessionToken(p.Home, env)
}

// UnsealProduction triggers the Ansible playbook to unseal the remote Production Vault cluster.
func UnsealProduction(ctx context.Context, p Paths, inventoryFile string, out *ui.Printer) error {
	playbookFile := filepath.Join(p.AnsibleDir, "playbooks", "operation_playbook.yaml")

	if inventoryFile == "" {
		return fmt.Errorf("vaultops: no Production Vault inventory discovered; apply shared-vault-frontend first")
	}
	if _, err := os.Stat(inventoryFile); err != nil {
		return fmt.Errorf("vaultops: inventory file not found at %s: %w", inventoryFile, err)
	}
	if _, err := os.Stat(playbookFile); err != nil {
		return fmt.Errorf("vaultops: playbook file not found at %s: %w", playbookFile, err)
	}
	if _, err := os.Stat(p.resolveRootTokenFile()); err != nil {
		return fmt.Errorf("vaultops: bootstrap Vault root token not found at %s: %w", p.resolveRootTokenFile(), err)
	}
	prodCACert, err := os.ReadFile(p.resolveProdCACertFile())
	if err != nil {
		return fmt.Errorf("vaultops: Production Vault CA cert not found at %s: %w", p.resolveProdCACertFile(), err)
	}

	prodCAB64 := base64.StdEncoding.EncodeToString(prodCACert)

	opts := &playbook.AnsiblePlaybookOptions{
		Inventory: inventoryFile,
		Tags:      "vault-unseal",
		ExtraVars: map[string]interface{}{
			"dev_vault_url":       p.resolveBastionAddr(),
			"dev_root_token_path": p.resolveRootTokenFile(),
			"vault_ca_cert_b64":   prodCAB64,
		},
	}
	if err := ansibleops.RunPlaybook(ctx, p.AnsibleDir, "", playbookFile, opts); err != nil {
		return fmt.Errorf("vaultops: Production Vault unseal playbook: %w", err)
	}
	out.Print(ui.OK, "[Prod Vault] Unseal Playbook execution completed.")
	return nil
}

// ReadKVv2Field reads mountPath/data/secretPath from a KV v2 engine and returns the specified field value.
func ReadKVv2Field(ctx context.Context, client *vaultapi.Client, mountPath, secretPath, field string) (value string, ok bool) {
	return vaultclient.ReadKVv2Field(ctx, client, mountPath, secretPath, field)
}

// ResolveContext resolves the Vault address, token, and CA certificate paths for the target environment.
func ResolveContext(ctx context.Context, p Paths, target, prodVaultAddr string) (addr, token, caCert string, err error) {
	bastionCfg := vaultclient.Config{
		Address:    p.resolveBastionAddr(),
		CACertPath: p.resolveCACertFile(),
		Token:      vaultclient.ReadTokenFile(p.Home),
	}
	prodCfg := vaultclient.Config{
		Address:    prodVaultAddr,
		CACertPath: p.resolveProdCACertFile(),
	}
	return vaultclient.ResolveTargetContext(ctx, target, bastionCfg, prodCfg, p.resolveProdTokenRef())
}
