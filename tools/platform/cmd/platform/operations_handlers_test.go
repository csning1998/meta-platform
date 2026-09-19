package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gitlab.com/csning1998-lab/terraform/terraform-provider-sshclient/sshops"

	"platform/internal/config"
	"platform/internal/ui"
)

func generateTestCACert(t *testing.T, targetPath string) {
	t.Helper()
	caKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	caTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "TestCA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageCertSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(targetPath), 0o755); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(targetPath)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	if err := pem.Encode(f, &pem.Block{Type: "CERTIFICATE", Bytes: caDER}); err != nil {
		t.Fatal(err)
	}
}

func TestSSHLoggerPrintsEveryLevel(t *testing.T) {
	var out, errOut bytes.Buffer
	l := sshLogger{p: ui.New(&out, &errOut)}
	cases := []struct {
		name  string
		level sshops.Level
	}{
		{"step", sshops.Step},
		{"task", sshops.Task},
		{"warn", sshops.Warn},
		{"error", sshops.Error},
		{"ok", sshops.OK},
		{"info default", sshops.Info},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out.Reset()
			errOut.Reset()
			l.Print(c.level, "msg")
			got := out.String() + errOut.String()
			if !strings.Contains(got, "msg") {
				t.Errorf("Print(%s) output = %q, want it to contain msg", c.name, got)
			}
		})
	}
	out.Reset()
	l.PrintDivider("=")
	if !strings.Contains(out.String(), "=") {
		t.Errorf("PrintDivider output = %q, want '='", out.String())
	}
}

func TestReportVaultStatusUnreachableReturnsError(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	if err := a.reportVaultStatus(context.Background()); err == nil {
		t.Fatal("reportVaultStatus on unreachable vault: want error, got nil")
	}
}

func TestReportVaultStatusReachableReturnsNil(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/sys/seal-status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"initialized": true, "sealed": false})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	a, _ := newOperationsApp(t, "")
	a.bastionVaultAddr = srv.URL
	caCertPath := filepath.Join(a.root, "vault", "tls", "ca.pem")
	generateTestCACert(t, caCertPath)
	a.env.Set(config.KeyBastionVaultCACert, caCertPath)
	if err := a.reportVaultStatus(context.Background()); err != nil {
		t.Fatalf("reportVaultStatus on reachable vault: %v", err)
	}
}

func TestUnsealProdVaultMissingInventory(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	err := a.unsealProdVault(context.Background())
	if err == nil || !strings.Contains(err.Error(), "no Production Vault inventory") {
		t.Fatalf("unsealProdVault = %v, want no Production Vault inventory", err)
	}
}

func TestGenerateSSHKeyWritesPathIntoEnv(t *testing.T) {
	a, out := newOperationsApp(t, "")
	if err := a.generateSSHKey("id_test", false); err != nil {
		t.Fatalf("generateSSHKey: %v", err)
	}
	want := filepath.Join(a.home, ".ssh", "id_test")
	if got := a.env.Get(config.KeySSHPrivateKey); got != want {
		t.Errorf("SSH_PRIVATE_KEY = %q, want %q", got, want)
	}
	if _, err := os.Stat(want); err != nil {
		t.Errorf("private key missing: %v", err)
	}
	if !strings.Contains(out.String(), "ssh_private_key_path") {
		t.Errorf("output = %q, want terraform path hint", out.String())
	}
}

func TestGenerateSSHKeyRejectsInvalidName(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	err := a.generateSSHKey("..", false)
	if err == nil {
		t.Fatal("generateSSHKey(\"..\"): want error, got nil")
	}
}

func TestGenerateSSHKeySaveError(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("skipping read-only directory test when running as root")
	}
	a, _ := newOperationsApp(t, "")
	a.home = t.TempDir()
	if err := os.Chmod(a.root, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(a.root, 0o700) })
	if err := a.generateSSHKey("id_test", false); err == nil {
		t.Fatal("generateSSHKey: want Save error on read-only root, got nil")
	}
}

func TestVerifySSHConnectivityExistingKeyRunsVerify(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	keyPath := filepath.Join(a.home, "dummy-key")
	if err := os.WriteFile(keyPath, []byte("not-a-real-key"), 0o600); err != nil {
		t.Fatal(err)
	}
	a.env.Set(config.KeySSHPrivateKey, keyPath)
	err := a.verifySSHConnectivity()
	if err == nil {
		t.Fatal("verifySSHConnectivity with dummy key: want verify error, got nil")
	}
}

func TestVerifyEnvironmentReportsToolStatus(t *testing.T) {
	a, out := newOperationsApp(t, "")
	err := a.verifyEnvironment()
	if !strings.Contains(out.String(), "Checking") {
		t.Errorf("output = %q, want Checking group headers", out.String())
	}
	if err != nil && !strings.Contains(err.Error(), "verification failed: missing required tools:") {
		t.Fatalf("verifyEnvironment: %v", err)
	}
}

func TestRunHypervisorPlaybookCreateTempFailsWhenAnsibleDirMissing(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	err := a.runHypervisorPlaybook(context.Background())
	if err == nil || !strings.Contains(err.Error(), "create temporary inventory") {
		t.Fatalf("runHypervisorPlaybook missing ansibleDir = %v, want create temporary inventory", err)
	}
}

func TestRunHypervisorPlaybookFailsWhenPlaybookMissing(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	if err := os.MkdirAll(a.ansibleDir, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	err := a.runHypervisorPlaybook(ctx)
	if err == nil || !strings.Contains(err.Error(), "ansible-playbook") {
		t.Fatalf("runHypervisorPlaybook missing playbook = %v, want ansible-playbook error", err)
	}
}

func TestBuildPackerImageKnownBaseRunsCleanThenBuild(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	if err := os.MkdirAll(filepath.Join(a.packerDir, "distro"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(a.packerDir, "distro", "ubuntu-24.pkrvars.hcl"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	err := a.buildPackerImage(context.Background(), "ubuntu-24")
	if err == nil {
		t.Fatal("buildPackerImage(ubuntu-24): want packer error, got nil")
	}
}

func TestVaultStatusCommandRunsReportVaultStatus(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/sys/seal-status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"initialized": true, "sealed": false})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	a, _ := newOperationsApp(t, "")
	a.bastionVaultAddr = srv.URL
	caCertPath := filepath.Join(a.root, "vault", "tls", "ca.pem")
	generateTestCACert(t, caCertPath)
	a.env.Set(config.KeyBastionVaultCACert, caCertPath)
	cmd := a.vaultCmd()
	cmd.SetArgs([]string{"status"})
	cmd.SetOut(io.Discard)
	cmd.SetErr(io.Discard)
	if err := cmd.Execute(); err != nil {
		t.Fatalf("vault status: %v", err)
	}

	unreachableApp, _ := newOperationsApp(t, "")
	unreachableCmd := unreachableApp.vaultCmd()
	unreachableCmd.SetArgs([]string{"status"})
	unreachableCmd.SetOut(io.Discard)
	unreachableCmd.SetErr(io.Discard)
	if err := unreachableCmd.Execute(); err == nil {
		t.Fatal("vault status on unreachable vault: want error, got nil")
	}
}

func TestVaultUnsealProdCommandMissingInventory(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	cmd := a.vaultCmd()
	cmd.SetArgs([]string{"unseal-prod"})
	cmd.SetOut(io.Discard)
	cmd.SetErr(io.Discard)
	err := cmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "no Production Vault inventory") {
		t.Fatalf("vault unseal-prod = %v, want no Production Vault inventory", err)
	}
}

func TestPackerPurgeAllCommand(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	cmd := a.packerCmd()
	cmd.SetArgs([]string{"purge-all"})
	cmd.SetOut(io.Discard)
	cmd.SetErr(io.Discard)
	if err := cmd.Execute(); err != nil {
		t.Fatalf("packer purge-all: %v", err)
	}
}

func TestGitalyRevertPrecheckCommandAborted(t *testing.T) {
	a, out := newOperationsApp(t, "n\n")
	cmd := a.gitalyCmd()
	cmd.SetArgs([]string{"revert-precheck"})
	cmd.SetOut(io.Discard)
	cmd.SetErr(io.Discard)
	if err := cmd.Execute(); err != nil {
		t.Fatalf("gitaly revert-precheck abort: %v", err)
	}
	if !strings.Contains(out.String(), operationAbortedMsg) {
		t.Errorf("output = %q, want aborted message", out.String())
	}
}

func TestStrategySwitchCommand(t *testing.T) {
	a, _ := newOperationsApp(t, "")
	a.env.Set(config.KeyEnvironmentStrategy, config.StrategyNative)
	cmd := a.strategyCmd()
	cmd.SetArgs([]string{"switch"})
	cmd.SetOut(io.Discard)
	cmd.SetErr(io.Discard)
	if err := cmd.Execute(); err != nil {
		t.Fatalf("strategy switch: %v", err)
	}
	if got := a.env.Get(config.KeyEnvironmentStrategy); got != config.StrategyContainer {
		t.Errorf("strategy = %q, want %q", got, config.StrategyContainer)
	}
}
