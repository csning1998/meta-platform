// Package ui provides formatted log output, visual section dividers, and interactive user prompts.
package ui

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"
)

const (
	colorReset   = "\033[0m"
	colorRed     = "\033[0;31m"
	colorGreen   = "\033[0;32m"
	colorYellow  = "\033[0;33m"
	colorCyan    = "\033[0;36m"
	colorPurple  = "\033[0;35m"
	colorBoldRed = "\033[1;31m"
	colorBlue    = "\033[1;34m"
)

// Level defines log output severity categories.
type Level int

const (
	Info Level = iota
	Step
	Task
	Warn
	Error
	Fatal
	OK
	Input
)

// severityLabel covers Info/Warn/Error/Fatal/OK: the outcome axis. Returns ("", "") for a
// Level outside this axis.
func (l Level) severityLabel() (tag, color string) {
	switch l {
	case Info:
		return "INFO", colorGreen
	case Warn:
		return "WARN", colorYellow
	case Error:
		return "ERROR", colorRed
	case Fatal:
		return "FATAL", colorBoldRed
	case OK:
		return "OK", colorGreen
	default:
		return "", ""
	}
}

// narrativeLabel covers Step/Task: the progress-narration axis. Returns ("", "") for a Level
// outside this axis.
func (l Level) narrativeLabel() (tag, color string) {
	switch l {
	case Step:
		return "STEP", colorBlue
	case Task:
		return "TASK", colorCyan
	default:
		return "", ""
	}
}

// interactiveLabel covers Input: the user-prompt axis. Returns ("", "") for a Level outside
// this axis.
func (l Level) interactiveLabel() (tag, color string) {
	if l == Input {
		return "INPUT", colorPurple
	}
	return "", ""
}

// resolveLabel dispatches l to whichever single axis l belongs to. An unrecognized Level
// falls back to the neutral Info label.
func (l Level) resolveLabel() (tag, color string) {
	if tag, color = l.severityLabel(); tag != "" {
		return tag, color
	}
	if tag, color = l.narrativeLabel(); tag != "" {
		return tag, color
	}
	if tag, color = l.interactiveLabel(); tag != "" {
		return tag, color
	}
	return "INFO", colorGreen
}

// Printer writes formatted, color-coded log lines to standard output and standard error streams based on log level.
type Printer struct {
	out    io.Writer
	errOut io.Writer
}

func New(out, errOut io.Writer) *Printer {
	return &Printer{out: out, errOut: errOut}
}

// Print writes a color-coded log line formatted as "[LEVEL] msg".
// Non-error levels write to standard output. Error and Fatal levels write to standard error.
func (p *Printer) Print(level Level, msg string) {
	tag, color := level.resolveLabel()
	dest := p.out
	if level == Error || level == Fatal {
		dest = p.errOut
	}
	_, _ = fmt.Fprintf(dest, "%s[%s] %s%s\n", color, tag, msg, colorReset)
}

// PrintDivider outputs a 60-character horizontal line using char. Defaults to "-" if char is empty.
func (p *Printer) PrintDivider(char string) {
	if char == "" {
		char = "-"
	}
	_, _ = fmt.Fprintln(p.out, strings.Repeat(char, 60))
}

// PromptConfirm displays msg and returns true if input matches "Y" or "y".
func (p *Printer) PromptConfirm(in *bufio.Reader, msg string) bool {
	p.Print(Input, msg)
	line, _ := in.ReadString('\n')
	line = strings.TrimSpace(line)
	return line == "Y" || line == "y"
}

// PromptInput displays msg and returns whitespace-trimmed input line. Returns def if input is empty.
func (p *Printer) PromptInput(in *bufio.Reader, msg, def string) string {
	p.Print(Input, msg)
	line, _ := in.ReadString('\n')
	line = strings.TrimSpace(line)
	if line == "" {
		return def
	}
	return line
}

// PromptSelect displays a numbered list of options and returns the zero-based index of the selected option.
// Returns ok=false if input is empty, non-numeric, or out of range.
func (p *Printer) PromptSelect(in *bufio.Reader, prompt string, options []string) (index int, ok bool) {
	for i, opt := range options {
		_, _ = fmt.Fprintf(p.out, "%d) %s\n", i+1, opt)
	}
	p.Print(Input, prompt)
	line, _ := in.ReadString('\n')
	line = strings.TrimSpace(line)

	for _, r := range line {
		if r < '0' || r > '9' {
			return 0, false
		}
	}
	n, err := strconv.Atoi(line)
	if line == "" || err != nil || n < 1 || n > len(options) {
		return 0, false
	}
	return n - 1, true
}
