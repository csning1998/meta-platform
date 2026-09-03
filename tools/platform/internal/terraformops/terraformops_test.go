package terraformops

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"platform/internal/ui"
)

func TestReportCleanupStatusRejectsEmptyTarget(t *testing.T) {
	if err := ReportCleanupStatus(t.TempDir(), "", nil, ui.New(io.Discard, io.Discard)); err == nil {
		t.Error("ReportCleanupStatus(\"\") = nil error, want error")
	}
}

func TestReportCleanupStatusSkipsMissingLayerDirWithoutError(t *testing.T) {
	dir := t.TempDir()
	if err := ReportCleanupStatus(dir, "no-such-layer", nil, ui.New(io.Discard, io.Discard)); err != nil {
		t.Errorf("Clean on a missing layer dir = %v, want nil (report-only, non-fatal)", err)
	}
}

func TestReportCleanupStatusAllIteratesEveryLayer(t *testing.T) {
	dir := t.TempDir()
	for _, layer := range []string{"layer-a", "layer-b"} {
		if err := os.MkdirAll(filepath.Join(dir, "layers", layer), 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", layer, err)
		}
	}

	if err := ReportCleanupStatus(dir, "all", []string{"layer-a", "layer-b"}, ui.New(io.Discard, io.Discard)); err != nil {
		t.Errorf("ReportCleanupStatus(\"all\") = %v, want nil", err)
	}
}

func TestReportCleanupStatusAllWithNilLayersIsNoopSuccess(t *testing.T) {
	dir := t.TempDir()
	if err := ReportCleanupStatus(dir, "all", nil, ui.New(io.Discard, io.Discard)); err != nil {
		t.Errorf("ReportCleanupStatus(\"all\", nil) = %v, want nil", err)
	}
}

func TestReportCleanupStatusAllWithOneMissingLayerStillSucceeds(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "layers", "layer-a"), 0o755); err != nil {
		t.Fatalf("mkdir layer-a: %v", err)
	}
	// layer-b is intentionally not created.

	var buf bytes.Buffer
	if err := ReportCleanupStatus(dir, "all", []string{"layer-a", "layer-b"}, ui.New(&buf, &buf)); err != nil {
		t.Errorf("ReportCleanupStatus(\"all\") with one missing layer = %v, want nil", err)
	}
	if !strings.Contains(buf.String(), "layer-b") {
		t.Errorf("output missing WARN for layer-b, got: %s", buf.String())
	}
}

func TestReportCleanupStatusSingleExistingLayerReportsSuccess(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "layers", "layer-a"), 0o755); err != nil {
		t.Fatalf("mkdir layer-a: %v", err)
	}

	var buf bytes.Buffer
	if err := ReportCleanupStatus(dir, "layer-a", nil, ui.New(&buf, &buf)); err != nil {
		t.Errorf("ReportCleanupStatus(\"layer-a\") = %v, want nil", err)
	}
	if !strings.Contains(buf.String(), "Terraform artifact cleanup completed.") {
		t.Errorf("output missing success line, got: %s", buf.String())
	}
}

func TestReportCleanupStatusTargetAllIsCaseSensitive(t *testing.T) {
	for _, target := range []string{"All", "ALL"} {
		dir := t.TempDir()
		var buf bytes.Buffer
		if err := ReportCleanupStatus(dir, target, []string{"layer-a"}, ui.New(&buf, &buf)); err != nil {
			t.Errorf("ReportCleanupStatus(%q) = %v, want nil", target, err)
		}
		if strings.Contains(buf.String(), "Preparing to clean all Terraform layers...") {
			t.Errorf("ReportCleanupStatus(%q) treated target as wildcard \"all\", want literal layer name", target)
		}
		if !strings.Contains(buf.String(), "Terraform layer directory not found, skipping") {
			t.Errorf("ReportCleanupStatus(%q) = %q, want missing-dir WARN for literal layer name", target, buf.String())
		}
	}
}

func TestReportCleanupStatusTargetWithPathTraversalDoesNotPanic(t *testing.T) {
	dir := t.TempDir()
	for _, target := range []string{"../etc", "sub/dir", "../../../etc/passwd"} {
		if err := ReportCleanupStatus(dir, target, nil, ui.New(io.Discard, io.Discard)); err != nil {
			t.Errorf("ReportCleanupStatus(%q) = %v, want nil", target, err)
		}
	}
}

func TestReportCleanupStatusSingleLayerOutputOrder(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "layers", "layer-a"), 0o755); err != nil {
		t.Fatalf("mkdir layer-a: %v", err)
	}

	var buf bytes.Buffer
	if err := ReportCleanupStatus(dir, "layer-a", nil, ui.New(&buf, &buf)); err != nil {
		t.Errorf("ReportCleanupStatus(\"layer-a\") = %v, want nil", err)
	}

	stepIdx := strings.Index(buf.String(), "Cleaning Terraform artifacts...")
	okIdx := strings.Index(buf.String(), "Terraform artifact cleanup completed.")
	dividerIdx := strings.Index(buf.String(), strings.Repeat("-", 60))
	if stepIdx == -1 || okIdx == -1 || dividerIdx == -1 {
		t.Fatalf("missing expected output segment, got: %s", buf.String())
	}
	if stepIdx >= okIdx || okIdx >= dividerIdx {
		t.Errorf("output out of order: step=%d ok=%d divider=%d, got: %s", stepIdx, okIdx, dividerIdx, buf.String())
	}
}
