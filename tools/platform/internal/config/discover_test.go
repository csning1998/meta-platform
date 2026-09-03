package config

import (
	"path/filepath"
	"testing"
)

func TestDiscoverPackerBasesSortsAndExcludesValues(t *testing.T) {
	dir := t.TempDir()
	mustMkdirAll(t, filepath.Join(dir, "distro"))
	mustMkdirAll(t, filepath.Join(dir, "services"))
	mustWriteFile(t, filepath.Join(dir, "distro", "ubuntu-24.pkrvars.hcl"), "")
	mustWriteFile(t, filepath.Join(dir, "distro", "values.pkrvars.hcl"), "")
	mustWriteFile(t, filepath.Join(dir, "services", "base-docker-harbor.pkrvars.hcl"), "")

	got, err := DiscoverPackerBases(dir)
	if err != nil {
		t.Fatalf("DiscoverPackerBases: %v", err)
	}
	want := []string{"base-docker-harbor", "ubuntu-24"}
	if len(got) != len(want) || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("DiscoverPackerBases = %v, want %v", got, want)
	}
}

func TestDiscoverTerraformLayersMissingDirYieldsNil(t *testing.T) {
	got, err := DiscoverTerraformLayers(filepath.Join(t.TempDir(), "no-such-terraform-dir"))
	if err != nil {
		t.Fatalf("DiscoverTerraformLayers: %v", err)
	}
	if got != nil {
		t.Errorf("DiscoverTerraformLayers on missing dir = %v, want nil", got)
	}
}

func TestDiscoverProdVaultInventory(t *testing.T) {
	t.Run("no match", func(t *testing.T) {
		inv, err := DiscoverProdVaultInventory(t.TempDir())
		if err != nil {
			t.Fatalf("DiscoverProdVaultInventory: %v", err)
		}
		if inv.File != "" || inv.Addr != "" {
			t.Errorf("DiscoverProdVaultInventory on empty dir = %+v, want zero value", inv)
		}
	})

	t.Run("one match", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "inventory-platform-vault-frontend.yaml")
		mustWriteFile(t, path, "\"vault_vip\": \"172.16.136.250\"\n")

		inv, err := DiscoverProdVaultInventory(dir)
		if err != nil {
			t.Fatalf("DiscoverProdVaultInventory: %v", err)
		}
		if inv.File != path {
			t.Errorf("File = %q, want %q", inv.File, path)
		}
		if inv.Addr != "https://172.16.136.250:443" {
			t.Errorf("Addr = %q, want https://172.16.136.250:443", inv.Addr)
		}
	})

	t.Run("multiple matches is an error", func(t *testing.T) {
		dir := t.TempDir()
		mustWriteFile(t, filepath.Join(dir, "inventory-a-vault-frontend.yaml"), "")
		mustWriteFile(t, filepath.Join(dir, "inventory-b-vault-frontend.yaml"), "")

		if _, err := DiscoverProdVaultInventory(dir); err == nil {
			t.Error("DiscoverProdVaultInventory with two matches = nil error, want error")
		}
	})
}

func TestDiscoverPackerBasesPartialDirs(t *testing.T) {
	cases := []struct {
		name  string
		setup func(t *testing.T, dir string)
		want  []string
	}{
		{
			name: "only distro exists",
			setup: func(t *testing.T, dir string) {
				mustMkdirAll(t, filepath.Join(dir, "distro"))
				mustWriteFile(t, filepath.Join(dir, "distro", "ubuntu-24.pkrvars.hcl"), "")
			},
			want: []string{"ubuntu-24"},
		},
		{
			name: "only services exists",
			setup: func(t *testing.T, dir string) {
				mustMkdirAll(t, filepath.Join(dir, "services"))
				mustWriteFile(t, filepath.Join(dir, "services", "base-docker-harbor.pkrvars.hcl"), "")
			},
			want: []string{"base-docker-harbor"},
		},
		{
			name:  "both missing",
			setup: func(t *testing.T, dir string) {},
			want:  nil,
		},
		{
			name: "values.pkrvars.hcl excluded from both distro and services",
			setup: func(t *testing.T, dir string) {
				mustMkdirAll(t, filepath.Join(dir, "distro"))
				mustMkdirAll(t, filepath.Join(dir, "services"))
				mustWriteFile(t, filepath.Join(dir, "distro", "values.pkrvars.hcl"), "")
				mustWriteFile(t, filepath.Join(dir, "services", "values.pkrvars.hcl"), "")
			},
			want: nil,
		},
		{
			name: "directory entry with matching suffix is skipped",
			setup: func(t *testing.T, dir string) {
				mustMkdirAll(t, filepath.Join(dir, "distro", "looks-like-a-base.pkrvars.hcl"))
				mustWriteFile(t, filepath.Join(dir, "distro", "real-base.pkrvars.hcl"), "")
			},
			want: []string{"real-base"},
		},
		{
			name: "bare suffix file yields empty base name",
			setup: func(t *testing.T, dir string) {
				mustMkdirAll(t, filepath.Join(dir, "distro"))
				mustWriteFile(t, filepath.Join(dir, "distro", ".pkrvars.hcl"), "")
			},
			want: []string{""},
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			c.setup(t, dir)
			assertDiscoverPackerBases(t, dir, c.want)
		})
	}
}

func assertDiscoverPackerBases(t *testing.T, dir string, want []string) {
	t.Helper()
	got, err := DiscoverPackerBases(dir)
	if err != nil {
		t.Fatalf("DiscoverPackerBases: %v", err)
	}
	if len(got) != len(want) {
		t.Fatalf("DiscoverPackerBases = %v, want %v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("DiscoverPackerBases = %v, want %v", got, want)
		}
	}
}

func TestDiscoverTerraformLayersEmptyAndMixed(t *testing.T) {
	t.Run("empty layers dir yields nil", func(t *testing.T) {
		dir := t.TempDir()
		mustMkdirAll(t, filepath.Join(dir, "layers"))

		got, err := DiscoverTerraformLayers(dir)
		if err != nil {
			t.Fatalf("DiscoverTerraformLayers: %v", err)
		}
		if got != nil {
			t.Errorf("DiscoverTerraformLayers on empty dir = %v, want nil", got)
		}
	})

	t.Run("files are not counted as layers", func(t *testing.T) {
		dir := t.TempDir()
		mustMkdirAll(t, filepath.Join(dir, "layers", "networking"))
		mustWriteFile(t, filepath.Join(dir, "layers", "README.md"), "")

		got, err := DiscoverTerraformLayers(dir)
		if err != nil {
			t.Fatalf("DiscoverTerraformLayers: %v", err)
		}
		if len(got) != 1 || got[0] != "networking" {
			t.Errorf("DiscoverTerraformLayers = %v, want [networking]", got)
		}
	})
}

func TestDiscoverProdVaultInventoryEdgeCases(t *testing.T) {
	t.Run("vault_vip line absent", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "inventory-platform-vault-frontend.yaml")
		mustWriteFile(t, path, "some_other_key: value\n")

		inv, err := DiscoverProdVaultInventory(dir)
		if err != nil {
			t.Fatalf("DiscoverProdVaultInventory: %v", err)
		}
		if inv.File != path {
			t.Errorf("File = %q, want %q", inv.File, path)
		}
		if inv.Addr != "" {
			t.Errorf("Addr = %q, want empty", inv.Addr)
		}
	})

	t.Run("vault_vip present but empty", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "inventory-platform-vault-frontend.yaml")
		mustWriteFile(t, path, `"vault_vip": ""`+"\n")

		inv, err := DiscoverProdVaultInventory(dir)
		if err != nil {
			t.Fatalf("DiscoverProdVaultInventory: %v", err)
		}
		if inv.Addr != "" {
			t.Errorf("Addr = %q, want empty for blank vault_vip", inv.Addr)
		}
	})

	t.Run("malformed line does not match regex", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "inventory-platform-vault-frontend.yaml")
		mustWriteFile(t, path, "vault_vip: 172.16.136.250\n")

		inv, err := DiscoverProdVaultInventory(dir)
		if err != nil {
			t.Fatalf("DiscoverProdVaultInventory: %v", err)
		}
		if inv.Addr != "" {
			t.Errorf("Addr = %q, want empty (unquoted key:value form does not match)", inv.Addr)
		}
	})
}
