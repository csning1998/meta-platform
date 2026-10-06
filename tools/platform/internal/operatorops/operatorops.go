// Package operatorops prepares a terraform run of a layer whose Vault provider logs in with the JWT-SVID of the
// Terraform operator of its component.
package operatorops

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
)

// DefaultWrapperDir is the directory where the play of provision-spire-parent installs the JWT-SVID wrappers.
const DefaultWrapperDir = "/usr/local/bin"

// JWTEnvKey is the variable which the Vault provider reads for block auth_login_jwt.
const JWTEnvKey = "TERRAFORM_VAULT_AUTH_JWT"

const wrapperPrefix = "spire-fetch-meta-platform-terraform-operator-"

var (
	// ErrLayerWithoutOperator reports a layer whose Vault provider does not log in with a JWT-SVID.
	ErrLayerWithoutOperator = errors.New("operatorops: layer does not log in with a JWT-SVID, run terraform directly")
	// ErrWrapperMissing reports an absent or non-executable JWT-SVID wrapper.
	ErrWrapperMissing = errors.New("operatorops: JWT-SVID wrapper is missing, apply provision-spire-parent first")
	// ErrJWTMissing reports a wrapper output without a non-empty jwt field.
	ErrJWTMissing = errors.New("operatorops: wrapper output carries no jwt field")
)

// layerOperators maps each layer to its operator. The Vault role of each operator binds one SPIFFE ID,
// hence a wrong entry fails the login.
var layerOperators = map[string]string{
	"platform-cilium-hubble":                "cilium-hubble",
	"provision-cilium-hubble":               "cilium-hubble",
	"platform-harbor-origin-frontend":       "harbor-origin-frontend",
	"provision-harbor-origin-frontend":      "harbor-origin-frontend",
	"provision-harbor-origin-oidc":          "harbor-origin-frontend",
	"platform-keycloak-frontend":            "keycloak-frontend",
	"provision-keycloak-oidc":               "keycloak-frontend",
	"platform-spire-child":                  "spire-child",
	"provision-spire-child":                 "spire-child",
	"provision-vault-oidc":                  "vault-downstream-frontend",
	"security-vault-downstream-credentials": "vault-downstream-frontend",
	"security-vault-downstream-pki":         "vault-downstream-frontend",
}

// Invocation is the program, the argument vector, and the environment which replace the current process.
type Invocation struct {
	Path string
	Args []string
	Env  []string
}

// ResolveOperator returns the operator whose JWT-SVID the Vault provider of layer presents.
func ResolveOperator(layer string) (string, error) {
	operator, ok := layerOperators[layer]
	if !ok {
		return "", fmt.Errorf("%w: %s", ErrLayerWithoutOperator, layer)
	}
	return operator, nil
}

// ResolveWrapperPath returns the path of the JWT-SVID wrapper of operator below wrapperDir.
func ResolveWrapperPath(wrapperDir, operator string) string {
	return filepath.Join(wrapperDir, wrapperPrefix+operator)
}

// FetchJWT runs the wrapper at wrapperPath and returns the jwt field of its JSON output.
// An error carries the stderr of the wrapper alone, since the stdout MAY hold a token.
func FetchJWT(ctx context.Context, wrapperPath string) (string, error) {
	info, err := os.Stat(wrapperPath)
	if err != nil || info.IsDir() || info.Mode().Perm()&0o111 == 0 {
		return "", fmt.Errorf("%w: %s", ErrWrapperMissing, wrapperPath)
	}

	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, wrapperPath)
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err = cmd.Run()
	if err != nil {
		return "", fmt.Errorf("operatorops: run %s: %w: %s", wrapperPath, err, strings.TrimSpace(stderr.String()))
	}

	if len(bytes.TrimSpace(stdout.Bytes())) == 0 {
		return "", fmt.Errorf("%w: %s printed nothing", ErrJWTMissing, wrapperPath)
	}
	var output struct {
		JWT *string `json:"jwt"`
	}
	err = json.Unmarshal(stdout.Bytes(), &output)
	if err != nil {
		return "", fmt.Errorf("operatorops: parse the output of %s: %w", wrapperPath, err)
	}
	if output.JWT == nil || *output.JWT == "" {
		return "", fmt.Errorf("%w: %s", ErrJWTMissing, wrapperPath)
	}
	return *output.JWT, nil
}

// BuildTerraformEnv returns base with JWTEnvKey set to jwt.
func BuildTerraformEnv(base []string, jwt string) []string {
	env := slices.DeleteFunc(slices.Clone(base), func(kv string) bool {
		return strings.HasPrefix(kv, JWTEnvKey+"=")
	})
	return append(env, JWTEnvKey+"="+jwt)
}

// PrepareTerraform returns the terraform invocation of the layer at layerDir with the JWT-SVID of its operator.
// Resolution of the layer and of terraform precedes the wrapper run, keeping a JWT-SVID out of an unstartable run.
func PrepareTerraform(ctx context.Context, wrapperDir, layerDir string, args, environ []string) (Invocation, error) {
	operator, err := ResolveOperator(filepath.Base(layerDir))
	if err != nil {
		return Invocation{}, err
	}
	terraform, err := exec.LookPath("terraform")
	if err != nil {
		return Invocation{}, fmt.Errorf("operatorops: %w", err)
	}
	jwt, err := FetchJWT(ctx, ResolveWrapperPath(wrapperDir, operator))
	if err != nil {
		return Invocation{}, err
	}
	return Invocation{
		Path: terraform,
		Args: append([]string{"terraform"}, args...),
		Env:  BuildTerraformEnv(environ, jwt),
	}, nil
}
