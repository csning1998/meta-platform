package vaultops

import (
	"context"
	"net/http/httptest"
	"testing"

	vaultapi "github.com/hashicorp/vault/api"
)

func TestReadKVv2FieldConnectionRefusedYieldsOkFalse(t *testing.T) {
	cfg := vaultapi.DefaultConfig()
	cfg.Address = "http://127.0.0.1:1"
	client, err := vaultapi.NewClient(cfg)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}

	value, ok := ReadKVv2Field(context.Background(), client, "secret", "some/path", "field")
	if ok {
		t.Errorf("ok = true, want false")
	}
	if value != "" {
		t.Errorf("value = %q, want empty", value)
	}
}

func TestReadKVv2FieldFoundWithField(t *testing.T) {
	srv := httptest.NewServer(kvv2Handler(t, "/v1/secret/data/meta-platform/credentials", map[string]interface{}{
		"data": map[string]interface{}{
			"data": map[string]interface{}{
				"prod_vault_root_token": "s.prod-token",
			},
		},
	}))
	defer srv.Close()

	client := newTestVaultClient(t, srv.URL)
	value, ok := ReadKVv2Field(context.Background(), client, "secret", "meta-platform/credentials", "prod_vault_root_token")
	if !ok {
		t.Fatal("ok = false, want true")
	}
	if value != "s.prod-token" {
		t.Errorf("value = %q, want s.prod-token", value)
	}
}

func TestReadKVv2FieldFoundButFieldMissing(t *testing.T) {
	srv := httptest.NewServer(kvv2Handler(t, "/v1/secret/data/some/path", map[string]interface{}{
		"data": map[string]interface{}{
			"data": map[string]interface{}{
				"other_field": "value",
			},
		},
	}))
	defer srv.Close()

	client := newTestVaultClient(t, srv.URL)
	value, ok := ReadKVv2Field(context.Background(), client, "secret", "some/path", "missing_field")
	if ok {
		t.Errorf("ok = true, want false")
	}
	if value != "" {
		t.Errorf("value = %q, want empty", value)
	}
}

func TestReadKVv2FieldMalformedDataShape(t *testing.T) {
	srv := httptest.NewServer(kvv2Handler(t, "/v1/secret/data/some/path", map[string]interface{}{
		"data": "not-a-map",
	}))
	defer srv.Close()

	client := newTestVaultClient(t, srv.URL)
	value, ok := ReadKVv2Field(context.Background(), client, "secret", "some/path", "field")
	if ok {
		t.Errorf("ok = true, want false")
	}
	if value != "" {
		t.Errorf("value = %q, want empty", value)
	}
}
