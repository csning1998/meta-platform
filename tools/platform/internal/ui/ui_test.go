package ui

import (
	"bufio"
	"bytes"
	"strings"
	"testing"
)

func TestPrintRoutesErrorAndFatalToErrOut(t *testing.T) {
	cases := []struct {
		name      string
		level     Level
		wantOnErr bool
	}{
		{"Info", Info, false},
		{"Step", Step, false},
		{"OK", OK, false},
		{"Error", Error, true},
		{"Fatal", Fatal, true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assertPrintDestination(t, tc.level, tc.wantOnErr)
		})
	}
}

func assertPrintDestination(t *testing.T, level Level, wantOnErr bool) {
	t.Helper()
	var out, errOut bytes.Buffer
	New(&out, &errOut).Print(level, "hello")

	writer, other, label := &out, &errOut, "out"
	if wantOnErr {
		writer, other, label = &errOut, &out, "errOut"
	}
	if !strings.Contains(writer.String(), "hello") {
		t.Errorf("Print(%v) wrote nothing to %s", level, label)
	}
	if other.Len() != 0 {
		t.Errorf("Print(%v) also wrote to the other writer: %q", level, other.String())
	}
}

func TestPrintIncludesLevelTag(t *testing.T) {
	var out, errOut bytes.Buffer
	New(&out, &errOut).Print(Warn, "careful")
	if !strings.Contains(out.String(), "[WARN]") {
		t.Errorf("Print(Warn) = %q, want it to contain [WARN]", out.String())
	}
}

func TestDividerDefaultsToDashes(t *testing.T) {
	var out, errOut bytes.Buffer
	New(&out, &errOut).PrintDivider("")
	if !strings.Contains(out.String(), strings.Repeat("-", 60)) {
		t.Errorf("PrintDivider(\"\") = %q, want 60 dashes", out.String())
	}
}

func TestPromptReturnsDefaultOnBlankLine(t *testing.T) {
	var out, errOut bytes.Buffer
	got := New(&out, &errOut).PromptInput(bufio.NewReader(strings.NewReader("\n")), "name?", "fallback")
	if got != "fallback" {
		t.Errorf("Prompt with blank input = %q, want fallback", got)
	}
}

func TestPromptReturnsTrimmedInput(t *testing.T) {
	var out, errOut bytes.Buffer
	got := New(&out, &errOut).PromptInput(bufio.NewReader(strings.NewReader("  custom-key  \n")), "name?", "fallback")
	if got != "custom-key" {
		t.Errorf("Prompt = %q, want custom-key", got)
	}
}

func TestSelectValidChoice(t *testing.T) {
	var out, errOut bytes.Buffer
	index, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader("2\n")), "choose", []string{"a", "b", "c"})
	if !ok || index != 1 {
		t.Errorf("PromptSelect(\"2\") = (%d, %v), want (1, true)", index, ok)
	}
}

func TestSelectRejectsInvalidChoices(t *testing.T) {
	cases := []string{"0\n", "4\n", "\n", "abc\n", "-1\n"}
	for _, input := range cases {
		var out, errOut bytes.Buffer
		_, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader(input)), "choose", []string{"a", "b", "c"})
		if ok {
			t.Errorf("PromptSelect(%q) = ok true, want false", input)
		}
	}
}

func TestConfirmAcceptsYAndyOnly(t *testing.T) {
	cases := map[string]bool{
		"Y\n":   true,
		"y\n":   true,
		"yes\n": false,
		"n\n":   false,
		"\n":    false,
	}
	for input, want := range cases {
		var out, errOut bytes.Buffer
		got := New(&out, &errOut).PromptConfirm(bufio.NewReader(strings.NewReader(input)), "confirm?")
		if got != want {
			t.Errorf("PromptConfirm(%q) = %v, want %v", input, got, want)
		}
	}
}

func TestLabelUnknownLevelFallsToInfoDefault(t *testing.T) {
	var out, errOut bytes.Buffer
	New(&out, &errOut).Print(Level(99), "msg")
	if !strings.Contains(out.String(), "[INFO]") {
		t.Errorf("Print(Level(99)) = %q, want it to contain [INFO]", out.String())
	}
	if errOut.Len() != 0 {
		t.Errorf("Print(Level(99)) wrote to errOut: %q, want nothing", errOut.String())
	}
}

func TestPrintExactFormatPerLevel(t *testing.T) {
	const (
		colorReset  = "\033[0m"
		colorRed    = "\033[0;31m"
		colorGreen  = "\033[0;32m"
		colorYellow = "\033[0;33m"
	)
	cases := []struct {
		name  string
		level Level
		want  string
	}{
		{"Info", Info, colorGreen + "[INFO] hi" + colorReset + "\n"},
		{"Warn", Warn, colorYellow + "[WARN] careful" + colorReset + "\n"},
		{"Error", Error, colorRed + "[ERROR] boom" + colorReset + "\n"},
		{"OK", OK, colorGreen + "[OK] done" + colorReset + "\n"},
	}
	msgs := map[Level]string{Info: "hi", Warn: "careful", Error: "boom", OK: "done"}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out, errOut bytes.Buffer
			New(&out, &errOut).Print(tc.level, msgs[tc.level])

			got := out.String()
			if tc.level == Error {
				got = errOut.String()
			}
			if got != tc.want {
				t.Errorf("Print(%v) = %q, want %q", tc.level, got, tc.want)
			}
		})
	}
}

func TestDividerCustomCharExactLength(t *testing.T) {
	var out, errOut bytes.Buffer
	New(&out, &errOut).PrintDivider("=")
	want := strings.Repeat("=", 60) + "\n"
	if out.String() != want {
		t.Errorf("PrintDivider(\"=\") = %q, want %q", out.String(), want)
	}
	if len(out.String()) != 61 {
		t.Errorf("PrintDivider(\"=\") length = %d, want 61", len(out.String()))
	}
}

func TestDividerDefaultExactLength(t *testing.T) {
	var out, errOut bytes.Buffer
	New(&out, &errOut).PrintDivider("")
	want := strings.Repeat("-", 60) + "\n"
	if out.String() != want {
		t.Errorf("PrintDivider(\"\") = %q, want %q", out.String(), want)
	}
	if len(out.String()) != 61 {
		t.Errorf("PrintDivider(\"\") length = %d, want 61", len(out.String()))
	}
}

func TestDividerMultiCharRepeatsWholeString(t *testing.T) {
	var out, errOut bytes.Buffer
	New(&out, &errOut).PrintDivider("-=")
	want := strings.Repeat("-=", 60) + "\n"
	if out.String() != want {
		t.Errorf("PrintDivider(\"-=\") = %q, want %q", out.String(), want)
	}
	if len(out.String()) != 121 {
		t.Errorf("PrintDivider(\"-=\") length = %d, want 121", len(out.String()))
	}
}

func TestConfirmEdgeCases(t *testing.T) {
	cases := map[string]bool{
		"Y":     true,  // ReadString returns the read bytes before io.EOF even with no trailing newline, and the error is ignored.
		" Y \n": true,  // surrounding whitespace trimmed before comparison
		"YES\n": false, // must not match via prefix, only exact "Y" or "y"
		"":      false, // an empty reader returns "" immediately from ReadString with io.EOF.
	}
	for input, want := range cases {
		var out, errOut bytes.Buffer
		got := New(&out, &errOut).PromptConfirm(bufio.NewReader(strings.NewReader(input)), "confirm?")
		if got != want {
			t.Errorf("PromptConfirm(%q) = %v, want %v", input, got, want)
		}
	}
}

func TestPromptWhitespaceOnlyLineReturnsDefault(t *testing.T) {
	var out, errOut bytes.Buffer
	got := New(&out, &errOut).PromptInput(bufio.NewReader(strings.NewReader("   \n")), "name?", "fallback")
	if got != "fallback" {
		t.Errorf("Prompt with whitespace-only input = %q, want fallback", got)
	}
}

func TestPromptNoTrailingNewlineReturnsTrimmedInput(t *testing.T) {
	var out, errOut bytes.Buffer
	got := New(&out, &errOut).PromptInput(bufio.NewReader(strings.NewReader("custom-key")), "name?", "fallback")
	if got != "custom-key" {
		t.Errorf("Prompt with no trailing newline = %q, want custom-key", got)
	}
}

func TestSelectLeadingZerosOutOfRange(t *testing.T) {
	var out, errOut bytes.Buffer
	_, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader("007\n")), "choose", []string{"a", "b", "c"})
	if ok {
		t.Errorf("PromptSelect(\"007\") = ok true, want false (7 is out of range)")
	}
}

func TestSelectOverflowingNumberDoesNotPanicAndIsInvalid(t *testing.T) {
	var out, errOut bytes.Buffer
	_, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader("99999999999999999999\n")), "choose", []string{"a", "b", "c"})
	if ok {
		t.Errorf("PromptSelect(20 nines) = ok true, want false")
	}
}

// Validates integer overflow handling for numerical inputs exceeding 64-bit unsigned bounds (2^64 + 2).
// Parsing MUST NOT allow modulo 2^64 wrap-around to resolve into valid option index ranges.
func TestSelectOverflowDoesNotWrapIntoValidRange(t *testing.T) {
	var out, errOut bytes.Buffer
	_, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader("18446744073709551618\n")), "choose", []string{"a", "b", "c"})
	if ok {
		t.Errorf("PromptSelect(2^64+2) = ok true, want false (must not wrap into a valid index)")
	}
}

func TestSelectAtIntBoundaries(t *testing.T) {
	cases := []struct {
		name  string
		input string
	}{
		{"math.MaxInt64", "9223372036854775807\n"},
		{"math.MaxInt64 plus one, overflows", "9223372036854775808\n"},
		{"one digit short of overflow, still out of range", "999999999999999999\n"},
		{"all zeros", "000\n"},
		{"single zero", "0\n"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var out, errOut bytes.Buffer
			_, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader(c.input)), "choose", []string{"a", "b", "c"})
			if ok {
				t.Errorf("PromptSelect(%q) = ok true, want false", c.input)
			}
		})
	}
}

func TestSelectExactUpperBoundaryAccepted(t *testing.T) {
	var out, errOut bytes.Buffer
	options := []string{"a", "b", "c"}
	index, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader("3\n")), "choose", options)
	if !ok || index != len(options)-1 {
		t.Errorf("PromptSelect(%q) = (%d, %v), want (%d, true)", "3", index, ok, len(options)-1)
	}
}

func TestSelectOneBeyondUpperBoundaryRejected(t *testing.T) {
	var out, errOut bytes.Buffer
	options := []string{"a", "b", "c"}
	_, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader("4\n")), "choose", options)
	if ok {
		t.Error("PromptSelect(\"4\") on a 3-option list = ok true, want false")
	}
}

func TestSelectSignedNumbersAreInvalid(t *testing.T) {
	for _, input := range []string{"+1\n", "-1\n"} {
		var out, errOut bytes.Buffer
		_, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader(input)), "choose", []string{"a", "b", "c"})
		if ok {
			t.Errorf("PromptSelect(%q) = ok true, want false", input)
		}
	}
}

func TestSelectTrailingGarbageIsInvalid(t *testing.T) {
	var out, errOut bytes.Buffer
	_, ok := New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader("2x\n")), "choose", []string{"a", "b", "c"})
	if ok {
		t.Errorf("PromptSelect(\"2x\") = ok true, want false")
	}
}

func TestSelectSingleOptionBoundaries(t *testing.T) {
	var out1, errOut1 bytes.Buffer
	index, ok := New(&out1, &errOut1).PromptSelect(bufio.NewReader(strings.NewReader("1\n")), "choose", []string{"only"})
	if !ok || index != 0 {
		t.Errorf("PromptSelect(\"1\") on single-option list = (%d, %v), want (0, true)", index, ok)
	}

	var out2, errOut2 bytes.Buffer
	_, ok = New(&out2, &errOut2).PromptSelect(bufio.NewReader(strings.NewReader("2\n")), "choose", []string{"only"})
	if ok {
		t.Errorf("PromptSelect(\"2\") on single-option list = ok true, want false")
	}
}

func TestSelectPrintsOptionListExactly(t *testing.T) {
	var out, errOut bytes.Buffer
	New(&out, &errOut).PromptSelect(bufio.NewReader(strings.NewReader("1\n")), "choose", []string{"a", "b"})

	got := out.String()
	want := "1) a\n2) b\n"
	if !strings.HasPrefix(got, want) {
		t.Errorf("Select option listing = %q, want it to start with %q", got, want)
	}
}

func TestNewRoundTripsWritersWithoutSwapping(t *testing.T) {
	var out, errOut bytes.Buffer
	New(&out, &errOut).Print(Info, "hello")
	if !strings.Contains(out.String(), "hello") {
		t.Errorf("New(out, errOut).Print(Info, ...) wrote nothing to out: %q", out.String())
	}
	if errOut.Len() != 0 {
		t.Errorf("New(out, errOut).Print(Info, ...) wrote to errOut: %q, want nothing", errOut.String())
	}
}
