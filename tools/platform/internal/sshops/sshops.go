// Package sshops provides SSH key generation, connectivity verification, and configuration helpers.
package sshops

import (
	"bufio"
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"

	"platform/internal/ui"
)

// KeyExists reports whether a private key file exists at the specified path.
func KeyExists(privateKeyPath string) bool {
	if privateKeyPath == "" {
		return false
	}
	_, err := os.Stat(privateKeyPath)
	return err == nil
}

// GenerateKey creates a new ed25519 keypair at home/.ssh/<keyName>.
func GenerateKey(home, keyName string, overwrite bool, out *ui.Printer) (privateKeyPath string, err error) {
	privateKeyPath = filepath.Join(home, ".ssh", keyName)
	publicKeyPath := privateKeyPath + ".pub"

	if _, statErr := os.Stat(privateKeyPath); statErr == nil && !overwrite {
		return "", fmt.Errorf("sshops: %s already exists; pass overwrite to replace it", privateKeyPath)
	}

	out.Print(ui.Task, "Generating key at '"+privateKeyPath+"'...")

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return "", fmt.Errorf("sshops: generate ed25519 key: %w", err)
	}

	block, err := ssh.MarshalPrivateKey(priv, keyName)
	if err != nil {
		return "", fmt.Errorf("sshops: marshal OpenSSH private key: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(privateKeyPath), 0o700); err != nil {
		return "", fmt.Errorf("sshops: mkdir %s: %w", filepath.Dir(privateKeyPath), err)
	}
	if err := os.WriteFile(privateKeyPath, pem.EncodeToMemory(block), 0o600); err != nil {
		return "", fmt.Errorf("sshops: write %s: %w", privateKeyPath, err)
	}

	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		return "", fmt.Errorf("sshops: derive public key: %w", err)
	}
	authorizedKeyLine := strings.TrimSuffix(string(ssh.MarshalAuthorizedKey(sshPub)), "\n") + " " + keyName + "\n"
	if err := os.WriteFile(publicKeyPath, []byte(authorizedKeyLine), 0o644); err != nil {
		return "", fmt.Errorf("sshops: write %s: %w", publicKeyPath, err)
	}

	out.Print(ui.OK, "Key generated successfully.")
	return privateKeyPath, nil
}

var hostLineRe = regexp.MustCompile(`^Host\s+(\S+)`)
var knownHostsLineRe = regexp.MustCompile(`UserKnownHostsFile\s+(\S+)`)

// VerifyConnectivity performs strict public-key SSH connection tests against hosts in home/.ssh/ssh_*.
func VerifyConnectivity(home string, out *ui.Printer) error {
	sshDir := filepath.Join(home, ".ssh")
	entries, err := os.ReadDir(sshDir)
	if err != nil {
		return fmt.Errorf("sshops: read %s: %w", sshDir, err)
	}

	var configFiles []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "ssh_") {
			configFiles = append(configFiles, filepath.Join(sshDir, e.Name()))
		}
	}
	if len(configFiles) == 0 {
		return fmt.Errorf("sshops: no IaC SSH config files found matching %s/ssh_*", sshDir)
	}

	allPassed := true
	for _, configFile := range configFiles {
		out.PrintDivider("")
		out.Print(ui.Info, "Verifying configuration: "+filepath.Base(configFile))

		data, err := os.ReadFile(configFile)
		if err != nil {
			return fmt.Errorf("sshops: read %s: %w", configFile, err)
		}

		knownHostsFile := ""
		var hosts []string
		scanner := bufio.NewScanner(bytes.NewReader(data))
		for scanner.Scan() {
			line := scanner.Text()
			if m := knownHostsLineRe.FindStringSubmatch(line); m != nil && knownHostsFile == "" {
				knownHostsFile = expandTildePath(home, m[1])
			}
			if m := hostLineRe.FindStringSubmatch(line); m != nil {
				hosts = append(hosts, m[1])
			}
		}

		if _, err := os.Stat(knownHostsFile); err != nil {
			out.Print(ui.Error, "Known hosts file not found at "+knownHostsFile)
			out.Print(ui.Info, "Please ensure the corresponding Terraform layer has been applied successfully.")
			allPassed = false
			continue
		}
		if len(hosts) == 0 {
			out.Print(ui.Warn, "No hosts found in "+configFile)
			continue
		}

		for _, host := range hosts {
			out.Print(ui.Task, "Verifying connection to host: "+host+"...")
			cmd := exec.Command("ssh", "-n",
				"-F", configFile,
				"-o", "ConnectTimeout=5",
				"-o", "BatchMode=yes",
				"-o", "PasswordAuthentication=no",
				"-o", "StrictHostKeyChecking=yes",
				"-o", "UserKnownHostsFile="+knownHostsFile,
				host, "true")
			if err := cmd.Run(); err != nil {
				out.Print(ui.Error, "Could not connect to "+host+" using strict key-based authentication.")
				allPassed = false
				continue
			}
			out.Print(ui.OK, "Connected to "+host+" via public key.")
		}
	}

	out.PrintDivider("")
	if !allPassed {
		return fmt.Errorf("sshops: one or more SSH verification checks failed")
	}
	out.Print(ui.OK, "All SSH verifications completed successfully.")
	return nil
}

func expandTildePath(home, path string) string {
	if strings.HasPrefix(path, "~/") {
		return filepath.Join(home, path[2:])
	}
	return path
}

// AddSSHIncludeDirective prepends the Include directive to home/.ssh/config if not already present.
func AddSSHIncludeDirective(home, includePath string) error {
	if includePath == "" {
		return fmt.Errorf("sshops: no config path provided")
	}

	configFile := filepath.Join(home, ".ssh", "config")
	includeLine := "Include " + includePath

	if err := os.MkdirAll(filepath.Dir(configFile), 0o700); err != nil {
		return fmt.Errorf("sshops: mkdir %s: %w", filepath.Dir(configFile), err)
	}

	existing, err := os.ReadFile(configFile)
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("sshops: read %s: %w", configFile, err)
	}

	for _, line := range strings.Split(string(existing), "\n") {
		if line == includeLine {
			return nil
		}
	}

	newContent := includeLine + "\n" + string(existing)
	if err := os.WriteFile(configFile, []byte(newContent), 0o600); err != nil {
		return fmt.Errorf("sshops: write %s: %w", configFile, err)
	}
	return nil
}

// RemoveSSHIncludeDirective deletes matching Include directives from home/.ssh/config.
func RemoveSSHIncludeDirective(home, includePath string) error {
	if includePath == "" {
		return fmt.Errorf("sshops: no config path provided")
	}

	configFile := filepath.Join(home, ".ssh", "config")
	includeLine := "Include " + includePath

	data, err := os.ReadFile(configFile)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("sshops: read %s: %w", configFile, err)
	}

	var kept []string
	for _, line := range strings.Split(string(data), "\n") {
		if line != includeLine {
			kept = append(kept, line)
		}
	}
	content := strings.Join(kept, "\n")
	if content != "" && !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	if err := os.WriteFile(configFile, []byte(content), 0o600); err != nil {
		return fmt.Errorf("sshops: write %s: %w", configFile, err)
	}
	return nil
}

// ScanKnownHosts queries SSH host keys for given hosts in parallel and writes them to home/.ssh/known_hosts_<configName>.
func ScanKnownHosts(home, configName string, poll bool, hosts []string, out *ui.Printer) error {
	if len(hosts) == 0 {
		return fmt.Errorf("sshops: no hosts provided")
	}

	knownHostsFile := filepath.Join(home, ".ssh", "known_hosts_"+configName)
	out.Print(ui.Step, "Preparing SSH known_hosts: "+knownHostsFile)
	if err := os.MkdirAll(filepath.Dir(knownHostsFile), 0o700); err != nil {
		return fmt.Errorf("sshops: mkdir %s: %w", filepath.Dir(knownHostsFile), err)
	}
	_ = os.Remove(knownHostsFile)

	out.Print(ui.Task, "Scanning host keys for all nodes...")

	results := make([][]byte, len(hosts))
	errs := make([]error, len(hosts))
	var wg sync.WaitGroup
	for i, host := range hosts {
		wg.Add(1)
		go func(i int, host string) {
			defer wg.Done()
			results[i], errs[i] = scanMultipleHostKeys(host, poll, out)
		}(i, host)
	}
	wg.Wait()

	var combined bytes.Buffer
	failed := 0
	for i, host := range hosts {
		if errs[i] != nil {
			out.Print(ui.Error, "Timed out or failed scanning "+host)
			failed++
			continue
		}
		combined.Write(results[i])
	}
	if err := os.WriteFile(knownHostsFile, combined.Bytes(), 0o644); err != nil {
		return fmt.Errorf("sshops: write %s: %w", knownHostsFile, err)
	}

	if failed > 0 {
		return fmt.Errorf("sshops: %d hosts failed to initialize SSH", failed)
	}
	out.Print(ui.OK, "Host key scanning complete.")
	out.PrintDivider("")
	return nil
}

// errHostKeyCaptured aborts the handshake once HostKeyCallback records the server key.
// Scanning requires only the key, not a full authenticated session.
var errHostKeyCaptured = errors.New("sshops: host key captured")

// fetchSingleHostKey opens a raw ed25519 SSH handshake to host:22 and returns its known_hosts
// line. fetchSingleHostKey replaces `ssh-keyscan -t ed25519`, capturing exactly one key
// algorithm and leaving the hostname unhashed, unlike the "-H" ssh-keyscan format.
func fetchSingleHostKey(host string, timeout time.Duration) (string, error) {
	var captured ssh.PublicKey
	cfg := &ssh.ClientConfig{
		User:              "entry-known-hosts-scan",
		HostKeyAlgorithms: []string{ssh.KeyAlgoED25519},
		Auth:              []ssh.AuthMethod{ssh.Password("")},
		Timeout:           timeout,
		HostKeyCallback: func(hostname string, remote net.Addr, key ssh.PublicKey) error {
			captured = key
			return errHostKeyCaptured
		},
	}

	conn, err := net.DialTimeout("tcp", host+":22", timeout)
	if err != nil {
		return "", fmt.Errorf("sshops: dial %s: %w", host, err)
	}
	defer func() { _ = conn.Close() }()

	_, _, _, err = ssh.NewClientConn(conn, host+":22", cfg)
	if captured == nil {
		return "", fmt.Errorf("sshops: no host key captured from %s: %w", host, err)
	}
	return formatKnownHostsLine([]string{host}, captured), nil
}

func formatKnownHostsLine(addresses []string, key ssh.PublicKey) string {
	return strings.Join(addresses, ",") + " " + key.Type() + " " +
		base64.StdEncoding.EncodeToString(key.Marshal()) + "\n"
}

func scanMultipleHostKeys(host string, poll bool, out *ui.Printer) ([]byte, error) {
	if !poll {
		line, err := fetchSingleHostKey(host, 5*time.Second)
		if err != nil {
			out.Print(ui.Warn, "Failed to scan "+host)
			return nil, err
		}
		out.Print(ui.OK, "Scanned "+host)
		return []byte(line), nil
	}

	out.Print(ui.Task, "Waiting for SSH on "+host+" ...")
	for attempt := 0; attempt < 150; attempt++ {
		if line, err := fetchSingleHostKey(host, 2*time.Second); err == nil {
			out.Print(ui.OK, host+" is ready.")
			return []byte(line), nil
		}
		time.Sleep(1 * time.Second)
	}
	return nil, fmt.Errorf("sshops: timed out waiting for %s", host)
}
