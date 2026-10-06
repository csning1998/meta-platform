package main

import (
	"context"
	"fmt"
	"os"
	"syscall"

	"platform/internal/operatorops"
)

// runOperatorTerraform replaces the process with terraform, which keeps the JWT-SVID out of every child but terraform.
func (a *app) runOperatorTerraform(ctx context.Context, args []string) error {
	layerDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("terraform run: %w", err)
	}
	inv, err := operatorops.PrepareTerraform(ctx, operatorops.DefaultWrapperDir, layerDir, args, os.Environ())
	if err != nil {
		return err
	}
	err = syscall.Exec(inv.Path, inv.Args, inv.Env)
	return fmt.Errorf("terraform run: exec %s: %w", inv.Path, err)
}
