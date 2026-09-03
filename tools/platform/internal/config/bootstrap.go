package config

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"platform/internal/ui"
)

// PackerNetConfig defines network interface parameters (PKR_VAR_NET_BRIDGE and PKR_VAR_NET_DEVICE)
// for Packer execution environments.
type PackerNetConfig struct {
	Bridge string
	Device string
}

// ComputePackerNetConfig determines Packer network device and bridge settings based on strategy type
// and virbr0 interface availability. Container strategy forces user-mode (SLIRP) networking.
func ComputePackerNetConfig(strategy string, out *ui.Printer) PackerNetConfig {
	cfg := PackerNetConfig{Device: "virtio-net"}
	if strategy == StrategyContainer {
		out.Print(ui.Warn, "Container strategy detected. Forcing User Mode Networking (SLIRP) for Packer.")
		return cfg
	}
	if exec.Command("ip", "link", "show", "virbr0").Run() == nil {
		cfg.Bridge = "virbr0"
		out.Print(ui.Info, "Network Mode: Bridge detected (virbr0). Using performance networking.")
	} else {
		out.Print(ui.Warn, "'virbr0' bridge not found. Defaulting to user-mode/SLIRP networking.")
	}
	return cfg
}

// BootstrapEnv initializes or updates root/.env with default settings, host facts, and
// dynamically discovered infrastructure layers.
func BootstrapEnv(root, packerDir, terraformDir, ansibleDir string, out *ui.Printer) (*Env, error) {
	envPath := filepath.Join(root, ".env")
	facts, err := DetectHostFacts()
	if err != nil {
		return nil, err
	}

	e, err := Load(envPath)
	if err != nil {
		return nil, err
	}

	if _, statErr := os.Stat(envPath); os.IsNotExist(statErr) {
		out.Print(ui.Info, "Creating new .env file...")
		for _, kv := range [][2]string{
			{"PROJECT_ROOT", root},
			{"ENVIRONMENT_STRATEGY", "native"},
			{"ALL_PACKER_BASES", ""},
			{"ALL_TERRAFORM_LAYERS", ""},
			{"PROD_VAULT_INVENTORY_FILE", ""},
			{"PROD_VAULT_ADDR", ""},
			{"DEV_VAULT_ADDR", "https://127.0.0.1:8200"},
			{"DEV_VAULT_CACERT", "${PROJECT_ROOT}/vault/tls/ca.pem"},
			{"VAULT_TOKEN", ""},
			{"HOST_UID", strconv.Itoa(facts.CurrentUID)},
			{"HOST_GID", strconv.Itoa(facts.CurrentGID)},
			{"UNAME", facts.CurrentUname},
			{"UHOME", "${HOME}"},
			{"PKR_VAR_NET_BRIDGE", ""},
			{"PKR_VAR_NET_DEVICE", "virtio-net"},
			{"LIBVIRT_GID", strconv.Itoa(facts.LibvirtGID)},
		} {
			e.Set(kv[0], kv[1])
		}
	} else {
		e.Set("HOST_UID", strconv.Itoa(facts.CurrentUID))
		e.Set("HOST_GID", strconv.Itoa(facts.CurrentGID))
		e.Set("PROJECT_ROOT", root)
		e.Set("LIBVIRT_GID", strconv.Itoa(facts.LibvirtGID))
		if e.Get("ENVIRONMENT_STRATEGY") == "" {
			e.Set("ENVIRONMENT_STRATEGY", "native")
		}
	}

	packerBases, err := DiscoverPackerBases(packerDir)
	if err != nil {
		return nil, err
	}
	e.Set("ALL_PACKER_BASES", strings.Join(packerBases, " "))

	tfLayers, err := DiscoverTerraformLayers(terraformDir)
	if err != nil {
		return nil, err
	}
	e.Set("ALL_TERRAFORM_LAYERS", strings.Join(tfLayers, " "))

	inv, err := DiscoverProdVaultInventory(ansibleDir)
	if err != nil {
		return nil, err
	}
	e.Set("PROD_VAULT_INVENTORY_FILE", inv.File)
	e.Set("PROD_VAULT_ADDR", inv.Addr)

	strategy := e.Get("ENVIRONMENT_STRATEGY")
	if strategy == "" {
		strategy = "native"
	}
	net := ComputePackerNetConfig(strategy, out)
	e.Set("PKR_VAR_NET_BRIDGE", net.Bridge)
	e.Set("PKR_VAR_NET_DEVICE", net.Device)

	if err := e.Save(); err != nil {
		return nil, err
	}
	return e, nil
}
