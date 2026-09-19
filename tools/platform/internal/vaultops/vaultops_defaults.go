// Package vaultops provides Bastion Vault connectivity resolution and status inspection,
// as well as Production Vault unseal automation.
package vaultops

import (
	"os"

	"gitlab.com/csning1998-lab/parent-group-governance/tools/governance/pkg/vaultclient"
)

const (
	// DefaultTokenMount is the default KV-v2 engine mount path for credentials in Bastion Vault.
	DefaultTokenMount = "secret"
	// DefaultTokenPath is the default KV-v2 secret path holding Production Vault credentials.
	DefaultTokenPath = "meta-platform/credentials"
	// DefaultTokenField is the default field key inside the secret for the Production Vault root token.
	DefaultTokenField = "prod_vault_root_token"
)

// DefaultProdTokenRef defines the standard KV-v2 reference where Production Vault root token is stored.
var DefaultProdTokenRef = vaultclient.SecretRef{
	Mount: DefaultTokenMount,
	Path:  DefaultTokenPath,
	Field: DefaultTokenField,
}

// ResolveProdTokenRef determines the KV-v2 secret reference, respecting environment overrides if configured.
func ResolveProdTokenRef() vaultclient.SecretRef {
	mount := os.Getenv("PROD_VAULT_TOKEN_MOUNT")
	if mount == "" {
		mount = DefaultTokenMount
	}
	path := os.Getenv("PROD_VAULT_TOKEN_PATH")
	if path == "" {
		path = DefaultTokenPath
	}
	field := os.Getenv("PROD_VAULT_TOKEN_FIELD")
	if field == "" {
		field = DefaultTokenField
	}
	return vaultclient.SecretRef{
		Mount: mount,
		Path:  path,
		Field: field,
	}
}

// CustomProdTokenRef constructs a SecretRef with fallbacks to default values when fields are empty.
func CustomProdTokenRef(mount, path, field string) vaultclient.SecretRef {
	if mount == "" {
		mount = DefaultTokenMount
	}
	if path == "" {
		path = DefaultTokenPath
	}
	if field == "" {
		field = DefaultTokenField
	}
	return vaultclient.SecretRef{
		Mount: mount,
		Path:  path,
		Field: field,
	}
}
