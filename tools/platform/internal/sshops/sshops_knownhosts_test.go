package sshops

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"

	"platform/internal/ui"
)

func TestScanKnownHostsNoHostsErrors(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	err := ScanKnownHosts(home, "myconfig", false, nil, ui.New(io.Discard, io.Discard))
	if err == nil || !strings.Contains(err.Error(), "no hosts provided") {
		t.Fatalf("ScanKnownHosts with no hosts = %v, want error containing \"no hosts provided\"", err)
	}
	if _, statErr := os.Stat(filepath.Join(home, ".ssh", "known_hosts_myconfig")); !os.IsNotExist(statErr) {
		t.Errorf("known_hosts file should not be created when no hosts provided, stat err = %v", statErr)
	}
}

func TestScanKnownHostsUnreachableHostsFail(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	configName := "myconfig"
	knownHostsFile := filepath.Join(home, ".ssh", "known_hosts_"+configName)
	// Asserts that ScanKnownHosts purges pre-existing known_hosts files prior to host key retrieval.
	if err := os.WriteFile(knownHostsFile, []byte("stale content\n"), 0o644); err != nil {
		t.Fatalf("write stale fixture: %v", err)
	}

	hosts := []string{"127.0.0.1:1", "does-not-resolve.invalid.test"}
	start := time.Now()
	err := ScanKnownHosts(home, configName, false, hosts, ui.New(io.Discard, io.Discard))
	elapsed := time.Since(start)

	if err == nil || !strings.Contains(err.Error(), "hosts failed to initialize SSH") {
		t.Fatalf("ScanKnownHosts with unreachable hosts = %v, want error containing \"hosts failed to initialize SSH\"", err)
	}
	if !strings.Contains(err.Error(), "2 hosts failed") {
		t.Errorf("error = %q, want failure count 2", err.Error())
	}
	if elapsed > 8*time.Second {
		t.Errorf("ScanKnownHosts took %v, want well under the 5s per-host timeout (hosts scan concurrently)", elapsed)
	}

	data, err := os.ReadFile(knownHostsFile)
	if err != nil {
		t.Fatalf("read known_hosts file: %v", err)
	}
	if strings.Contains(string(data), "stale content") {
		t.Errorf("known_hosts file still contains stale content: %q", string(data))
	}
}

// Excludes poll=true execution to prevent 150-second retry timeouts; core key retrieval logic is evaluated under poll=false.
func TestFetchHostKeyFailsFastOnUnreachableHost(t *testing.T) {
	done := make(chan struct{})
	var key string
	var err error
	go func() {
		key, err = fetchSingleHostKey("127.0.0.1", 500*time.Millisecond)
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("fetchSingleHostKey did not return within bound, want it to fail fast on connection refused/timeout")
	}

	if err == nil {
		t.Errorf("fetchSingleHostKey(127.0.0.1) = (%q, nil), want a non-nil error (nothing should be listening on :22 in this sandbox)", key)
	}
}

func TestScanHostKeysWrapsFetchFailure(t *testing.T) {
	var out, errOut bytes.Buffer
	line, err := scanMultipleHostKeys("127.0.0.1", false, ui.New(&out, &errOut))
	if err == nil {
		t.Fatalf("scanMultipleHostKeys(127.0.0.1, poll=false) = (%v, nil), want non-nil error", line)
	}
	if line != nil {
		t.Errorf("scanMultipleHostKeys returned non-nil bytes on failure: %q", line)
	}
	if !strings.Contains(out.String(), "Failed to scan") {
		t.Errorf("out = %q, want it to contain the \"Failed to scan\" Warn message", out.String())
	}
}

// Omits fetchSingleHostKey success path validation to avoid root privilege constraints on TCP port 22.
func TestKnownHostsLineFormat(t *testing.T) {
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate ed25519 key: %v", err)
	}
	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		t.Fatalf("NewPublicKey: %v", err)
	}

	cases := [][]string{
		{"host1"},
		{"host1", "10.0.0.1", "host1.example.com"},
	}
	for _, addrs := range cases {
		assertKnownHostsLineFormat(t, addrs, sshPub)
	}
}

func assertKnownHostsLineFormat(t *testing.T, addrs []string, sshPub ssh.PublicKey) {
	t.Helper()
	line := formatKnownHostsLine(addrs, sshPub)
	if !strings.HasSuffix(line, "\n") {
		t.Fatalf("formatKnownHostsLine(%v) = %q, want trailing newline", addrs, line)
	}

	trimmed := strings.TrimSuffix(line, "\n")
	assertKnownHostsLineFields(t, addrs, sshPub, trimmed)

	_, parsedAddrs, parsedKey, _, _, err := ssh.ParseKnownHosts([]byte(line))
	if err != nil {
		t.Fatalf("ParseKnownHosts(%q): %v", line, err)
	}
	if len(parsedAddrs) != len(addrs) {
		t.Errorf("ParseKnownHosts addrs = %v, want %v", parsedAddrs, addrs)
	}
	if parsedKey.Type() != sshPub.Type() || string(parsedKey.Marshal()) != string(sshPub.Marshal()) {
		t.Errorf("ParseKnownHosts key does not match original public key")
	}
}

func assertKnownHostsLineFields(t *testing.T, addrs []string, sshPub ssh.PublicKey, trimmed string) {
	t.Helper()
	if strings.HasSuffix(trimmed, " ") {
		t.Errorf("formatKnownHostsLine(%v) = %q, want no trailing space before the newline", addrs, trimmed)
	}
	if strings.Count(trimmed, "\n") != 0 {
		t.Errorf("formatKnownHostsLine(%v) contains more than one line: %q", addrs, trimmed)
	}

	fields := strings.SplitN(trimmed, " ", 3)
	if len(fields) != 3 {
		t.Fatalf("formatKnownHostsLine(%v) = %q, want exactly 3 space-separated fields", addrs, trimmed)
	}
	wantAddr := strings.Join(addrs, ",")
	if fields[0] != wantAddr {
		t.Errorf("address field = %q, want %q", fields[0], wantAddr)
	}
	if fields[1] != sshPub.Type() {
		t.Errorf("type field = %q, want %q", fields[1], sshPub.Type())
	}
	wantKey := base64.StdEncoding.EncodeToString(sshPub.Marshal())
	if fields[2] != wantKey {
		t.Errorf("key field = %q, want %q", fields[2], wantKey)
	}
}
