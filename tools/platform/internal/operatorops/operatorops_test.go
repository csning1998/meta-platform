package operatorops

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// layersDir is the terraform/layers directory of the repository, relative to this package.
const layersDir = "../../../../terraform/layers"

func TestResolveOperator(t *testing.T) {
	cases := []struct {
		layer string
		want  string
	}{
		{"platform-cilium-hubble", "cilium-hubble"},
		{"provision-cilium-hubble", "cilium-hubble"},
		{"platform-harbor-origin-frontend", "harbor-origin-frontend"},
		{"provision-harbor-origin-frontend", "harbor-origin-frontend"},
		{"provision-harbor-origin-oidc", "harbor-origin-frontend"},
		{"platform-keycloak-frontend", "keycloak-frontend"},
		{"provision-keycloak-oidc", "keycloak-frontend"},
		{"platform-spire-child", "spire-child"},
		{"provision-spire-child", "spire-child"},
		{"provision-vault-oidc", "vault-downstream-frontend"},
		{"security-vault-downstream-credentials", "vault-downstream-frontend"},
		{"security-vault-downstream-pki", "vault-downstream-frontend"},
	}
	for _, c := range cases {
		t.Run(c.layer, func(t *testing.T) {
			got, err := ResolveOperator(c.layer)
			if err != nil || got != c.want {
				t.Errorf("ResolveOperator(%q) = %q, %v, want %q, nil", c.layer, got, err, c.want)
			}
		})
	}
}

func TestResolveOperatorRejectsLayerWithoutJWTLogin(t *testing.T) {
	for _, layer := range []string{
		"foundation-libvirt-resources",
		"provision-spire-parent",
		"security-vault-downstream-tenants",
		"",
		"keycloak-oidc",
		"provision-keycloak-oidc/",
	} {
		t.Run(layer, func(t *testing.T) {
			got, err := ResolveOperator(layer)
			if !errors.Is(err, ErrLayerWithoutOperator) {
				t.Fatalf("ResolveOperator(%q) = %q, %v, want ErrLayerWithoutOperator", layer, got, err)
			}
			if !strings.Contains(err.Error(), layer) {
				t.Errorf("ResolveOperator(%q) error = %q, want the layer name in the message", layer, err)
			}
		})
	}
}

// TestResolveOperatorMatchesTheProviders fails when a layer gains or loses block auth_login_jwt without the table.
func TestResolveOperatorMatchesTheProviders(t *testing.T) {
	files, err := filepath.Glob(filepath.Join(layersDir, "*", "*.tf"))
	if err != nil || len(files) == 0 {
		t.Fatalf("glob %s: %d files, %v", layersDir, len(files), err)
	}
	jwtLayers := map[string]bool{}
	allLayers := map[string]bool{}
	for _, file := range files {
		layer := filepath.Base(filepath.Dir(file))
		allLayers[layer] = true
		content, err := os.ReadFile(file)
		if err != nil {
			t.Fatalf("read %s: %v", file, err)
		}
		if strings.Contains(string(content), "auth_login_jwt") {
			jwtLayers[layer] = true
		}
	}
	for layer := range allLayers {
		_, err := ResolveOperator(layer)
		if jwtLayers[layer] && err != nil {
			t.Errorf("layer %s declares auth_login_jwt, but ResolveOperator returns %v", layer, err)
		}
		if !jwtLayers[layer] && err == nil {
			t.Errorf("layer %s declares no auth_login_jwt, but ResolveOperator resolves an operator", layer)
		}
	}
}

func TestResolveWrapperPath(t *testing.T) {
	got := ResolveWrapperPath("/usr/local/bin", "keycloak-frontend")
	want := "/usr/local/bin/spire-fetch-meta-platform-terraform-operator-keycloak-frontend"
	if got != want {
		t.Errorf("ResolveWrapperPath = %q, want %q", got, want)
	}
}

// writeFakeExecutable writes an executable script below dir which stands in for a wrapper or for terraform.
func writeFakeExecutable(t *testing.T, dir, name, body string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	err := os.WriteFile(path, []byte("#!/bin/sh\n"+body+"\n"), 0o700)
	if err != nil {
		t.Fatalf("write fake executable: %v", err)
	}
	return path
}

// isPathPresent reports whether path exists, which the fixtures use to detect a wrapper run.
func isPathPresent(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func TestFetchJWT(t *testing.T) {
	cases := []struct {
		name string
		body string
		want string
	}{
		{"jwt field", `printf '{"jwt":"eyJhbGciOi.payload.signature"}\n'`, "eyJhbGciOi.payload.signature"},
		{"extra fields", `printf '{"jwt":"eyJ.a.b","expires_at":1}'`, "eyJ.a.b"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			wrapper := writeFakeExecutable(t, t.TempDir(), "wrapper", c.body)
			got, err := FetchJWT(context.Background(), wrapper)
			if err != nil || got != c.want {
				t.Errorf("FetchJWT = %q, %v, want %q, nil", got, err, c.want)
			}
		})
	}
}

func TestFetchJWTRejectsOutputWithoutJWT(t *testing.T) {
	for _, c := range []struct{ name, body string }{
		{"empty jwt", `printf '{"jwt":""}'`},
		{"null jwt", `printf '{"jwt":null}'`},
		{"absent jwt", `printf '{"token":"eyJ.a.b"}'`},
		{"empty output", `true`},
	} {
		t.Run(c.name, func(t *testing.T) {
			wrapper := writeFakeExecutable(t, t.TempDir(), "wrapper", c.body)
			got, err := FetchJWT(context.Background(), wrapper)
			if !errors.Is(err, ErrJWTMissing) || got != "" {
				t.Errorf("FetchJWT = %q, %v, want \"\", ErrJWTMissing", got, err)
			}
		})
	}
}

// TestFetchJWTKeepsTheOutputOutOfTheError covers output which fails to parse and MAY still hold a token.
func TestFetchJWTKeepsTheOutputOutOfTheError(t *testing.T) {
	for _, c := range []struct{ name, body string }{
		{"truncated object", `printf '{"jwt":"eyJsecret.payload.sig"'`},
		{"non-string jwt", `printf '{"jwt":["eyJsecret.payload.sig"]}'`},
	} {
		t.Run(c.name, func(t *testing.T) {
			wrapper := writeFakeExecutable(t, t.TempDir(), "wrapper", c.body)
			got, err := FetchJWT(context.Background(), wrapper)
			if err == nil || got != "" {
				t.Fatalf("FetchJWT = %q, %v, want \"\" and a parse error", got, err)
			}
			if strings.Contains(err.Error(), "eyJsecret") {
				t.Errorf("FetchJWT error = %q, want no wrapper output in the message", err)
			}
		})
	}
}

func TestFetchJWTReportsTheWrapperFailure(t *testing.T) {
	wrapper := writeFakeExecutable(t, t.TempDir(), "wrapper",
		`echo "spire-agent exited 1: connect: no such file or directory" >&2; exit 1`)
	_, err := FetchJWT(context.Background(), wrapper)
	if err == nil || errors.Is(err, ErrJWTMissing) {
		t.Fatalf("FetchJWT error = %v, want the wrapper failure", err)
	}
	if !strings.Contains(err.Error(), "connect: no such file or directory") {
		t.Errorf("FetchJWT error = %q, want the stderr of the wrapper", err)
	}
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) || exitErr.ExitCode() != 1 {
		t.Errorf("FetchJWT error = %v, want exit status 1 in the chain", err)
	}
}

func TestFetchJWTRejectsMissingWrapper(t *testing.T) {
	dir := t.TempDir()
	nonExecutable := filepath.Join(dir, "non-executable")
	err := os.WriteFile(nonExecutable, []byte("#!/bin/sh\n"), 0o600)
	if err != nil {
		t.Fatalf("write non-executable wrapper: %v", err)
	}
	for name, path := range map[string]string{
		"absent":         filepath.Join(dir, "absent"),
		"non-executable": nonExecutable,
		"directory":      dir,
	} {
		t.Run(name, func(t *testing.T) {
			_, err := FetchJWT(context.Background(), path)
			if !errors.Is(err, ErrWrapperMissing) {
				t.Fatalf("FetchJWT(%s) error = %v, want ErrWrapperMissing", name, err)
			}
			if !strings.Contains(err.Error(), path) {
				t.Errorf("FetchJWT(%s) error = %q, want the wrapper path in the message", name, err)
			}
		})
	}
}

func TestBuildTerraformEnv(t *testing.T) {
	cases := []struct {
		name string
		base []string
		want []string
	}{
		{"absent key", []string{"PATH=/bin"}, []string{"PATH=/bin", JWTEnvKey + "=new"}},
		{"stale key", []string{JWTEnvKey + "=old", "PATH=/bin"}, []string{"PATH=/bin", JWTEnvKey + "=new"}},
		{"duplicate keys", []string{JWTEnvKey + "=a", "PATH=/bin", JWTEnvKey + "=b"}, []string{"PATH=/bin", JWTEnvKey + "=new"}},
		{"prefix of another key", []string{JWTEnvKey + "_X=keep"}, []string{JWTEnvKey + "_X=keep", JWTEnvKey + "=new"}},
		{"empty base", nil, []string{JWTEnvKey + "=new"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			base := slices.Clone(c.base)
			got := BuildTerraformEnv(base, "new")
			if !slices.Equal(got, c.want) {
				t.Errorf("BuildTerraformEnv = %q, want %q", got, c.want)
			}
			if !slices.Equal(base, c.base) {
				t.Errorf("BuildTerraformEnv mutated base to %q", base)
			}
		})
	}
}

// prepareFixture holds a layer directory, a wrapper directory, and a PATH with a fake terraform.
type prepareFixture struct {
	layerDir   string
	wrapperDir string
	terraform  string
	marker     string
}

func newPrepareFixture(t *testing.T, layer string) prepareFixture {
	t.Helper()
	root := t.TempDir()
	f := prepareFixture{
		layerDir:   filepath.Join(root, "layers", layer),
		wrapperDir: filepath.Join(root, "wrappers"),
		marker:     filepath.Join(root, "wrapper-ran"),
	}
	binDir := filepath.Join(root, "bin")
	for _, dir := range []string{f.layerDir, f.wrapperDir, binDir} {
		err := os.MkdirAll(dir, 0o700)
		if err != nil {
			t.Fatalf("mkdir %s: %v", dir, err)
		}
	}
	writeFakeExecutable(t, f.wrapperDir, "spire-fetch-meta-platform-terraform-operator-keycloak-frontend",
		`touch "`+f.marker+`"; printf '{"jwt":"eyJ.keycloak.sig"}'`)
	f.terraform = writeFakeExecutable(t, binDir, "terraform", "exit 0")
	t.Setenv("PATH", binDir)
	return f
}

func TestPrepareTerraform(t *testing.T) {
	f := newPrepareFixture(t, "provision-keycloak-oidc")
	environ := []string{"PATH=" + filepath.Dir(f.terraform), "VAULT_TOKEN=tenant"}

	got, err := PrepareTerraform(context.Background(), f.wrapperDir, f.layerDir, []string{"plan", "-out=tfplan"}, environ)
	if err != nil {
		t.Fatalf("PrepareTerraform: %v", err)
	}
	if got.Path != f.terraform {
		t.Errorf("Path = %q, want %q", got.Path, f.terraform)
	}
	wantArgs := []string{"terraform", "plan", "-out=tfplan"}
	if !slices.Equal(got.Args, wantArgs) {
		t.Errorf("Args = %q, want %q", got.Args, wantArgs)
	}
	wantEnv := append(slices.Clone(environ), JWTEnvKey+"=eyJ.keycloak.sig")
	if !slices.Equal(got.Env, wantEnv) {
		t.Errorf("Env = %q, want %q", got.Env, wantEnv)
	}
}

func TestPrepareTerraformSkipsTheWrapperOfLayerWithoutJWTLogin(t *testing.T) {
	f := newPrepareFixture(t, "foundation-libvirt-resources")

	_, err := PrepareTerraform(context.Background(), f.wrapperDir, f.layerDir, []string{"plan"}, nil)
	if !errors.Is(err, ErrLayerWithoutOperator) {
		t.Errorf("PrepareTerraform error = %v, want ErrLayerWithoutOperator", err)
	}
	if isPathPresent(f.marker) {
		t.Error("PrepareTerraform ran a wrapper for a layer without JWT login")
	}
}

func TestPrepareTerraformRejectsMissingTerraform(t *testing.T) {
	f := newPrepareFixture(t, "provision-keycloak-oidc")
	t.Setenv("PATH", t.TempDir())

	_, err := PrepareTerraform(context.Background(), f.wrapperDir, f.layerDir, []string{"plan"}, nil)
	if !errors.Is(err, exec.ErrNotFound) {
		t.Errorf("PrepareTerraform error = %v, want exec.ErrNotFound", err)
	}
	if isPathPresent(f.marker) {
		t.Error("PrepareTerraform fetched a JWT-SVID although terraform is absent")
	}
}
