package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"platform/internal/clusterops"
)

// bastionOperator returns one entry of output downstream_vault_operators whose leaf resides on the Bastion Vault.
func bastionOperator(service, component string) map[string]any {
	return map[string]any{
		"auth_mount": "spire-parent-jwt-svid-provider",
		"role_name":  "example-platform-terraform-operator-" + service + "-" + component,
		"cluster_config": map[string]any{
			"vault": "bastion", "kv_mount": "secret", "kv_path": "example-platform/" + service + "/" + component + "/cluster-config",
		},
	}
}

// writeFakeBin writes an executable script below dir.
func writeFakeBin(t *testing.T, dir, name, body string) {
	t.Helper()
	err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"+body+"\n"), 0o700)
	if err != nil {
		t.Fatalf("write fake %s: %v", name, err)
	}
}

// newClusterEnvironment starts a Bastion Vault double which holds the leaf of vault-downstream/frontend alone, and
// points terraform, kubectl, the tenant session, and XDG_RUNTIME_DIR of the process at test doubles.
func newClusterEnvironment(t *testing.T) string {
	t.Helper()
	leaf := map[string]any{
		"content_b64":                  base64.StdEncoding.EncodeToString([]byte("kind: Config\n")),
		"talos_ca_certificate_b64":     "Y2E=",
		"talos_client_certificate_b64": "Y3J0",
		"talos_client_key_b64":         "a2V5",
	}
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/secret/data/example-platform/vault-downstream/frontend/cluster-config" || r.Header.Get("X-Vault-Token") != "s.tenant" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{"data": leaf, "metadata": map[string]any{}}})
	}))
	t.Cleanup(server.Close)

	root := t.TempDir()
	caFile := filepath.Join(root, "ca.crt")
	outputFile := filepath.Join(root, "output.json")
	output, err := json.Marshal(map[string]any{
		"downstream_vault_endpoint":     map[string]any{"value": server.URL},
		"downstream_vault_ca_cert_path": map[string]any{"value": caFile},
		"downstream_vault_operators": map[string]any{"value": map[string]any{
			"vault-downstream": map[string]any{"frontend": bastionOperator("vault-downstream", "frontend")},
			"harbor-origin":    map[string]any{"frontend": bastionOperator("harbor-origin", "frontend")},
		}},
	})
	if err != nil {
		t.Fatalf("marshal tenants output: %v", err)
	}
	for path, content := range map[string][]byte{
		caFile:     pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: server.Certificate().Raw}),
		outputFile: output,
	} {
		err := os.WriteFile(path, content, 0o600)
		if err != nil {
			t.Fatalf("write %s: %v", path, err)
		}
	}

	bin, runtime := t.TempDir(), t.TempDir()
	writeFakeBin(t, bin, "terraform", `cat "`+outputFile+`"`)
	writeFakeBin(t, bin, "kubectl", `case "$*" in *jsonpath*) printf '172.16.127.10 ' ;; *) echo "kubectl $*" ;; esac`)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("VAULT_ADDR", server.URL)
	t.Setenv("VAULT_TOKEN", "s.tenant")
	t.Setenv("VAULT_CACERT", caFile)
	t.Setenv("XDG_RUNTIME_DIR", runtime)
	return runtime
}

func assertNoSessionDir(t *testing.T, runtime string) {
	t.Helper()
	entries, err := os.ReadDir(runtime)
	if err != nil || len(entries) != 0 {
		t.Errorf("runtime directory holds %v, %v, want no session directory", entries, err)
	}
}

func TestReportClusterStatus_PrintsStatusAcrossClusters(t *testing.T) {
	cases := []struct {
		arg  string
		want []string
	}{
		{"all", []string{
			"Cluster harbor-origin/frontend", "No cluster-config, the component runs on the VM runtime.",
			"Cluster vault-downstream/frontend", "nodes: 172.16.127.10",
		}},
		{"vault-downstream/frontend", []string{"Cluster vault-downstream/frontend", "nodes: 172.16.127.10"}},
	}
	for _, c := range cases {
		t.Run(c.arg, func(t *testing.T) {
			runtime := newClusterEnvironment(t)
			a, out := newOperationsApp(t, "")
			err := a.reportClusterStatus(context.Background(), c.arg)
			if err != nil {
				t.Fatalf("reportClusterStatus(%s): %v", c.arg, err)
			}
			for _, want := range c.want {
				if !strings.Contains(out.String(), want) {
					t.Errorf("output = %q, want %q", out.String(), want)
				}
			}
			assertNoSessionDir(t, runtime)
		})
	}
}

func TestReportClusterStatus_RejectsInvalidTarget(t *testing.T) {
	cases := []struct {
		arg  string
		want error
	}{
		{"vault-downstream", clusterops.ErrInvalidTarget},
		{"harbor-origin/frontend", clusterops.ErrClusterConfigMissing},
	}
	for _, c := range cases {
		t.Run(c.arg, func(t *testing.T) {
			newClusterEnvironment(t)
			a, _ := newOperationsApp(t, "")
			err := a.reportClusterStatus(context.Background(), c.arg)
			if !errors.Is(err, c.want) {
				t.Errorf("reportClusterStatus(%s) error = %v, want %v", c.arg, err, c.want)
			}
		})
	}
}

// TestOpenClusterShell_PassesSessionEnvironment covers the exit status of the last command in the shell, which says nothing about the session.
func TestOpenClusterShell_PassesSessionEnvironment(t *testing.T) {
	runtime := newClusterEnvironment(t)
	dump := filepath.Join(t.TempDir(), "kubeconfig-of-shell")
	shell := filepath.Join(t.TempDir(), "shell")
	writeFakeBin(t, filepath.Dir(shell), "shell", `echo "$KUBECONFIG $PLATFORM_CLUSTER" > "`+dump+`"; exit 3`)
	t.Setenv("SHELL", shell)
	a, out := newOperationsApp(t, "")

	err := a.openClusterShell(context.Background(), "vault-downstream/frontend")
	if err != nil {
		t.Fatalf("openClusterShell: %v", err)
	}
	got, err := os.ReadFile(dump)
	if err != nil || !strings.HasPrefix(string(got), runtime) || !strings.HasSuffix(string(got), "/kubeconfig vault-downstream/frontend\n") {
		t.Errorf("shell environment = %q, %v, want the session kubeconfig below %s", got, err, runtime)
	}
	if !strings.Contains(out.String(), "Session shell exited with status 3.") {
		t.Errorf("output = %q, want the exit status as information", out.String())
	}
	assertNoSessionDir(t, runtime)
}

func TestOpenClusterShell_RejectsInvalidTarget(t *testing.T) {
	newClusterEnvironment(t)
	a, _ := newOperationsApp(t, "")
	err := a.openClusterShell(context.Background(), "keycloak")
	if !errors.Is(err, clusterops.ErrInvalidTarget) {
		t.Errorf("openClusterShell error = %v, want ErrInvalidTarget", err)
	}
}
