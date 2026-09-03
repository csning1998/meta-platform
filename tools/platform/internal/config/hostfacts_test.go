package config

import "testing"

func TestParseOSRelease(t *testing.T) {
	cases := []struct {
		name              string
		data              string
		wantID, wantVerID string
	}{
		{"fedora", "ID=fedora\nVERSION_ID=44\n", "fedora", "44"},
		{"ubuntu quoted", "ID=\"ubuntu\"\nVERSION_ID=\"24.04\"\n", "ubuntu", "24.04"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id, verID := parseOSRelease(tc.data)
			if id != tc.wantID || verID != tc.wantVerID {
				t.Errorf("parseOSRelease() = (%q, %q), want (%q, %q)", id, verID, tc.wantID, tc.wantVerID)
			}
		})
	}
}

func TestParseOSReleaseEdgeCases(t *testing.T) {
	cases := []struct {
		name              string
		data              string
		wantID, wantVerID string
	}{
		{"empty data", "", "", ""},
		{"line with no equals ignored", "NOEQUALSHERE\nID=fedora\n", "fedora", ""},
		{"unrelated key ignored", "ID=fedora\nPRETTY_NAME=\"Fedora\"\n", "fedora", ""},
		{"version id not truncated on multiple dots", "ID=ubuntu\nVERSION_ID=\"24.04.1\"\n", "ubuntu", "24.04.1"},
		{"version id before id, order independent", "VERSION_ID=44\nID=fedora\n", "fedora", "44"},
		{"mixed quoted and unquoted", "ID=fedora\nVERSION_ID=\"44\"\n", "fedora", "44"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id, verID := parseOSRelease(tc.data)
			if id != tc.wantID || verID != tc.wantVerID {
				t.Errorf("parseOSRelease() = (%q, %q), want (%q, %q)", id, verID, tc.wantID, tc.wantVerID)
			}
		})
	}
}

func TestVerifyNativeEnvironment(t *testing.T) {
	checks := VerifyNativeEnvironment()
	if len(checks) != 6 {
		t.Fatalf("len(checks) = %d, want 6", len(checks))
	}

	wantNames := []string{
		"QEMU/KVM",
		"Libvirt Client (virsh)",
		"HashiCorp Packer",
		"HashiCorp Terraform",
		"HashiCorp Vault",
		"Red Hat Ansible",
	}
	wantGroups := []string{
		"Libvirt/KVM Environment",
		"Libvirt/KVM Environment",
		"Core IaC Tools (HashiCorp/Ansible)",
		"Core IaC Tools (HashiCorp/Ansible)",
		"Core IaC Tools (HashiCorp/Ansible)",
		"Core IaC Tools (HashiCorp/Ansible)",
	}
	for i, check := range checks {
		if check.Name != wantNames[i] {
			t.Errorf("checks[%d].Name = %q, want %q", i, check.Name, wantNames[i])
		}
		if check.Group != wantGroups[i] {
			t.Errorf("checks[%d].Group = %q, want %q", i, check.Group, wantGroups[i])
		}
	}
}
