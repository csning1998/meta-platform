package libvirtops

import (
	"strings"
	"testing"
)

func TestHasProjectPrefix(t *testing.T) {
	prefix := ProjectCode + "-"
	cases := map[string]bool{
		"platform-harbor-origin-frontend-node-00": true,
		"platform-spire-parent-frontend-pool":     true,
		"other-project-vm":                        false,
		"platform":                                false,
		"":                                        false,
		prefix:                                    true,
		"platform_x":                              false,
		"Platform-vm":                             false,
		"xplatform-vm":                            false,
		"PLATFORM-VM":                             false,
		"other-platform-vm":                       false,
		prefix + strings.Repeat("x", 4096):        true,
	}
	for name, want := range cases {
		if got := hasProjectPrefix(name); got != want {
			t.Errorf("hasProjectPrefix(%q) = %v, want %v", name, got, want)
		}
	}
}

func TestProjectCodeValue(t *testing.T) {
	if ProjectCode != "platform" {
		t.Errorf("ProjectCode = %q, want %q", ProjectCode, "platform")
	}
}

func TestParseDiskPaths(t *testing.T) {
	cases := []struct {
		name string
		xml  string
		want []string
	}{
		{
			name: "single disk",
			xml: `<domain><devices>
				<disk type='file' device='disk'><source file='/var/lib/libvirt/images/platform-node.qcow2'/></disk>
			</devices></domain>`,
			want: []string{"/var/lib/libvirt/images/platform-node.qcow2"},
		},
		{
			name: "multiple disks preserve order",
			xml: `<domain><devices>
				<disk type='file' device='disk'><source file='/a.qcow2'/></disk>
				<disk type='file' device='cdrom'/>
				<disk type='file' device='disk'><source file='/b.qcow2'/></disk>
			</devices></domain>`,
			want: []string{"/a.qcow2", "/b.qcow2"},
		},
		{
			name: "no devices element",
			xml:  `<domain></domain>`,
			want: []string{},
		},
		{
			name: "malformed xml yields nil",
			xml:  `<domain><devices>`,
			want: nil,
		},
		{
			name: "disk with empty source file attribute excluded",
			xml: `<domain><devices>
				<disk type='file' device='disk'><source file=''/></disk>
			</devices></domain>`,
			want: []string{},
		},
		{
			name: "cdrom device with no source element at all",
			xml: `<domain><devices>
				<disk type='file' device='cdrom'></disk>
			</devices></domain>`,
			want: []string{},
		},
		{
			name: "realistic domain XML with interleaved non-disk devices",
			xml: `<domain type='kvm'>
				<devices>
					<emulator>/usr/bin/qemu-system-x86_64</emulator>
					<disk type='file' device='disk'>
						<driver name='qemu' type='qcow2'/>
						<source file='/var/lib/libvirt/images/platform-node.qcow2'/>
						<target dev='vda' bus='virtio'/>
					</disk>
					<interface type='network'>
						<source network='default'/>
					</interface>
					<disk type='block' device='disk'>
						<source dev='/dev/mapper/vg-lv'/>
					</disk>
				</devices>
			</domain>`,
			want: []string{"/var/lib/libvirt/images/platform-node.qcow2"},
		},
		{
			name: "empty string input",
			xml:  "",
			want: nil,
		},
		{
			name: "no disk elements at all",
			xml:  `<domain><devices><interface type='network'/></devices></domain>`,
			want: []string{},
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			assertParseDiskPaths(t, c.xml, c.want)
		})
	}
}

func assertParseDiskPaths(t *testing.T, xmlDesc string, want []string) {
	t.Helper()
	got := parseDiskPaths(xmlDesc)
	if len(got) != len(want) {
		t.Fatalf("parseDiskPaths(...) = %#v, want %#v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("parseDiskPaths(...) = %#v, want %#v", got, want)
		}
	}
}
