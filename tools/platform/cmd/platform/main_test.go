package main

import (
	"bufio"
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"platform/internal/config"
	"platform/internal/ui"
)

func TestSplitFields(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want []string
	}{
		{"empty", "", nil},
		{"only spaces", "   ", nil},
		{"single field", "a", []string{"a"}},
		{"two fields", "a b", []string{"a", "b"}},
		{"consecutive spaces", "a  b", []string{"a", "b"}},
		{"tab separator", "a\tb", []string{"a", "b"}},
		{"leading and trailing spaces", " a b ", []string{"a", "b"}},
		{"newline not a separator", "a\nb", []string{"a\nb"}},
		{"mixed tabs and spaces", "a\t \tb", []string{"a", "b"}},
		{"single space char", " ", nil},
		{"unicode content", "café latte", []string{"café", "latte"}},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			assertSplitWhitespaceFields(t, c.in, c.want)
		})
	}
}

func assertSplitWhitespaceFields(t *testing.T, in string, want []string) {
	t.Helper()
	got := splitWhitespaceFields(in)
	if len(want) == 0 {
		if len(got) != 0 {
			t.Fatalf("splitWhitespaceFields(%q) = %#v, want empty", in, got)
		}
		return
	}
	if len(got) != len(want) {
		t.Fatalf("splitWhitespaceFields(%q) = %#v, want %#v", in, got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("splitWhitespaceFields(%q) = %#v, want %#v", in, got, want)
		}
	}
}

func loadTestEnv(t *testing.T, content string) *config.Env {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, ".env")
	if content != "" {
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatalf("write fake .env: %v", err)
		}
	}
	env, err := config.Load(path)
	if err != nil {
		t.Fatalf("config.Load: %v", err)
	}
	return env
}

func TestAllBases(t *testing.T) {
	env := loadTestEnv(t, `ALL_PACKER_BASES="base-a base-b"`+"\n")
	got := getConfiguredPackerBases(env)
	want := []string{"base-a", "base-b"}
	if len(got) != len(want) {
		t.Fatalf("getConfiguredPackerBases = %#v, want %#v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("getConfiguredPackerBases = %#v, want %#v", got, want)
		}
	}
}

func TestAllBases_KeyAbsent(t *testing.T) {
	env := loadTestEnv(t, `ALL_TERRAFORM_LAYERS="layer-x"`+"\n")
	got := getConfiguredPackerBases(env)
	if len(got) != 0 {
		t.Fatalf("getConfiguredPackerBases with absent key = %#v, want empty", got)
	}
}

func TestAllTerraformLayers(t *testing.T) {
	env := loadTestEnv(t, `ALL_TERRAFORM_LAYERS="layer-x"`+"\n")
	got := getConfiguredTerraformLayers(env)
	want := []string{"layer-x"}
	if len(got) != len(want) {
		t.Fatalf("getConfiguredTerraformLayers = %#v, want %#v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("getConfiguredTerraformLayers = %#v, want %#v", got, want)
		}
	}
}

func TestAllTerraformLayers_KeyAbsent(t *testing.T) {
	env := loadTestEnv(t, `ALL_PACKER_BASES="base-a"`+"\n")
	got := getConfiguredTerraformLayers(env)
	if len(got) != 0 {
		t.Fatalf("getConfiguredTerraformLayers with absent key = %#v, want empty", got)
	}
}

func TestAppVaultPaths(t *testing.T) {
	a := &app{root: "/r", home: "/h", terraform: "/tf", ansibleDir: "/ans"}
	got := a.newVaultPaths()

	if got.ProjectRoot != "/r" {
		t.Errorf("ProjectRoot = %q, want %q", got.ProjectRoot, "/r")
	}
	if got.AnsibleDir != "/ans" {
		t.Errorf("AnsibleDir = %q, want %q", got.AnsibleDir, "/ans")
	}
	if got.TerraformDir != "/tf" {
		t.Errorf("TerraformDir = %q, want %q", got.TerraformDir, "/tf")
	}
	if got.Home != "/h" {
		t.Errorf("Home = %q, want %q", got.Home, "/h")
	}
}

// TestRunMenu_Quit drives runMenu with "Quit" selected (option 15, the last entry) via an
// in-memory reader, matching the one selection whose dispatch (chosen.run == nil) requires
// no real infrastructure.
func TestRunMenu_Quit(t *testing.T) {
	var buf bytes.Buffer
	dir := t.TempDir()
	env, err := config.Load(filepath.Join(dir, ".env"))
	if err != nil {
		t.Fatalf("config.Load: %v", err)
	}
	a := &app{
		root:      dir,
		home:      dir,
		terraform: filepath.Join(dir, "terraform"),
		env:       env,
		out:       ui.New(&buf, &buf),
		in:        bufio.NewReader(strings.NewReader("15\n")),
	}

	if err := a.runMenu(context.Background()); err != nil {
		t.Fatalf("runMenu quit path returned error: %v", err)
	}

	if !strings.Contains(buf.String(), "Exiting.") {
		t.Errorf("output missing exit message, got: %s", buf.String())
	}
}
