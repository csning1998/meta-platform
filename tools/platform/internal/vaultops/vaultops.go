// Package vaultops provides Bastion Vault TLS, initialization, unseal, and status operations,
// as well as Production Vault unseal automation.
package vaultops

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/apenella/go-ansible/v2/pkg/playbook"
	vaultapi "github.com/hashicorp/vault/api"

	"platform/internal/ansibleops"
	"platform/internal/ui"
)

const BastionVaultAddr = "https://127.0.0.1:8200"

// Paths groups all project-relative and user-relative paths needed by Vault operations.
type Paths struct {
	ProjectRoot  string
	AnsibleDir   string
	TerraformDir string
	Home         string
}

func (p Paths) resolveKeysDir() string       { return filepath.Join(p.ProjectRoot, "vault", "keys") }
func (p Paths) resolveTLSDir() string        { return filepath.Join(p.ProjectRoot, "vault", "tls") }
func (p Paths) resolveInitFile() string      { return filepath.Join(p.resolveKeysDir(), "init-output.json") }
func (p Paths) resolveUnsealKeyFile() string { return filepath.Join(p.resolveKeysDir(), "unseal.key") }
func (p Paths) resolveRootTokenFile() string { return filepath.Join(p.Home, ".vault-token") }
func (p Paths) resolveCACertFile() string    { return filepath.Join(p.resolveTLSDir(), "ca.pem") }
func (p Paths) resolveProdCACertFile() string {
	return filepath.Join(p.TerraformDir, "layers", "shared-vault-frontend", "tls", "bootstrap-ca.crt")
}

func newClient(addr, caCertPath, token string) (*vaultapi.Client, error) {
	cfg := vaultapi.DefaultConfig()
	cfg.Address = addr
	if caCertPath != "" {
		if err := cfg.ConfigureTLS(&vaultapi.TLSConfig{CACert: caCertPath}); err != nil {
			return nil, fmt.Errorf("vaultops: configure TLS from %s: %w", caCertPath, err)
		}
	}
	client, err := vaultapi.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("vaultops: new client for %s: %w", addr, err)
	}
	if token != "" {
		client.SetToken(token)
	}
	return client, nil
}

func (p Paths) newBastionClient(token string) (*vaultapi.Client, error) {
	return newClient(BastionVaultAddr, p.resolveCACertFile(), token)
}

// ProdCACertPath returns the on-disk path where shared-vault-frontend's Terraform output
// writes the Production Vault CA certificate.
func (p Paths) ProdCACertPath() string { return p.resolveProdCACertFile() }

// SealStatus is one Vault instance's reachability, initialization, and seal state.
type SealStatus struct {
	Reachable   bool
	Initialized bool
	Sealed      bool
}

// InspectStatusAt queries the Vault instance at addr, verifying its TLS certificate against
// caCert. A zero SealStatus means the instance did not response.
func InspectStatusAt(ctx context.Context, addr, caCert string) SealStatus {
	client, err := newClient(addr, caCert, "")
	if err != nil {
		return SealStatus{}
	}
	st, err := client.Sys().SealStatusWithContext(ctx)
	if err != nil {
		return SealStatus{}
	}
	return SealStatus{Reachable: true, Initialized: st.Initialized, Sealed: st.Sealed}
}

// InspectBastionStatus queries Bastion Vault's full seal status.
func InspectBastionStatus(ctx context.Context, p Paths) SealStatus {
	return InspectStatusAt(ctx, BastionVaultAddr, p.resolveCACertFile())
}

// GetBastionStatus checks whether Bastion Vault is reachable and reports its sealed state.
func GetBastionStatus(ctx context.Context, p Paths) (running, sealed bool, err error) {
	client, err := p.newBastionClient("")
	if err != nil {
		return false, false, err
	}
	st, err := client.Sys().SealStatusWithContext(ctx)
	if err != nil {
		return false, false, nil
	}
	return true, st.Sealed, nil
}

// SyncVaultToken extracts the root token from the initialization file or existing token file and updates the environment.
func SyncVaultToken(p Paths, env interface{ Set(string, string) }) (string, error) {
	var token string

	if data, err := os.ReadFile(p.resolveInitFile()); err == nil {
		var init struct {
			RootToken string `json:"root_token"`
		}
		if err := json.Unmarshal(data, &init); err != nil {
			return "", fmt.Errorf("vaultops: parse %s: %w", p.resolveInitFile(), err)
		}
		token = init.RootToken
	} else if data, err := os.ReadFile(p.resolveRootTokenFile()); err == nil {
		token = strings.TrimSpace(string(data))
	} else {
		return "", nil
	}

	if token == "" {
		return "", fmt.Errorf("vaultops: failed to extract a valid token")
	}

	env.Set("VAULT_TOKEN", token)

	tmp := p.resolveRootTokenFile() + fmt.Sprintf(".tmp%d", time.Now().UnixNano())
	if err := os.WriteFile(tmp, []byte(token), 0o600); err != nil {
		return "", fmt.Errorf("vaultops: write %s: %w", tmp, err)
	}
	if err := os.Rename(tmp, p.resolveRootTokenFile()); err != nil {
		return "", fmt.Errorf("vaultops: replace %s: %w", p.resolveRootTokenFile(), err)
	}
	return token, nil
}

// persistInitOutput writes the Vault initialization response payload and unseal key material
// to disk under p's keys directory. Creates the target keys directory with 0700 mode bits and
// writes artifact files with 0600 mode bits to enforce owner-only read and traversal permissions.
func persistInitOutput(p Paths, resp *vaultapi.InitResponse) error {
	if err := os.MkdirAll(p.resolveKeysDir(), 0o700); err != nil {
		return fmt.Errorf("vaultops: mkdir %s: %w", p.resolveKeysDir(), err)
	}

	raw, err := json.Marshal(resp)
	if err != nil {
		return fmt.Errorf("vaultops: marshal init response: %w", err)
	}
	if err := os.WriteFile(p.resolveInitFile(), raw, 0o600); err != nil {
		return fmt.Errorf("vaultops: write %s: %w", p.resolveInitFile(), err)
	}
	if len(resp.KeysB64) == 0 {
		return fmt.Errorf("vaultops: no unseal keys in init response")
	}
	if err := os.WriteFile(p.resolveUnsealKeyFile(), []byte(strings.Join(resp.KeysB64, "\n")+"\n"), 0o600); err != nil {
		return fmt.Errorf("vaultops: write %s: %w", p.resolveUnsealKeyFile(), err)
	}
	return nil
}

// Init initializes Bastion Vault with Shamir secret shares, persists unseal keys, and performs initial unseal.
func Init(ctx context.Context, p Paths, out *ui.Printer, env interface{ Set(string, string) }) error {
	if _, err := os.Stat(p.resolveInitFile()); err == nil {
		return fmt.Errorf("vaultops: %s already exists, refusing to re-init", p.resolveInitFile())
	}

	client, err := p.newBastionClient("")
	if err != nil {
		return err
	}
	resp, err := client.Sys().InitWithContext(ctx, &vaultapi.InitRequest{SecretShares: 5, SecretThreshold: 3})
	if err != nil {
		return fmt.Errorf("vaultops: vault init against %s: %w", BastionVaultAddr, err)
	}

	if err := persistInitOutput(p, resp); err != nil {
		return err
	}

	out.Print(ui.Info, "Keys saved to "+p.resolveKeysDir())

	if _, err := SyncVaultToken(p, env); err != nil {
		return err
	}
	if err := UnsealBastion(ctx, p, out, env); err != nil {
		return fmt.Errorf("vaultops: auto-unseal after init: %w", err)
	}

	out.Print(ui.OK, "Bastion Vault is ready for use.")
	return nil
}

// UnsealBastion applies stored unseal keys to Bastion Vault until the sealed flag clears.
func UnsealBastion(ctx context.Context, p Paths, out *ui.Printer, env interface{ Set(string, string) }) error {
	keysRaw, err := os.ReadFile(p.resolveUnsealKeyFile())
	if err != nil {
		return fmt.Errorf("vaultops: unseal keys not found at %s, run Init first: %w", p.resolveUnsealKeyFile(), err)
	}

	if _, sealed, err := GetBastionStatus(ctx, p); err == nil && !sealed {
		out.Print(ui.Info, "Bastion Vault is already unsealed.")
		return nil
	}

	client, err := p.newBastionClient("")
	if err != nil {
		return err
	}

	for _, key := range strings.Split(strings.TrimSpace(string(keysRaw)), "\n") {
		key = strings.TrimSpace(key)
		if key == "" {
			continue
		}
		if _, err := client.Sys().UnsealWithContext(ctx, key); err != nil {
			return fmt.Errorf("vaultops: unseal: %w", err)
		}
	}

	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if _, sealed, err := GetBastionStatus(ctx, p); err == nil && !sealed {
			out.Print(ui.OK, "Bastion Vault Unsealed and ready.")
			if _, statErr := os.Stat(p.resolveRootTokenFile()); statErr == nil {
				if _, err := SyncVaultToken(p, env); err != nil {
					return err
				}
				out.Print(ui.Info, "Vault environment variables set for this session.")
			}
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("vaultops: still reporting sealed after 5s of unseal attempts")
}

// EnableKVEngine enables the kv-v2 secrets engine at secret/ if not already mounted.
func EnableKVEngine(ctx context.Context, p Paths, out *ui.Printer) error {
	tokenRaw, err := os.ReadFile(p.resolveRootTokenFile())
	if err != nil {
		return fmt.Errorf("vaultops: root token not found at %s: %w", p.resolveRootTokenFile(), err)
	}
	client, err := p.newBastionClient(strings.TrimSpace(string(tokenRaw)))
	if err != nil {
		return err
	}

	mounts, err := client.Sys().ListMountsWithContext(ctx)
	if err == nil {
		if _, exists := mounts["secret/"]; exists {
			out.Print(ui.Info, "kv-v2 secrets engine is already enabled.")
			return nil
		}
	}

	out.Print(ui.Task, "'secret/' path not found, enabling kv-v2...")
	if err := client.Sys().MountWithContext(ctx, "secret", &vaultapi.MountInput{Type: "kv-v2"}); err != nil {
		return fmt.Errorf("vaultops: enable kv-v2: %w", err)
	}
	return nil
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
			"dev_vault_url":       BastionVaultAddr,
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
	secret, err := client.Logical().ReadWithContext(ctx, mountPath+"/data/"+secretPath)
	if err != nil || secret == nil {
		return "", false
	}
	data, _ := secret.Data["data"].(map[string]interface{})
	value, ok = data[field].(string)
	return value, ok
}

// ResolveContext resolves the Vault address, token, and CA certificate paths for the target environment.
func ResolveContext(ctx context.Context, p Paths, target, prodVaultAddr string) (addr, token, caCert string, err error) {
	if target != "prod" {
		tokenRaw, _ := os.ReadFile(p.resolveRootTokenFile())
		return BastionVaultAddr, strings.TrimSpace(string(tokenRaw)), p.resolveCACertFile(), nil
	}

	caCert = p.resolveProdCACertFile()
	bastionTokenRaw, readErr := os.ReadFile(p.resolveRootTokenFile())
	if readErr != nil {
		return prodVaultAddr, "", caCert, nil
	}

	client, err := p.newBastionClient(strings.TrimSpace(string(bastionTokenRaw)))
	if err != nil {
		return prodVaultAddr, "", caCert, nil
	}
	token, _ = ReadKVv2Field(ctx, client, "secret", "meta-platform/credentials", "prod_vault_root_token")
	return prodVaultAddr, token, caCert, nil
}
