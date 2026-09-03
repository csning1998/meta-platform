package sshops

import (
	"io"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/crypto/ssh"

	"platform/internal/ui"
)

func TestExpandHome(t *testing.T) {
	cases := []struct {
		path, home, want string
	}{
		{"~/.ssh/known_hosts", "/home/tester", "/home/tester/.ssh/known_hosts"},
		{"/absolute/path", "/home/tester", "/absolute/path"},
		{"relative/path", "/home/tester", "relative/path"},
		{"~", "/home/tester", "~"},
		{"~otheruser/foo", "/home/tester", "~otheruser/foo"},
	}
	for _, tc := range cases {
		if got := expandTildePath(tc.home, tc.path); got != tc.want {
			t.Errorf("expandTildePath(%q, %q) = %q, want %q", tc.home, tc.path, got, tc.want)
		}
	}
}

func TestKeyExists(t *testing.T) {
	if KeyExists("") {
		t.Error("KeyExists(\"\") = true, want false")
	}

	dir := t.TempDir()
	missing := filepath.Join(dir, "nope")
	if KeyExists(missing) {
		t.Errorf("KeyExists(%q) = true, want false", missing)
	}

	present := filepath.Join(dir, "id_ed25519")
	if err := os.WriteFile(present, []byte("fake"), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	if !KeyExists(present) {
		t.Errorf("KeyExists(%q) = false, want true", present)
	}
}

func TestGenerateKeyRefusesOverwriteByDefault(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	existing := filepath.Join(home, ".ssh", "id_ed25519_test")
	if err := os.WriteFile(existing, []byte("fake"), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	if _, err := GenerateKey(home, "id_ed25519_test", false, ui.New(io.Discard, io.Discard)); err == nil {
		t.Error("GenerateKey over an existing key without overwrite = nil error, want error")
	}
}

func TestGenerateKeyWritesValidOpenSSHFiles(t *testing.T) {
	home := t.TempDir()

	privPath, err := GenerateKey(home, "id_ed25519_test", false, ui.New(io.Discard, io.Discard))
	if err != nil {
		t.Fatalf("GenerateKey: %v", err)
	}

	if _, err := os.Stat(privPath); err != nil {
		t.Errorf("private key not written at %s: %v", privPath, err)
	}
	pubData, err := os.ReadFile(privPath + ".pub")
	if err != nil {
		t.Fatalf("read public key: %v", err)
	}
	if len(pubData) == 0 {
		t.Error("public key file is empty")
	}

	info, err := os.Stat(privPath)
	if err != nil {
		t.Fatalf("stat private key: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("private key mode = %v, want 0600", info.Mode().Perm())
	}
}

func TestGenerateKeyOverwriteReplacesExistingKey(t *testing.T) {
	home := t.TempDir()
	keyName := "id_ed25519_overwrite"
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	privPath := filepath.Join(home, ".ssh", keyName)
	if err := os.WriteFile(privPath, []byte("not a real key"), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	gotPath, err := GenerateKey(home, keyName, true, ui.New(io.Discard, io.Discard))
	if err != nil {
		t.Fatalf("GenerateKey(overwrite=true): %v", err)
	}
	if gotPath != privPath {
		t.Errorf("GenerateKey returned %q, want %q", gotPath, privPath)
	}

	privData, err := os.ReadFile(privPath)
	if err != nil {
		t.Fatalf("read private key: %v", err)
	}
	if _, err := ssh.ParseRawPrivateKey(privData); err != nil {
		t.Errorf("overwritten private key is not a valid OpenSSH PEM: %v", err)
	}
	if _, err := ssh.ParsePrivateKey(privData); err != nil {
		t.Errorf("overwritten private key does not parse as ssh.Signer: %v", err)
	}

	pubData, err := os.ReadFile(privPath + ".pub")
	if err != nil {
		t.Fatalf("read public key: %v", err)
	}
	pubKey, comment, _, _, err := ssh.ParseAuthorizedKey(pubData)
	if err != nil {
		t.Fatalf("ParseAuthorizedKey: %v", err)
	}
	if pubKey.Type() != "ssh-ed25519" {
		t.Errorf("public key type = %q, want ssh-ed25519", pubKey.Type())
	}
	if comment != keyName {
		t.Errorf("public key comment = %q, want %q", comment, keyName)
	}
}

func TestGenerateKeyCreatesMissingSSHDir(t *testing.T) {
	home := t.TempDir() // .ssh is NOT pre-created

	privPath, err := GenerateKey(home, "id_ed25519_nodir", false, ui.New(io.Discard, io.Discard))
	if err != nil {
		t.Fatalf("GenerateKey with no pre-existing .ssh dir: %v", err)
	}
	if _, err := os.Stat(privPath); err != nil {
		t.Errorf("private key not written at %s: %v", privPath, err)
	}
}
