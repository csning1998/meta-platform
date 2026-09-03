// Package packerops provides Packer artifact cleanup and image build execution.
package packerops

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"platform/internal/ui"
)

// Clean removes output directories for specified targets and cleans non-ISO files from the host cache.
func Clean(packerDir, target string, allBases []string, cacheDir string, out *ui.Printer) error {
	out.Print(ui.Step, "Cleaning Packer artifacts...")

	targets := []string{target}
	if target == "all" {
		if len(allBases) == 0 {
			out.Print(ui.Warn, "no discovered Packer bases; cannot clean 'all'.")
			targets = nil
		} else {
			targets = allBases
		}
	}

	for _, base := range targets {
		out.Print(ui.Task, "Cleaning output for layer: "+base)
		if err := os.RemoveAll(filepath.Join(packerDir, "output", base)); err != nil {
			return fmt.Errorf("packerops: remove output for %s: %w", base, err)
		}
	}

	if entries, err := os.ReadDir(cacheDir); err == nil {
		out.Print(ui.Task, "Cleaning Packer cache on host (preserving ISOs)...")
		for _, entry := range entries {
			if strings.HasSuffix(entry.Name(), ".iso") {
				continue
			}
			path := filepath.Join(cacheDir, entry.Name())
			if err := os.RemoveAll(path); err == nil {
				continue
			}
			if err := exec.Command("sudo", "rm", "-rf", path).Run(); err != nil {
				out.Print(ui.Warn, "could not remove cache entry "+path+": "+err.Error())
			}
		}
	}

	out.Print(ui.OK, "Packer artifact cleanup completed.")
	out.PrintDivider("")
	return nil
}

func resolveBaseCategoryDir(packerDir, base string) string {
	if _, err := os.Stat(filepath.Join(packerDir, "distro", base+".pkrvars.hcl")); err == nil {
		return "distro"
	}
	return "services"
}

// BaseExists reports whether base has a var file in either the distro or services category.
func BaseExists(packerDir, base string) bool {
	sub := resolveBaseCategoryDir(packerDir, base)
	_, err := os.Stat(filepath.Join(packerDir, sub, base+".pkrvars.hcl"))
	return err == nil
}

// Build initializes and executes a Packer build for the specified base, generating a SHA-256 checksum upon completion.
func Build(ctx context.Context, packerDir, base string, env []string, out *ui.Printer) error {
	sub := resolveBaseCategoryDir(packerDir, base)
	varFile := filepath.Join(packerDir, sub, base+".pkrvars.hcl")
	if _, err := os.Stat(varFile); err != nil {
		return fmt.Errorf("packerops: var file not found: %s: %w", varFile, err)
	}

	out.Print(ui.Step, fmt.Sprintf("Starting new Packer build for [%s] in [%s]...", base, sub))

	targetDir := filepath.Join(packerDir, sub)

	initCmd := exec.CommandContext(ctx, "packer", "init", ".")
	initCmd.Dir, initCmd.Env = targetDir, env
	initCmd.Stdout, initCmd.Stderr = os.Stdout, os.Stderr
	if err := initCmd.Run(); err != nil {
		return fmt.Errorf("packerops: packer init: %w", err)
	}

	buildCmd := exec.CommandContext(ctx, "packer", "build",
		"-var-file=../values.pkrvars.hcl",
		"-var-file="+base+".pkrvars.hcl",
		"-var", "build_name="+base,
		".",
	)
	buildCmd.Dir, buildCmd.Env = targetDir, env
	buildCmd.Stdout, buildCmd.Stderr = os.Stdout, os.Stderr
	if err := buildCmd.Run(); err != nil {
		return fmt.Errorf("packerops: packer build: %w", err)
	}

	if err := generateQcow2Checksum(filepath.Join(packerDir, "output", base), out); err != nil {
		return err
	}

	out.Print(ui.OK, fmt.Sprintf("Packer build complete. New image for [%s] is ready.", base))
	out.PrintDivider("")
	return nil
}

func generateQcow2Checksum(outputDir string, out *ui.Printer) error {
	entries, err := os.ReadDir(outputDir)
	if err != nil {
		return nil
	}
	var image string
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".qcow2") {
			image = entry.Name()
			break
		}
	}
	if image == "" {
		return nil
	}

	out.Print(ui.Task, "Generating SHA256 checksum for "+image+"...")
	f, err := os.Open(filepath.Join(outputDir, image))
	if err != nil {
		return fmt.Errorf("packerops: open %s: %w", image, err)
	}
	defer func() { _ = f.Close() }()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("packerops: hash %s: %w", image, err)
	}

	line := fmt.Sprintf("%s  %s\n", hex.EncodeToString(h.Sum(nil)), image)
	sumPath := filepath.Join(outputDir, image+".sha256")
	if err := os.WriteFile(sumPath, []byte(line), 0o644); err != nil {
		return fmt.Errorf("packerops: write %s: %w", sumPath, err)
	}
	out.Print(ui.Info, "Checksum generated at "+sumPath)
	return nil
}

// ListDistroBases returns all discovered Packer base configuration names in the distro directory.
func ListDistroBases(packerDir string) ([]string, error) { return listBases(packerDir, "distro") }

// ListServiceBases returns all discovered Packer base configuration names in the services directory.
func ListServiceBases(packerDir string) ([]string, error) { return listBases(packerDir, "services") }

func listBases(packerDir, sub string) ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(packerDir, sub))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("packerops: read %s: %w", filepath.Join(packerDir, sub), err)
	}
	var bases []string
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".pkrvars.hcl") {
			bases = append(bases, strings.TrimSuffix(entry.Name(), ".pkrvars.hcl"))
		}
	}
	sort.Strings(bases)
	return bases, nil
}
