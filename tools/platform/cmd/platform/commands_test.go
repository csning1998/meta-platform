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

func TestHostsCmdRegistersSyncWithDryRunDefault(t *testing.T) {
	a := &app{}
	cmd, _, err := a.hostsCmd().Find([]string{"sync"})
	if err != nil || cmd.Name() != "sync" {
		t.Fatalf("find sync: command %q, error %v, want command %q", cmd.Name(), err, "sync")
	}
	flag := cmd.Flags().Lookup("apply")
	if flag == nil || flag.DefValue != "false" {
		t.Errorf("hosts sync flag apply = %v, want a flag with default false", flag)
	}
}

func TestClusterCmdRegistersShellAndStatus(t *testing.T) {
	a := &app{}
	for _, name := range []string{"shell", "status"} {
		t.Run(name, func(t *testing.T) {
			cmd, _, err := a.clusterCmd().Find([]string{name})
			if err != nil || cmd.Name() != name {
				t.Fatalf("find %s: command %q, error %v", name, cmd.Name(), err)
			}
			if cmd.Args == nil || cmd.Args(cmd, []string{"keycloak/frontend"}) != nil || cmd.Args(cmd, nil) == nil ||
				cmd.Args(cmd, []string{"a/b", "c/d"}) == nil {
				t.Errorf("cluster %s accepts other than one target", name)
			}
		})
	}
}

// TestIsBootstrapRequired covers terraform, hosts sync, and cluster, which MUST leave .env untouched.
func TestIsBootstrapRequired(t *testing.T) {
	a := &app{}
	findSubcommand := func(parent func() *cobra.Command, name string) func(t *testing.T) *cobra.Command {
		return func(t *testing.T) *cobra.Command {
			t.Helper()
			cmd, _, err := parent().Find([]string{name})
			if err != nil || cmd.Name() != name {
				t.Fatalf("find %s: command %q, error %v", name, cmd.Name(), err)
			}
			return cmd
		}
	}
	cases := []struct {
		name string
		cmd  func(t *testing.T) *cobra.Command
		want bool
	}{
		{"terraform", func(*testing.T) *cobra.Command { return a.terraformCmd() }, false},
		{"layer clean", findSubcommand(a.layerCmd, "clean"), true},
		{"hosts sync", findSubcommand(a.hostsCmd, "sync"), false},
		{"cluster shell", findSubcommand(a.clusterCmd, "shell"), false},
		{"cluster status", findSubcommand(a.clusterCmd, "status"), false},
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
