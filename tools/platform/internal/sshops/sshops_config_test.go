package sshops

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAddSSHIncludeDirectiveEmptyPathErrorsAndCreatesNothing(t *testing.T) {
	home := t.TempDir()
	err := AddSSHIncludeDirective(home, "")
	if err == nil || !strings.Contains(err.Error(), "no config path provided") {
		t.Fatalf("AddSSHIncludeDirective(home, \"\") = %v, want error containing \"no config path provided\"", err)
	}
	if _, statErr := os.Stat(filepath.Join(home, ".ssh", "config")); !os.IsNotExist(statErr) {
		t.Errorf("config file should not exist after empty-path error, stat err = %v", statErr)
	}
}

func TestAddSSHIncludeDirectiveCreatesFileFromScratch(t *testing.T) {
	home := t.TempDir()
	includePath := "/etc/ssh/conf.d/*"

	if err := AddSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("AddSSHIncludeDirective: %v", err)
	}

	configFile := filepath.Join(home, ".ssh", "config")
	data, err := os.ReadFile(configFile)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	want := "Include " + includePath + "\n"
	if string(data) != want {
		t.Errorf("config content = %q, want %q", string(data), want)
	}

	info, err := os.Stat(configFile)
	if err != nil {
		t.Fatalf("stat config: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("config mode = %v, want 0600", info.Mode().Perm())
	}
}

func TestAddSSHIncludeDirectivePrependsToExistingContent(t *testing.T) {
	home := t.TempDir()
	includePath := "/etc/ssh/conf.d/*"
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	configFile := filepath.Join(home, ".ssh", "config")
	oldContent := "Host foo\n  HostName foo.example.com\n"
	if err := os.WriteFile(configFile, []byte(oldContent), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	if err := AddSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("AddSSHIncludeDirective: %v", err)
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	want := "Include " + includePath + "\n" + oldContent
	if string(data) != want {
		t.Errorf("config content = %q, want %q", string(data), want)
	}
}

func TestAddSSHIncludeDirectiveNoOpWhenExactLinePresent(t *testing.T) {
	home := t.TempDir()
	includePath := "/etc/ssh/conf.d/*"
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	configFile := filepath.Join(home, ".ssh", "config")
	content := "Host foo\nInclude " + includePath + "\nHost bar\n"
	if err := os.WriteFile(configFile, []byte(content), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	if err := AddSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("AddSSHIncludeDirective: %v", err)
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if string(data) != content {
		t.Errorf("config content changed on no-op: got %q, want unchanged %q", string(data), content)
	}
}

func TestAddSSHIncludeDirectiveSimilarButNotExactLinesStillPrepend(t *testing.T) {
	includePath := "/etc/ssh/conf.d/*"
	cases := []string{
		"Include " + includePath + "extra\n",
		" Include " + includePath + "\n",
		"include " + includePath + "\n",
	}
	for _, oldContent := range cases {
		home := t.TempDir()
		if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
			t.Fatalf("mkdir: %v", err)
		}
		configFile := filepath.Join(home, ".ssh", "config")
		if err := os.WriteFile(configFile, []byte(oldContent), 0o600); err != nil {
			t.Fatalf("write fixture: %v", err)
		}

		if err := AddSSHIncludeDirective(home, includePath); err != nil {
			t.Fatalf("AddSSHIncludeDirective: %v", err)
		}

		data, err := os.ReadFile(configFile)
		if err != nil {
			t.Fatalf("read config: %v", err)
		}
		want := "Include " + includePath + "\n" + oldContent
		if string(data) != want {
			t.Errorf("for old content %q: config content = %q, want %q", oldContent, string(data), want)
		}
	}
}

func TestAddSSHIncludeDirectiveTwiceIsIdempotent(t *testing.T) {
	home := t.TempDir()
	includePath := "/etc/ssh/conf.d/*"

	if err := AddSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("first AddSSHIncludeDirective: %v", err)
	}
	if err := AddSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("second AddSSHIncludeDirective: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(home, ".ssh", "config"))
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	includeLine := "Include " + includePath
	count := 0
	for _, line := range strings.Split(string(data), "\n") {
		if line == includeLine {
			count++
		}
	}
	if count != 1 {
		t.Errorf("Include line appears %d times, want exactly 1; content = %q", count, string(data))
	}
}

func TestRemoveSSHIncludeDirectiveEmptyPathErrors(t *testing.T) {
	home := t.TempDir()
	err := RemoveSSHIncludeDirective(home, "")
	if err == nil || !strings.Contains(err.Error(), "no config path provided") {
		t.Fatalf("RemoveSSHIncludeDirective(home, \"\") = %v, want error containing \"no config path provided\"", err)
	}
}

func TestRemoveSSHIncludeDirectiveMissingFileReturnsNil(t *testing.T) {
	home := t.TempDir()
	if err := RemoveSSHIncludeDirective(home, "/etc/ssh/conf.d/*"); err != nil {
		t.Errorf("RemoveSSHIncludeDirective with no config file = %v, want nil", err)
	}
}

func TestRemoveSSHIncludeDirectiveRemovesOnlyMatchingLines(t *testing.T) {
	home := t.TempDir()
	includePath := "/etc/ssh/conf.d/*"
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	configFile := filepath.Join(home, ".ssh", "config")
	content := "Host foo\nInclude " + includePath + "\nHost bar\n"
	if err := os.WriteFile(configFile, []byte(content), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	if err := RemoveSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("RemoveSSHIncludeDirective: %v", err)
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	got := strings.Split(string(data), "\n")
	want := []string{"Host foo", "Host bar", ""}
	if len(got) != len(want) {
		t.Fatalf("lines = %q, want %q", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("line %d = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestRemoveSSHIncludeDirectiveRemovesDuplicateOccurrences(t *testing.T) {
	home := t.TempDir()
	includePath := "/etc/ssh/conf.d/*"
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	configFile := filepath.Join(home, ".ssh", "config")
	includeLine := "Include " + includePath
	content := includeLine + "\nHost foo\n" + includeLine + "\nHost bar\n"
	if err := os.WriteFile(configFile, []byte(content), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	if err := RemoveSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("RemoveSSHIncludeDirective: %v", err)
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if strings.Contains(string(data), includeLine) {
		t.Errorf("config still contains %q after removal: %q", includeLine, string(data))
	}
	for _, line := range strings.Split(string(data), "\n") {
		if line == includeLine {
			t.Errorf("found leftover Include line in %q", string(data))
		}
	}
}

func TestRemoveSSHIncludeDirectiveNoMatchPreservesContent(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	configFile := filepath.Join(home, ".ssh", "config")
	content := "Host foo\nHost bar\n"
	if err := os.WriteFile(configFile, []byte(content), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	if err := RemoveSSHIncludeDirective(home, "/etc/ssh/conf.d/*"); err != nil {
		t.Fatalf("RemoveSSHIncludeDirective: %v", err)
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if string(data) != content {
		t.Errorf("content changed on no-match rewrite: got %q, want %q", string(data), content)
	}
}

func TestAddThenRemoveSSHIncludeDirectiveRoundTrip(t *testing.T) {
	home := t.TempDir()
	includePath := "/etc/ssh/conf.d/*"

	if err := AddSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("AddSSHIncludeDirective: %v", err)
	}
	if err := RemoveSSHIncludeDirective(home, includePath); err != nil {
		t.Fatalf("RemoveSSHIncludeDirective: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(home, ".ssh", "config"))
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	includeLine := "Include " + includePath
	for _, line := range strings.Split(string(data), "\n") {
		if line == includeLine {
			t.Errorf("Include line still present after round trip: %q", string(data))
		}
	}
}
