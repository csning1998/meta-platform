package vaultops

import (
	"testing"
)

func TestResolveProdTokenRefDefaults(t *testing.T) {
	ref := ResolveProdTokenRef()
	if ref.Mount != DefaultTokenMount {
		t.Errorf("Mount = %q, want %q", ref.Mount, DefaultTokenMount)
	}
	if ref.Path != DefaultTokenPath {
		t.Errorf("Path = %q, want %q", ref.Path, DefaultTokenPath)
	}
	if ref.Field != DefaultTokenField {
		t.Errorf("Field = %q, want %q", ref.Field, DefaultTokenField)
	}
}

func TestResolveProdTokenRefEnvOverrides(t *testing.T) {
	t.Setenv("PROD_VAULT_TOKEN_MOUNT", "custom-secret")
	t.Setenv("PROD_VAULT_TOKEN_PATH", "custom/path")
	t.Setenv("PROD_VAULT_TOKEN_FIELD", "custom_token")

	ref := ResolveProdTokenRef()
	if ref.Mount != "custom-secret" {
		t.Errorf("Mount = %q, want custom-secret", ref.Mount)
	}
	if ref.Path != "custom/path" {
		t.Errorf("Path = %q, want custom/path", ref.Path)
	}
	if ref.Field != "custom_token" {
		t.Errorf("Field = %q, want custom_token", ref.Field)
	}
}

func TestCustomProdTokenRefFallback(t *testing.T) {
	ref := CustomProdTokenRef("", "", "")
	if ref.Mount != DefaultTokenMount || ref.Path != DefaultTokenPath || ref.Field != DefaultTokenField {
		t.Errorf("CustomProdTokenRef empty = %+v, want defaults", ref)
	}

	custom := CustomProdTokenRef("m", "p", "f")
	if custom.Mount != "m" || custom.Path != "p" || custom.Field != "f" {
		t.Errorf("CustomProdTokenRef custom = %+v, want m/p/f", custom)
	}
}

func TestPathsWithProdTokenRef(t *testing.T) {
	p := Paths{}
	if got := p.resolveProdTokenRef(); got.Mount != DefaultTokenMount {
		t.Errorf("default resolveProdTokenRef = %+v, want default mount", got)
	}

	custom := CustomProdTokenRef("my-mount", "my-path", "my-field")
	p = p.WithProdTokenRef(custom)
	if got := p.resolveProdTokenRef(); got != custom {
		t.Errorf("configured resolveProdTokenRef = %+v, want %+v", got, custom)
	}
}
