package main

import (
	"testing"
)

func TestTerraformRunPassesEveryArgumentToTerraform(t *testing.T) {
	a := &app{}
	cmd, _, err := a.terraformCmd().Find([]string{"run"})
	if err != nil || cmd.Name() != "run" {
		t.Fatalf("find run: command %q, error %v, want command %q", cmd.Name(), err, "run")
	}
	if !cmd.DisableFlagParsing {
		t.Error("terraform run parses flags, want every argument passed to terraform")
	}
}

// TestIsBootstrapRequired covers commands which run inside a layer directory and MUST leave .env untouched.
func TestIsBootstrapRequired(t *testing.T) {
	a := &app{}
	cases := []struct {
		name string
		path []string
		want bool
	}{
		{"terraform run", []string{"run"}, false},
		{"terraform clean", []string{"clean"}, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			cmd, _, err := a.terraformCmd().Find(c.path)
			if err != nil {
				t.Fatalf("find %v: %v", c.path, err)
			}
			got := isBootstrapRequired(cmd)
			if got != c.want {
				t.Errorf("isBootstrapRequired(%s) = %v, want %v", c.name, got, c.want)
			}
		})
	}
}
