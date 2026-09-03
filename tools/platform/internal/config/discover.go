package config

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// DiscoverPackerBases scans packerDir/distro and packerDir/services for *.pkrvars.hcl files,
// excluding values.pkrvars.hcl, and returns sorted base identifiers.
func DiscoverPackerBases(packerDir string) ([]string, error) {
	var bases []string
	for _, sub := range []string{"distro", "services"} {
		entries, err := os.ReadDir(filepath.Join(packerDir, sub))
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("config: read %s: %w", filepath.Join(packerDir, sub), err)
		}
		for _, entry := range entries {
			name := entry.Name()
			if entry.IsDir() || !strings.HasSuffix(name, ".pkrvars.hcl") || name == "values.pkrvars.hcl" {
				continue
			}
			bases = append(bases, strings.TrimSuffix(name, ".pkrvars.hcl"))
		}
	}
	sort.Strings(bases)
	return bases, nil
}

// DiscoverTerraformLayers lists subdirectories within terraformDir/layers and returns
// a lexicographically sorted slice of layer identifiers.
func DiscoverTerraformLayers(terraformDir string) ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(terraformDir, "layers"))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("config: read %s/layers: %w", terraformDir, err)
	}

	var layers []string
	for _, entry := range entries {
		if entry.IsDir() {
			layers = append(layers, entry.Name())
		}
	}
	sort.Strings(layers)
	return layers, nil
}

var vaultVIPLineRe = regexp.MustCompile(`"vault_vip"\s*:\s*"([^"]*)"`)

// ProdVaultInventory contains the discovered Ansible production Vault inventory file path and
// the derived HTTPS service address.
type ProdVaultInventory struct {
	File string
	Addr string
}

// DiscoverProdVaultInventory locates inventory-*-vault-frontend.yaml under ansibleDir, parses
// the vault_vip attribute, and constructs the Vault endpoint URL. Exactly one inventory file
// MUST exist. Multiple matches trigger an error.
func DiscoverProdVaultInventory(ansibleDir string) (ProdVaultInventory, error) {
	matches, err := filepath.Glob(filepath.Join(ansibleDir, "inventory-*-vault-frontend.yaml"))
	if err != nil {
		return ProdVaultInventory{}, fmt.Errorf("config: glob prod vault inventory: %w", err)
	}
	if len(matches) > 1 {
		return ProdVaultInventory{}, fmt.Errorf("config: multiple production Vault inventory files found, expected at most one: %v", matches)
	}
	if len(matches) == 0 {
		return ProdVaultInventory{}, nil
	}

	data, err := os.ReadFile(matches[0])
	if err != nil {
		return ProdVaultInventory{}, fmt.Errorf("config: read %s: %w", matches[0], err)
	}

	inv := ProdVaultInventory{File: matches[0]}
	if m := vaultVIPLineRe.FindSubmatch(data); m != nil && len(m[1]) > 0 {
		inv.Addr = "https://" + string(m[1]) + ":443"
	}
	return inv, nil
}
