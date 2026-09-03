package config

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"strconv"
	"strings"
)

// HostFacts encapsulates host operating system identity, virtualization support status, user identity,
// and libvirt group configuration.
type HostFacts struct {
	OSFamily     string // "rhel", "debian", or "unknown"
	OSVersionID  string
	VirtSupport  bool
	LibvirtGID   int
	CurrentUID   int
	CurrentGID   int
	CurrentUname string
}

// DetectHostFacts inspects system configuration files (/etc/os-release, /proc/cpuinfo) and
// user database entries to populate HostFacts.
func DetectHostFacts() (HostFacts, error) {
	facts := HostFacts{OSFamily: "unknown", OSVersionID: "unknown", LibvirtGID: 999}

	if data, err := os.ReadFile("/etc/os-release"); err == nil {
		id, versionID := parseOSRelease(string(data))
		switch {
		case strings.Contains(id, "fedora"), id == "rhel", id == "centos":
			facts.OSFamily = "rhel"
		case strings.Contains(id, "debian"), id == "ubuntu":
			facts.OSFamily = "debian"
		}
		if versionID != "" {
			facts.OSVersionID = strings.SplitN(versionID, ".", 2)[0]
		}
	}

	if cpuinfo, err := os.ReadFile("/proc/cpuinfo"); err == nil {
		for _, line := range strings.Split(string(cpuinfo), "\n") {
			if strings.HasPrefix(line, "flags") && (strings.Contains(line, " vmx") || strings.Contains(line, " svm")) {
				facts.VirtSupport = true
				break
			}
		}
	}

	if grp, err := exec.Command("getent", "group", "libvirt").Output(); err == nil {
		fields := strings.Split(strings.TrimSpace(string(grp)), ":")
		if len(fields) >= 3 {
			if gid, err := strconv.Atoi(fields[2]); err == nil {
				facts.LibvirtGID = gid
			}
		}
	}

	u, err := user.Current()
	if err != nil {
		return facts, fmt.Errorf("config: lookup current user: %w", err)
	}
	facts.CurrentUname = u.Username
	if uid, err := strconv.Atoi(u.Uid); err == nil {
		facts.CurrentUID = uid
	}
	if gid, err := strconv.Atoi(u.Gid); err == nil {
		facts.CurrentGID = gid
	}

	return facts, nil
}

func parseOSRelease(data string) (id, versionID string) {
	for _, line := range strings.Split(data, "\n") {
		key, val, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		val = strings.Trim(val, `"`)
		switch key {
		case "ID":
			id = val
		case "VERSION_ID":
			versionID = val
		}
	}
	return id, versionID
}

// requiredTool defines binary executable requirements verified against system PATH.
type requiredTool struct {
	Cmd  string
	Name string
}

var libvirtTools = []requiredTool{
	{"qemu-system-x86_64", "QEMU/KVM"},
	{"virsh", "Libvirt Client (virsh)"},
}

var iacTools = []requiredTool{
	{"packer", "HashiCorp Packer"},
	{"terraform", "HashiCorp Terraform"},
	{"vault", "HashiCorp Vault"},
	{"ansible", "Red Hat Ansible"},
}

// ToolCheck reports one required tool's install state, for the env verify command's report.
type ToolCheck struct {
	Group     string
	Name      string
	Installed bool
}

// VerifyNativeEnvironment validates executable availability for required virtualization and
// IaC tool binaries against PATH.
func VerifyNativeEnvironment() []ToolCheck {
	var checks []ToolCheck
	for _, t := range libvirtTools {
		checks = append(checks, ToolCheck{"Libvirt/KVM Environment", t.Name, isToolInstalled(t.Cmd)})
	}
	for _, t := range iacTools {
		checks = append(checks, ToolCheck{"Core IaC Tools (HashiCorp/Ansible)", t.Name, isToolInstalled(t.Cmd)})
	}
	return checks
}

func isToolInstalled(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}
