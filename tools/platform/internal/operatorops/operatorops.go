// Package operatorops prepares a terraform run of a layer whose Vault provider logs in with the JWT-SVID of the
// Terraform operator of its component.
package operatorops

import (
	"context"
	"errors"
)

// DefaultWrapperDir is the directory where the play of provision-spire-parent installs the JWT-SVID wrappers.
const DefaultWrapperDir = "/usr/local/bin"

// JWTEnvKey is the variable which the Vault provider reads for block auth_login_jwt.
const JWTEnvKey = "TERRAFORM_VAULT_AUTH_JWT"

var (
	// ErrLayerWithoutOperator reports a layer whose Vault provider does not log in with a JWT-SVID.
	ErrLayerWithoutOperator = errors.New("operatorops: layer does not log in with a JWT-SVID, run terraform directly")
	// ErrWrapperMissing reports an absent or non-executable JWT-SVID wrapper.
	ErrWrapperMissing = errors.New("operatorops: JWT-SVID wrapper is missing, apply provision-spire-parent first")
	// ErrJWTMissing reports a wrapper output without a non-empty jwt field.
	ErrJWTMissing = errors.New("operatorops: wrapper output carries no jwt field")
)

// Invocation is the program, the argument vector, and the environment which replace the current process.
type Invocation struct {
	Path string
	Args []string
	Env  []string
}

// ResolveOperator returns the operator whose JWT-SVID the Vault provider of layer presents.
func ResolveOperator(layer string) (string, error) {
	return "", nil
}

// ResolveWrapperPath returns the path of the JWT-SVID wrapper of operator below wrapperDir.
func ResolveWrapperPath(wrapperDir, operator string) string {
	return ""
}

// FetchJWT runs the wrapper at wrapperPath and returns the jwt field of its JSON output.
func FetchJWT(ctx context.Context, wrapperPath string) (string, error) {
	return "", nil
}

// BuildTerraformEnv returns base with JWTEnvKey set to jwt.
func BuildTerraformEnv(base []string, jwt string) []string {
	return base
}

// PrepareTerraform returns the terraform invocation of the layer at layerDir with the JWT-SVID of its operator.
func PrepareTerraform(ctx context.Context, wrapperDir, layerDir string, args, environ []string) (Invocation, error) {
	return Invocation{}, nil
}
