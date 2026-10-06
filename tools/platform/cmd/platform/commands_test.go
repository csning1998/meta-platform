package main

import (
	"testing"

	"github.com/spf13/cobra"
)

// TestTerraformCmdPassesEveryArgumentToTerraform covers subcommand names such as clean, which would shadow terraform arguments.
func TestTerraformCmdPassesEveryArgumentToTerraform(t *testing.T) {
	a := &app{}
	cmd := a.terraformCmd()
	if !cmd.DisableFlagParsing {
		t.Error("terraform parses flags, want every argument passed to terraform")
	}
	if cmd.HasSubCommands() {
		t.Errorf("terraform has %d subcommands, want none", len(cmd.Commands()))
	}
	if cmd.RunE == nil {
		t.Error("terraform has no RunE, want the terraform invocation")
	}
}

func TestLayerCmdRegistersClean(t *testing.T) {
	a := &app{}
	cmd, _, err := a.layerCmd().Find([]string{"clean"})
	if err != nil || cmd.Name() != "clean" {
		t.Fatalf("find clean: command %q, error %v, want command %q", cmd.Name(), err, "clean")
	}
	if cmd.Args == nil || cmd.Args(cmd, []string{"all"}) != nil || cmd.Args(cmd, nil) == nil {
		t.Error("layer clean accepts other than one argument, want exactly one layer or all")
	}
}

// TestIsBootstrapRequired covers terraform, which runs inside a layer directory and MUST leave .env untouched.
func TestIsBootstrapRequired(t *testing.T) {
	a := &app{}
	findLayerClean := func(t *testing.T) *cobra.Command {
		t.Helper()
		cmd, _, err := a.layerCmd().Find([]string{"clean"})
		if err != nil {
			t.Fatalf("find layer clean: %v", err)
		}
		return cmd
	}
	cases := []struct {
		name string
		cmd  func(t *testing.T) *cobra.Command
		want bool
	}{
		{"terraform", func(*testing.T) *cobra.Command { return a.terraformCmd() }, false},
		{"layer clean", findLayerClean, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := isBootstrapRequired(c.cmd(t))
			if got != c.want {
				t.Errorf("isBootstrapRequired(%s) = %v, want %v", c.name, got, c.want)
			}
		})
	}
}
