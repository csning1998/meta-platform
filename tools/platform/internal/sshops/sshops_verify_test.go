package sshops

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"platform/internal/ui"
)

func TestVerifyConnectivityMissingSSHDir(t *testing.T) {
	home := t.TempDir() // .ssh not created
	err := VerifyConnectivity(home, ui.New(io.Discard, io.Discard))
	if err == nil {
		t.Fatal("VerifyConnectivity with missing .ssh dir = nil, want error")
	}
	if !strings.Contains(err.Error(), "read") || !strings.Contains(err.Error(), filepath.Join(home, ".ssh")) {
		t.Errorf("error = %q, want it to contain \"read\" and %q", err.Error(), filepath.Join(home, ".ssh"))
	}
}

func TestVerifyConnectivityEmptySSHDir(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	err := VerifyConnectivity(home, ui.New(io.Discard, io.Discard))
	if err == nil || !strings.Contains(err.Error(), "no IaC SSH config files found") {
		t.Fatalf("VerifyConnectivity on empty .ssh dir = %v, want error containing \"no IaC SSH config files found\"", err)
	}
}

func TestVerifyConnectivityNoSSHPrefixedFiles(t *testing.T) {
	home := t.TempDir()
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	for _, name := range []string{"config", "known_hosts"} {
		if err := os.WriteFile(filepath.Join(sshDir, name), []byte(""), 0o600); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
	}
	err := VerifyConnectivity(home, ui.New(io.Discard, io.Discard))
	if err == nil || !strings.Contains(err.Error(), "no IaC SSH config files found") {
		t.Fatalf("VerifyConnectivity with only non-ssh_ files = %v, want error containing \"no IaC SSH config files found\"", err)
	}
}

func TestVerifyConnectivityMissingKnownHostsFileFails(t *testing.T) {
	home := t.TempDir()
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	content := "Host somehost\n  UserKnownHostsFile " + filepath.Join(sshDir, "known_hosts_missing") + "\n"
	if err := os.WriteFile(filepath.Join(sshDir, "ssh_1"), []byte(content), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	err := VerifyConnectivity(home, ui.New(io.Discard, io.Discard))
	if err == nil || !strings.Contains(err.Error(), "one or more SSH verification checks failed") {
		t.Fatalf("VerifyConnectivity with missing known_hosts = %v, want error containing \"one or more SSH verification checks failed\"", err)
	}
}

func TestVerifyConnectivityExpandedKnownHostsProceedsPastMissingCheck(t *testing.T) {
	home := t.TempDir()
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	knownHostsFile := filepath.Join(sshDir, "known_hosts_1")
	if err := os.WriteFile(knownHostsFile, []byte(""), 0o600); err != nil {
		t.Fatalf("write known_hosts: %v", err)
	}
	// "~/.ssh/known_hosts_1" expands via expandTildePath(home, ...) to knownHostsFile.
	content := "Host nonexistent-host-for-test\n  UserKnownHostsFile ~/.ssh/known_hosts_1\n"
	if err := os.WriteFile(filepath.Join(sshDir, "ssh_1"), []byte(content), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	var out, errOut bytes.Buffer
	err := VerifyConnectivity(home, ui.New(&out, &errOut))
	// Since the connection to a nonexistent host still fails, an overall error is expected.
	// The assertions below isolate which code path produced that error.
	if err == nil {
		t.Fatal("VerifyConnectivity = nil, want error (connection to nonexistent host must fail)")
	}
	if strings.Contains(errOut.String(), "Known hosts file not found") {
		t.Errorf("errOut contains \"Known hosts file not found\", want the known-hosts check to have passed: %q", errOut.String())
	}
	if !strings.Contains(errOut.String(), "Could not connect") {
		t.Errorf("errOut = %q, want it to contain \"Could not connect\" (proving the attempt-connection path was taken)", errOut.String())
	}
}

func TestVerifyConnectivityNoHostsIsSuccessWhenSoleConfig(t *testing.T) {
	home := t.TempDir()
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	knownHostsFile := filepath.Join(sshDir, "known_hosts_1")
	if err := os.WriteFile(knownHostsFile, []byte(""), 0o600); err != nil {
		t.Fatalf("write known_hosts: %v", err)
	}
	content := "UserKnownHostsFile " + knownHostsFile + "\n# no Host lines here\n"
	if err := os.WriteFile(filepath.Join(sshDir, "ssh_1"), []byte(content), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	var out, errOut bytes.Buffer
	if err := VerifyConnectivity(home, ui.New(&out, &errOut)); err != nil {
		t.Fatalf("VerifyConnectivity with a hostless config as the only file = %v, want nil", err)
	}
	if !strings.Contains(out.String(), "No hosts found") {
		t.Errorf("out = %q, want it to contain the \"No hosts found\" warning", out.String())
	}
}

func TestVerifyConnectivityAggregatesFailureAcrossMultipleFiles(t *testing.T) {
	home := t.TempDir()
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	knownHostsFile := filepath.Join(sshDir, "known_hosts_1")
	if err := os.WriteFile(knownHostsFile, []byte(""), 0o600); err != nil {
		t.Fatalf("write known_hosts: %v", err)
	}
	// The ssh_1_nohosts/ssh_2_missingkh names ensure os.ReadDir's sorted order processes
	// the passing config before the failing one, keeping the assertion deterministic.
	noHostsContent := "UserKnownHostsFile " + knownHostsFile + "\n# no Host lines\n"
	if err := os.WriteFile(filepath.Join(sshDir, "ssh_1_nohosts"), []byte(noHostsContent), 0o600); err != nil {
		t.Fatalf("write ssh_1_nohosts: %v", err)
	}
	missingKHContent := "Host somehost\n  UserKnownHostsFile " + filepath.Join(sshDir, "known_hosts_does_not_exist") + "\n"
	if err := os.WriteFile(filepath.Join(sshDir, "ssh_2_missingkh"), []byte(missingKHContent), 0o600); err != nil {
		t.Fatalf("write ssh_2_missingkh: %v", err)
	}

	err := VerifyConnectivity(home, ui.New(io.Discard, io.Discard))
	if err == nil {
		t.Fatal("VerifyConnectivity across a passing and a failing config = nil, want error")
	}
	if !strings.Contains(err.Error(), "one or more SSH verification checks failed") {
		t.Errorf("error = %q, want \"one or more SSH verification checks failed\"", err.Error())
	}
}

func TestVerifyConnectivityHostLineCapturesOnlyFirstToken(t *testing.T) {
	home := t.TempDir()
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	knownHostsFile := filepath.Join(sshDir, "known_hosts_1")
	if err := os.WriteFile(knownHostsFile, []byte(""), 0o600); err != nil {
		t.Fatalf("write known_hosts: %v", err)
	}
	content := "UserKnownHostsFile " + knownHostsFile + "\nHost a b c\n"
	if err := os.WriteFile(filepath.Join(sshDir, "ssh_1"), []byte(content), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	var out, errOut bytes.Buffer
	_ = VerifyConnectivity(home, ui.New(&out, &errOut))
	combined := out.String() + errOut.String()
	if !strings.Contains(combined, "Verifying connection to host: a...") {
		t.Errorf("output %q does not show host \"a\" being verified", combined)
	}
	if strings.Contains(combined, "host: b") || strings.Contains(combined, "host: c") {
		t.Errorf("output %q shows host \"b\" or \"c\" being verified, want only the first token \"a\" tracked", combined)
	}
}

func TestVerifyConnectivityUserKnownHostsFileMatchesMidLine(t *testing.T) {
	home := t.TempDir()
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	knownHostsFile := filepath.Join(sshDir, "known_hosts_1")
	if err := os.WriteFile(knownHostsFile, []byte(""), 0o600); err != nil {
		t.Fatalf("write known_hosts: %v", err)
	}
	// No leading "^" anchor on knownHostsLineRe: an indented/prefixed occurrence still matches.
	content := "  UserKnownHostsFile " + knownHostsFile + "\n# no Host lines\n"
	if err := os.WriteFile(filepath.Join(sshDir, "ssh_1"), []byte(content), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	var out, errOut bytes.Buffer
	if err := VerifyConnectivity(home, ui.New(&out, &errOut)); err != nil {
		t.Fatalf("VerifyConnectivity with indented UserKnownHostsFile = %v, want nil", err)
	}
	if strings.Contains(errOut.String(), "Known hosts file not found") {
		t.Errorf("errOut = %q, want the indented UserKnownHostsFile line to have matched", errOut.String())
	}
}

func TestVerifyConnectivityOnlyFirstUserKnownHostsFileHonored(t *testing.T) {
	home := t.TempDir()
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	validKnownHosts := filepath.Join(sshDir, "known_hosts_valid")
	if err := os.WriteFile(validKnownHosts, []byte(""), 0o600); err != nil {
		t.Fatalf("write known_hosts: %v", err)
	}
	invalidKnownHosts := filepath.Join(sshDir, "known_hosts_does_not_exist")
	content := "UserKnownHostsFile " + validKnownHosts + "\n" +
		"UserKnownHostsFile " + invalidKnownHosts + "\n" +
		"# no Host lines\n"
	if err := os.WriteFile(filepath.Join(sshDir, "ssh_1"), []byte(content), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	var out, errOut bytes.Buffer
	if err := VerifyConnectivity(home, ui.New(&out, &errOut)); err != nil {
		t.Fatalf("VerifyConnectivity = %v, want nil (first UserKnownHostsFile line should be honored)", err)
	}
	if strings.Contains(errOut.String(), "Known hosts file not found") {
		t.Errorf("errOut = %q, want no known-hosts-missing error since the first line points at a valid file", errOut.String())
	}
}
