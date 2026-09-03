// Package main provides the platform CLI for infrastructure management across Vault, Packer, Terraform,
// SSH, Gitaly, and libvirt. Invocation without arguments launches the interactive management menu.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	"platform/internal/config"
	"platform/internal/ui"
)

// app maintains filesystem paths and bootstrapped environment configuration for CLI operations.
// Resolves root and home directories at initialization to pass explicit parameters to internal packages.
type app struct {
	root             string
	home             string
	packerDir        string
	packerCache      string
	terraform        string
	bastionVaultAddr string
	ansibleDir       string
	env              *config.Env
	out              *ui.Printer
	in               *bufio.Reader
}

func main() {
	os.Exit(execute())
}

// resolveProjectRoot anchors root resolution to .git, independent of the invoking subdirectory.
func resolveProjectRoot(start string) (string, error) {
	dir := start
	for {
		_, err := os.Stat(filepath.Join(dir, ".git"))
		if err == nil {
			return dir, nil
		}
		if !errors.Is(err, fs.ErrNotExist) {
			return "", fmt.Errorf("stat %s: %w", filepath.Join(dir, ".git"), err)
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("no .git entry found from %s upward", start)
		}
		dir = parent
	}
}

func execute() int {
	out := ui.New(os.Stdout, os.Stderr)

	cwd, err := os.Getwd()
	if err != nil {
		out.Print(ui.Fatal, err.Error())
		return 1
	}
	root, err := resolveProjectRoot(cwd)
	if err != nil {
		out.Print(ui.Fatal, err.Error())
		return 1
	}
	home, err := os.UserHomeDir()
	if err != nil {
		out.Print(ui.Fatal, err.Error())
		return 1
	}

	a := &app{
		root:        root,
		home:        home,
		packerDir:   filepath.Join(root, "packer"),
		packerCache: filepath.Join(home, ".cache", "packer"),
		terraform:   filepath.Join(root, "terraform"),
		ansibleDir:  filepath.Join(root, "ansible"),
		out:         out,
		in:          bufio.NewReader(os.Stdin),
	}

	var rootCmd *cobra.Command
	rootCmd = &cobra.Command{
		Use:           "platform",
		Short:         "IaC-driven Internal Developer Platform for meta-platform",
		SilenceUsage:  true,
		SilenceErrors: true,
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			if cmd == rootCmd {
				// runMenu bootstraps itself after printing the title banner.
				return nil
			}
			env, err := config.BootstrapEnv(a.root, a.packerDir, a.terraform, a.ansibleDir, a.out)
			if err != nil {
				return err
			}
			a.env = env
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return a.runMenu(cmd.Context())
		},
	}

	rootCmd.AddCommand(
		a.vaultCmd(),
		a.sshCmd(),
		a.envCmd(),
		a.packerCmd(),
		a.terraformCmd(),
		a.gitalyCmd(),
		a.libvirtCmd(),
		a.strategyCmd(),
	)

	if err := rootCmd.Execute(); err != nil {
		out.Print(ui.Error, err.Error())
		return 1
	}
	return 0
}
