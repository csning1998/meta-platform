package clusterops

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"platform/internal/operatorops"
)

func TestParseTarget_ExtractsServiceAndComponent(t *testing.T) {
	cases := []struct {
		arg  string
		want operatorops.OperatorSubject
	}{
		{"keycloak/frontend", operatorops.OperatorSubject{Service: "keycloak", Component: "frontend"}},
		{"vault-downstream/frontend", operatorops.OperatorSubject{Service: "vault-downstream", Component: "frontend"}},
		{"gitlab/praefect-patroni", operatorops.OperatorSubject{Service: "gitlab", Component: "praefect-patroni"}},
		{"s3/v2", operatorops.OperatorSubject{Service: "s3", Component: "v2"}},
	}
	for _, c := range cases {
		t.Run(c.arg, func(t *testing.T) {
			got, err := ParseTarget(c.arg)
			if err != nil || got != c.want {
				t.Errorf("ParseTarget(%q) = %+v, %v, want %+v, nil", c.arg, got, err, c.want)
			}
		})
	}
}

func TestParseTarget_RejectsInvalidArgument(t *testing.T) {
	for _, arg := range []string{
		"", "keycloak", "keycloak/", "/frontend", "/",
		"gitlab/praefect/patroni", "keycloak//frontend",
		"Keycloak/frontend", "keycloak/front end", "keycloak/front_end",
		"-keycloak/frontend", "keycloak-/frontend", "key--cloak/frontend",
		"../frontend", "keycloak/..", " keycloak/frontend", "keycloak/frontend\n",
	} {
		t.Run(arg, func(t *testing.T) {
			got, err := ParseTarget(arg)
			if !errors.Is(err, ErrInvalidTarget) {
				t.Errorf("ParseTarget(%q) = %+v, %v, want ErrInvalidTarget", arg, got, err)
			}
		})
	}
}

// tenantsOutput mirrors terraform output -json of security-vault-downstream-tenants, including outputs B3 ignores.
const tenantsOutput = `{
  "downstream_vault_endpoint": {"sensitive": false, "type": "string", "value": "https://172.16.127.250:443"},
  "downstream_vault_ca_cert_path": {"sensitive": false, "type": "string", "value": "/repo/terraform/layers/platform-vault-downstream-frontend/tls/listener-ca-chain.crt"},
  "downstream_vault_service_vip": {"sensitive": false, "type": "string", "value": "172.16.127.250"},
  "downstream_vault_operators": {"sensitive": false, "type": ["object", {}], "value": {
    "keycloak": {"frontend": {
      "auth_mount": "spire-parent-jwt-svid-provider", "role_name": "platform-foundation-terraform-operator-keycloak-frontend",
      "audience": "vault", "wrapper_name": "spire-fetch-platform-foundation-terraform-operator-keycloak-frontend",
      "cluster_name": "platform-foundation-keycloak-frontend", "cluster_issuer_policy": "p", "external_secrets_policy": null,
      "cluster_config": {"vault": "downstream", "kv_mount": "secret", "kv_path": "platform-foundation/keycloak/frontend/cluster-config"}}},
    "vault-downstream": {"frontend": {
      "auth_mount": "spire-parent-jwt-svid-provider", "role_name": "platform-foundation-terraform-operator-vault-downstream-frontend",
      "audience": "vault", "wrapper_name": "w", "cluster_name": "c", "cluster_issuer_policy": null, "external_secrets_policy": null,
      "cluster_config": {"vault": "bastion", "kv_mount": "secret", "kv_path": "platform-foundation/vault-downstream/frontend/cluster-config"}}},
    "gitlab": {
      "praefect-patroni": {"auth_mount": "m", "role_name": "r", "cluster_config": {"vault": "downstream", "kv_mount": "secret", "kv_path": "platform-foundation/gitlab/praefect-patroni/cluster-config"}},
      "praefect": {"auth_mount": "m", "role_name": "r", "cluster_config": {"vault": "downstream", "kv_mount": "secret", "kv_path": "platform-foundation/gitlab/praefect/cluster-config"}}
    }
  }}
}`

func TestDecodeCoordinates_ExtractsOperators(t *testing.T) {
	got, err := DecodeCoordinates([]byte(tenantsOutput))
	if err != nil {
		t.Fatalf("DecodeCoordinates: %v", err)
	}
	if got.Address != "https://172.16.127.250:443" || !strings.HasSuffix(got.CACertPath, "/tls/listener-ca-chain.crt") {
		t.Errorf("Address, CACertPath = %q, %q", got.Address, got.CACertPath)
	}
	want := Operator{
		AuthMount: "spire-parent-jwt-svid-provider",
		RoleName:  "platform-foundation-terraform-operator-keycloak-frontend",
		ClusterConfig: ClusterConfig{
			Vault: "downstream", KVMount: "secret", KVPath: "platform-foundation/keycloak/frontend/cluster-config",
		},
	}
	if got.Operators["keycloak"]["frontend"] != want {
		t.Errorf("keycloak/frontend = %+v, want %+v", got.Operators["keycloak"]["frontend"], want)
	}
	if got.Operators["vault-downstream"]["frontend"].ClusterConfig.Vault != "bastion" {
		t.Errorf("vault-downstream/frontend = %+v, want the Bastion Vault", got.Operators["vault-downstream"]["frontend"])
	}
}

// replaceJSON returns tenantsOutput with old replaced once by new, failing when old is absent.
func replaceJSON(t *testing.T, old, new string) []byte {
	t.Helper()
	if !strings.Contains(tenantsOutput, old) {
		t.Fatalf("tenantsOutput holds no %q", old)
	}
	return []byte(strings.Replace(tenantsOutput, old, new, 1))
}

func TestDecodeCoordinates_RejectsIncompleteOutput(t *testing.T) {
	cases := map[string]struct {
		input []byte
		want  string
	}{
		"not json":          {[]byte("Error: Backend initialization required"), "clusterops"},
		"empty state":       {[]byte("{}"), "downstream_vault_endpoint"},
		"no operators":      {replaceJSON(t, `"downstream_vault_operators"`, `"renamed_operators"`), "downstream_vault_operators"},
		"no ca":             {replaceJSON(t, `"downstream_vault_ca_cert_path"`, `"renamed_ca"`), "downstream_vault_ca_cert_path"},
		"unknown vault":     {replaceJSON(t, `"vault": "bastion"`, `"vault": "production"`), "production"},
		"empty kv path":     {replaceJSON(t, `"kv_path": "platform-foundation/keycloak/frontend/cluster-config"`, `"kv_path": ""`), "keycloak/frontend"},
		"empty role":        {replaceJSON(t, `"role_name": "platform-foundation-terraform-operator-keycloak-frontend"`, `"role_name": ""`), "keycloak/frontend"},
		"no cluster config": {replaceJSON(t, `"cluster_config": {"vault": "downstream", "kv_mount": "secret", "kv_path": "platform-foundation/gitlab/praefect/cluster-config"}`, `"cluster_config": null`), "gitlab/praefect"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := DecodeCoordinates(c.input)
			if err == nil || !strings.Contains(err.Error(), c.want) {
				t.Errorf("DecodeCoordinates error = %v, want an error which contains %q", err, c.want)
			}
		})
	}
}

func TestResolveOperator_ResolvesRegisteredOperator(t *testing.T) {
	coordinates, err := DecodeCoordinates([]byte(tenantsOutput))
	if err != nil {
		t.Fatalf("DecodeCoordinates: %v", err)
	}
	got, err := coordinates.ResolveOperator(operatorops.OperatorSubject{Service: "gitlab", Component: "praefect-patroni"})
	if err != nil || got.ClusterConfig.KVPath != "platform-foundation/gitlab/praefect-patroni/cluster-config" {
		t.Errorf("ResolveOperator(gitlab/praefect-patroni) = %+v, %v", got, err)
	}

	for _, target := range []operatorops.OperatorSubject{
		{Service: "gitlab", Component: "patroni"},
		{Service: "gitlab-praefect", Component: "patroni"},
		{Service: "harbor", Component: "frontend"},
	} {
		_, err := coordinates.ResolveOperator(target)
		if !errors.Is(err, ErrUnknownTarget) || !strings.Contains(err.Error(), "keycloak/frontend") {
			t.Errorf("ResolveOperator(%+v) error = %v, want ErrUnknownTarget which lists the known targets", target, err)
		}
	}
}

func TestListTargets_ReturnsSortedTargets(t *testing.T) {
	coordinates, err := DecodeCoordinates([]byte(tenantsOutput))
	if err != nil {
		t.Fatalf("DecodeCoordinates: %v", err)
	}
	want := []operatorops.OperatorSubject{
		{Service: "gitlab", Component: "praefect"},
		{Service: "gitlab", Component: "praefect-patroni"},
		{Service: "keycloak", Component: "frontend"},
		{Service: "vault-downstream", Component: "frontend"},
	}
	got := coordinates.ListTargets()
	if !slices.Equal(got, want) {
		t.Errorf("ListTargets = %+v, want %+v", got, want)
	}
}

// writeExecutable writes an executable script below dir which stands in for terraform or kubectl.
func writeExecutable(t *testing.T, dir, name, body string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	err := os.WriteFile(path, []byte("#!/bin/sh\n"+body+"\n"), 0o700)
	if err != nil {
		t.Fatalf("write fake %s: %v", name, err)
	}
	return path
}

func TestReadCoordinates_ParsesTerraformOutput(t *testing.T) {
	bin := t.TempDir()
	argsFile := filepath.Join(bin, "args")
	outputFile := filepath.Join(bin, "output.json")
	err := os.WriteFile(outputFile, []byte(tenantsOutput), 0o600)
	if err != nil {
		t.Fatalf("write output fixture: %v", err)
	}
	writeExecutable(t, bin, "terraform", `echo "$@" > "`+argsFile+`"; cat "`+outputFile+`"`)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	got, err := ReadCoordinates(context.Background(), "/repo/terraform/layers/security-vault-downstream-tenants")
	if err != nil || got.Address != "https://172.16.127.250:443" {
		t.Fatalf("ReadCoordinates = %+v, %v", got, err)
	}
	args, err := os.ReadFile(argsFile)
	if err != nil {
		t.Fatalf("read terraform arguments: %v", err)
	}
	want := "-chdir=/repo/terraform/layers/security-vault-downstream-tenants output -json\n"
	if string(args) != want {
		t.Errorf("terraform arguments = %q, want %q", args, want)
	}
}

func TestReadCoordinates_ReportsTerraformFailure(t *testing.T) {
	bin := t.TempDir()
	writeExecutable(t, bin, "terraform", `echo "Error: HTTP remote state endpoint requires auth" >&2; exit 1`)
	t.Setenv("PATH", bin)

	_, err := ReadCoordinates(context.Background(), "/repo/terraform/layers/security-vault-downstream-tenants")
	if err == nil || !strings.Contains(err.Error(), "requires auth") {
		t.Errorf("ReadCoordinates error = %v, want the stderr of terraform", err)
	}
}

// vaultFixture is a TLS Vault double and the PEM file of its certificate.
type vaultFixture struct {
	server   *httptest.Server
	caFile   string
	mu       sync.Mutex
	requests []string
}

// recorded returns the requests which the double received so far.
func (f *vaultFixture) recorded() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.requests)
}

func newVaultFixture(t *testing.T, secrets map[string]map[string]any) *vaultFixture {
	t.Helper()
	f := &vaultFixture{}
	f.server = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		f.requests = append(f.requests, r.Method+" "+r.URL.Path+" token="+r.Header.Get("X-Vault-Token"))
		f.mu.Unlock()
		switch {
		case r.URL.Path == "/v1/auth/spire-parent-jwt-svid-provider/login":
			var body map[string]string
			err := json.NewDecoder(r.Body).Decode(&body)
			if err != nil || body["role"] != "platform-foundation-terraform-operator-keycloak-frontend" || body["jwt"] != "eyJ.keycloak.sig" {
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"auth": map[string]any{"client_token": "s.downstream"}})
		case strings.HasPrefix(r.URL.Path, "/v1/secret/data/"):
			data, ok := secrets[strings.TrimPrefix(r.URL.Path, "/v1/secret/data/")]
			if !ok {
				w.WriteHeader(http.StatusNotFound)
				_, _ = w.Write([]byte(`{"errors":[]}`))
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{"data": data, "metadata": map[string]any{}}})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(f.server.Close)
	f.caFile = writePEM(t, f.server.Certificate().Raw)
	return f
}

func writePEM(t *testing.T, der []byte) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "ca.crt")
	err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600)
	if err != nil {
		t.Fatalf("write CA file: %v", err)
	}
	return path
}

// createForeignCA returns a self-signed CA certificate which signed none of the certificates of the test servers.
// Every httptest TLS server shares one built-in certificate, hence a second server cannot stand in for a foreign CA.
func createForeignCA(t *testing.T) []byte {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate CA key: %v", err)
	}
	template := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "foreign test CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("create CA certificate: %v", err)
	}
	return der
}

var keycloakOperator = Operator{
	AuthMount: "spire-parent-jwt-svid-provider",
	RoleName:  "platform-foundation-terraform-operator-keycloak-frontend",
	ClusterConfig: ClusterConfig{
		Vault: "downstream", KVMount: "secret", KVPath: "platform-foundation/keycloak/frontend/cluster-config",
	},
}

func clusterConfigSecret() map[string]any {
	return map[string]any{
		"content_b64":                  base64.StdEncoding.EncodeToString([]byte("apiVersion: v1\nkind: Config\n")),
		"talos_ca_certificate_b64":     "Y2E=",
		"talos_client_certificate_b64": "Y3J0",
		"talos_client_key_b64":         "a2V5",
	}
}

func TestLoginDownstream_AuthenticatesAndReadsCredential(t *testing.T) {
	f := newVaultFixture(t, map[string]map[string]any{"platform-foundation/keycloak/frontend/cluster-config": clusterConfigSecret()})

	client, err := LoginDownstream(context.Background(), f.server.URL, f.caFile, keycloakOperator, "eyJ.keycloak.sig")
	if err != nil {
		t.Fatalf("LoginDownstream: %v", err)
	}
	got, err := ReadCredential(context.Background(), client, keycloakOperator.ClusterConfig)
	if err != nil {
		t.Fatalf("ReadCredential: %v", err)
	}
	if string(got.Kubeconfig) != "apiVersion: v1\nkind: Config\n" || got.TalosCA != "Y2E=" || got.TalosCert != "Y3J0" || got.TalosKey != "a2V5" {
		t.Errorf("ReadCredential = %+v", got)
	}
	wantRead := "GET /v1/secret/data/platform-foundation/keycloak/frontend/cluster-config token=s.downstream"
	if !slices.Contains(f.recorded(), wantRead) {
		t.Errorf("requests = %q, want %q", f.recorded(), wantRead)
	}
}

// TestLoginDownstream_VerifiesListenerAgainstCACert covers the curl -k of the shell script, which this package MUST NOT repeat.
func TestLoginDownstream_VerifiesListenerAgainstCACert(t *testing.T) {
	f := newVaultFixture(t, nil)

	for name, caFile := range map[string]string{
		"foreign CA": writePEM(t, createForeignCA(t)),
		"absent CA":  filepath.Join(t.TempDir(), "absent.crt"),
	} {
		t.Run(name, func(t *testing.T) {
			_, err := LoginDownstream(context.Background(), f.server.URL, caFile, keycloakOperator, "eyJ.keycloak.sig")
			if err == nil {
				t.Fatal("LoginDownstream error = nil, want a TLS verification failure")
			}
			if strings.Contains(err.Error(), "eyJ.keycloak.sig") {
				t.Errorf("LoginDownstream error = %q, want no JWT in the message", err)
			}
		})
	}
	if len(f.recorded()) != 0 {
		t.Errorf("requests = %q, want none before a verified handshake", f.recorded())
	}
}

func TestLoginDownstream_RejectsDeniedLogin(t *testing.T) {
	f := newVaultFixture(t, nil)
	_, err := LoginDownstream(context.Background(), f.server.URL, f.caFile, keycloakOperator, "eyJ.other.sig")
	if err == nil || strings.Contains(err.Error(), "eyJ.other.sig") {
		t.Errorf("LoginDownstream error = %v, want a login failure without the JWT", err)
	}
}

func TestNewBastionClient_ReadsTenantSession(t *testing.T) {
	f := newVaultFixture(t, map[string]map[string]any{"platform-foundation/vault-downstream/frontend/cluster-config": clusterConfigSecret()})
	env := map[string]string{"VAULT_ADDR": f.server.URL, "VAULT_TOKEN": "s.tenant", "VAULT_CACERT": f.caFile}

	client, err := NewBastionClient(func(key string) string { return env[key] })
	if err != nil {
		t.Fatalf("NewBastionClient: %v", err)
	}
	_, err = ReadCredential(context.Background(), client, ClusterConfig{
		Vault: "bastion", KVMount: "secret", KVPath: "platform-foundation/vault-downstream/frontend/cluster-config",
	})
	if err != nil {
		t.Fatalf("ReadCredential: %v", err)
	}
	want := "GET /v1/secret/data/platform-foundation/vault-downstream/frontend/cluster-config token=s.tenant"
	if !slices.Contains(f.recorded(), want) {
		t.Errorf("requests = %q, want %q", f.recorded(), want)
	}
}

func TestNewBastionClient_RequiresTenantSession(t *testing.T) {
	for name, env := range map[string]map[string]string{
		"no address": {"VAULT_TOKEN": "s.tenant"},
		"no token":   {"VAULT_ADDR": "https://172.16.0.1:8200"},
		"empty":      {},
	} {
		t.Run(name, func(t *testing.T) {
			_, err := NewBastionClient(func(key string) string { return env[key] })
			if !errors.Is(err, ErrTenantSessionMissing) {
				t.Errorf("NewBastionClient error = %v, want ErrTenantSessionMissing", err)
			}
		})
	}
}

func TestReadCredential_RejectsIncompleteLeaf(t *testing.T) {
	invalid := clusterConfigSecret()
	invalid["content_b64"] = "not base64 secret-material"
	absentKey := clusterConfigSecret()
	delete(absentKey, "talos_client_key_b64")
	f := newVaultFixture(t, map[string]map[string]any{
		"platform-foundation/a/invalid/cluster-config":    invalid,
		"platform-foundation/a/absent-key/cluster-config": absentKey,
	})
	env := map[string]string{"VAULT_ADDR": f.server.URL, "VAULT_TOKEN": "s.tenant", "VAULT_CACERT": f.caFile}
	client, err := NewBastionClient(func(key string) string { return env[key] })
	if err != nil {
		t.Fatalf("NewBastionClient: %v", err)
	}

	cases := map[string]struct {
		path      string
		wantIs    error
		wantField string
	}{
		"absent leaf":    {"platform-foundation/a/vm-runtime/cluster-config", ErrClusterConfigMissing, ""},
		"invalid base64": {"platform-foundation/a/invalid/cluster-config", nil, "content_b64"},
		"absent field":   {"platform-foundation/a/absent-key/cluster-config", nil, "talos_client_key_b64"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := ReadCredential(context.Background(), client, ClusterConfig{Vault: "bastion", KVMount: "secret", KVPath: c.path})
			if err == nil {
				t.Fatal("ReadCredential error = nil")
			}
			if c.wantIs != nil && !errors.Is(err, c.wantIs) {
				t.Errorf("ReadCredential error = %v, want %v", err, c.wantIs)
			}
			if !strings.Contains(err.Error(), c.wantField) || strings.Contains(err.Error(), "secret-material") {
				t.Errorf("ReadCredential error = %q, want the field %q and no secret value", err, c.wantField)
			}
		})
	}
}

func TestRenderTalosconfig_RendersEndpointsAndCertificates(t *testing.T) {
	cred := Credential{TalosCA: "Y2E=", TalosCert: "Y3J0", TalosKey: "a2V5"}
	target := operatorops.OperatorSubject{Service: "gitlab", Component: "praefect-patroni"}

	got := RenderTalosconfig(target, []string{"172.16.140.10", "172.16.140.11"}, cred)
	want := "context: gitlab/praefect-patroni\n" +
		"contexts:\n" +
		"  gitlab/praefect-patroni:\n" +
		"    endpoints: [172.16.140.10, 172.16.140.11]\n" +
		"    nodes: [172.16.140.10, 172.16.140.11]\n" +
		"    ca: Y2E=\n" +
		"    crt: Y3J0\n" +
		"    key: a2V5\n"
	if got != want {
		t.Errorf("RenderTalosconfig =\n%s\nwant\n%s", got, want)
	}

	// An unreachable API server leaves the endpoints to talosctl --endpoints.
	got = RenderTalosconfig(target, nil, cred)
	if strings.Contains(got, "endpoints:") || strings.Contains(got, "nodes:") || !strings.Contains(got, "    key: a2V5\n") {
		t.Errorf("RenderTalosconfig without nodes =\n%s", got)
	}
}

func TestListNodeAddresses_ParsesInternalIPs(t *testing.T) {
	bin := t.TempDir()
	argsFile := filepath.Join(bin, "args")
	writeExecutable(t, bin, "kubectl", `echo "$@" > "`+argsFile+`"; printf '172.16.140.10 172.16.140.11 '`)
	t.Setenv("PATH", bin)
	t.Setenv("KUBECONFIG", "/home/operator/.kube/other-cluster")

	got, err := ListNodeAddresses(context.Background(), "/run/user/1000/platform-cluster-1/kubeconfig")
	if err != nil || !slices.Equal(got, []string{"172.16.140.10", "172.16.140.11"}) {
		t.Errorf("ListNodeAddresses = %q, %v", got, err)
	}
	args, err := os.ReadFile(argsFile)
	if err != nil {
		t.Fatalf("read kubectl arguments: %v", err)
	}
	if !strings.Contains(string(args), "--kubeconfig /run/user/1000/platform-cluster-1/kubeconfig") {
		t.Errorf("kubectl arguments = %q, want the session kubeconfig over KUBECONFIG of the parent", args)
	}
}

func TestListNodeAddresses_ReportsKubectlFailure(t *testing.T) {
	bin := t.TempDir()
	writeExecutable(t, bin, "kubectl", `echo "Unable to connect to the server: dial tcp: i/o timeout" >&2; exit 1`)
	t.Setenv("PATH", bin)

	_, err := ListNodeAddresses(context.Background(), "/run/user/1000/platform-cluster-1/kubeconfig")
	if err == nil || !strings.Contains(err.Error(), "i/o timeout") {
		t.Errorf("ListNodeAddresses error = %v, want the stderr of kubectl", err)
	}
}

func TestResolveRuntimeDir_PrefersXDGRuntimeDir(t *testing.T) {
	got := ResolveRuntimeDir(func(key string) string { return map[string]string{"XDG_RUNTIME_DIR": "/run/user/1000"}[key] })
	if got != "/run/user/1000" {
		t.Errorf("ResolveRuntimeDir = %q, want XDG_RUNTIME_DIR", got)
	}
	got = ResolveRuntimeDir(func(string) string { return "" })
	if got != os.TempDir() {
		t.Errorf("ResolveRuntimeDir without XDG_RUNTIME_DIR = %q, want %q", got, os.TempDir())
	}
}

// TestCreateSessionDir_CreatesDistinctDirectories covers concurrent sessions of one cluster and a shared /tmp, which a fixed name would expose.
func TestCreateSessionDir_CreatesDistinctDirectories(t *testing.T) {
	base := t.TempDir()
	first, err := CreateSessionDir(base)
	if err != nil {
		t.Fatalf("CreateSessionDir: %v", err)
	}
	second, err := CreateSessionDir(base)
	if err != nil {
		t.Fatalf("CreateSessionDir: %v", err)
	}
	if first == second || filepath.Dir(first) != base {
		t.Errorf("CreateSessionDir = %q, %q, want two distinct directories below %q", first, second, base)
	}
	info, err := os.Stat(first)
	if err != nil || info.Mode().Perm() != 0o700 {
		t.Errorf("session directory mode = %v, %v, want 0700", info, err)
	}

	_, err = CreateSessionDir(filepath.Join(base, "absent"))
	if err == nil {
		t.Error("CreateSessionDir below an absent base = nil error")
	}
}

func TestWriteSessionFile_WritesOwnerOnlyPermissions(t *testing.T) {
	dir, err := CreateSessionDir(t.TempDir())
	if err != nil {
		t.Fatalf("CreateSessionDir: %v", err)
	}
	path, err := WriteSessionFile(dir, "kubeconfig", []byte("apiVersion: v1\n"))
	if err != nil || path != filepath.Join(dir, "kubeconfig") {
		t.Fatalf("WriteSessionFile = %q, %v", path, err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Errorf("kubeconfig mode = %v, %v, want 0600", info, err)
	}

	for _, name := range []string{"../kubeconfig", "sub/kubeconfig", "", "."} {
		_, err := WriteSessionFile(dir, name, []byte("x"))
		if err == nil {
			t.Errorf("WriteSessionFile(%q) = nil error, want a rejection of a name outside the session directory", name)
		}
	}
}

func TestBuildShellEnv_ConfiguresSessionVariables(t *testing.T) {
	base := []string{"PATH=/bin", "KUBECONFIG=/old/kubeconfig", "TALOSCONFIG=/old/talosconfig", "PLATFORM_CLUSTER=spire/child", "VAULT_TOKEN=s.tenant"}
	original := slices.Clone(base)
	target := operatorops.OperatorSubject{Service: "gitlab", Component: "praefect-patroni"}

	got := BuildShellEnv(base, "/run/user/1000/platform-cluster-1", target)
	want := []string{
		"PATH=/bin", "VAULT_TOKEN=s.tenant",
		"KUBECONFIG=/run/user/1000/platform-cluster-1/kubeconfig",
		"TALOSCONFIG=/run/user/1000/platform-cluster-1/talosconfig",
		"PLATFORM_CLUSTER=gitlab/praefect-patroni",
	}
	if !slices.Equal(got, want) {
		t.Errorf("BuildShellEnv = %q, want %q", got, want)
	}
	if !slices.Equal(base, original) {
		t.Errorf("BuildShellEnv mutated base to %q", base)
	}
}

// newSessionWithFile returns a session directory which holds one kubeconfig.
func newSessionWithFile(t *testing.T) string {
	t.Helper()
	dir, err := CreateSessionDir(t.TempDir())
	if err != nil {
		t.Fatalf("CreateSessionDir: %v", err)
	}
	_, err = WriteSessionFile(dir, "kubeconfig", []byte("x"))
	if err != nil {
		t.Fatalf("WriteSessionFile: %v", err)
	}
	return dir
}

func assertPathRemoved(t *testing.T, path string) {
	t.Helper()
	_, err := os.Stat(path)
	if !errors.Is(err, os.ErrNotExist) {
		t.Errorf("%s after the session: %v, want removed", path, err)
	}
}

func TestRunSession_RemovesDirectoryAfterRun(t *testing.T) {
	failure := errors.New("shell failed")
	for name, runErr := range map[string]error{"success": nil, "failure": failure} {
		t.Run(name, func(t *testing.T) {
			dir := newSessionWithFile(t)
			var gotEnv []string
			err := RunSession(context.Background(), dir, []string{"A=1"}, func(_ context.Context, env []string) error {
				gotEnv = env
				return runErr
			})
			if !errors.Is(err, runErr) || !slices.Equal(gotEnv, []string{"A=1"}) {
				t.Errorf("RunSession = %v with env %q, want %v with env [A=1]", err, gotEnv, runErr)
			}
			assertPathRemoved(t, dir)
		})
	}
}
