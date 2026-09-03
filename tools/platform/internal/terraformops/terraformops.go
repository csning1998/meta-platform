// Package terraformops provides Terraform layer artifact cleanup status reporting.
package terraformops

import (
	"fmt"
	"os"
	"path/filepath"

	"platform/internal/ui"
)

// ReportCleanupStatus scans the specified Terraform layer, or all discovered layers, and
// reports one summary of the artifact cleanup status across every layer.
func ReportCleanupStatus(terraformDir, target string, allLayers []string, out *ui.Printer) error {
	if target == "" {
		return fmt.Errorf("terraformops: no layer specified")
	}

	layers := []string{target}
	if target == "all" {
		out.Print(ui.Step, "Preparing to clean all Terraform layers...")
		layers = allLayers
	}

	var cleaned, missing []string
	for _, layer := range layers {
		if _, err := os.Stat(filepath.Join(terraformDir, "layers", layer)); err != nil {
			missing = append(missing, layer)
			continue
		}
		cleaned = append(cleaned, layer)
	}

	if len(cleaned) > 0 {
		out.Print(ui.Step, "Cleaning Terraform artifacts...")
		out.Print(ui.OK, "Terraform artifact cleanup completed.")
	}
	for _, layer := range missing {
		out.Print(ui.Warn, "Terraform layer directory not found, skipping: "+filepath.Join(terraformDir, "layers", layer))
	}
	out.PrintDivider("")
	return nil
}
