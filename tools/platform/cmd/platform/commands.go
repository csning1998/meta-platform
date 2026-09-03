package main

import (
	"github.com/spf13/cobra"

	"platform/internal/libvirtops"
	"platform/internal/packerops"
	"platform/internal/terraformops"
)

func (a *app) vaultCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "vault", Short: "Bastion and Production Vault operations"}

	cmd.AddCommand(&cobra.Command{
		Use:   "tls-generate",
		Short: "[BASTION] Generate TLS certificates for Bastion Vault (destroys existing files)",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.generateVaultTLS(cmd.Context()) },
	})
	cmd.AddCommand(&cobra.Command{
		Use:   "init",
		Short: "[BASTION] Initialize Bastion Vault",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.initVault(cmd.Context()) },
	})
	cmd.AddCommand(&cobra.Command{
		Use:   "enable-kv",
		Short: "[BASTION] Enable KV-v2 engine",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.enableVaultKV(cmd.Context()) },
	})
	cmd.AddCommand(&cobra.Command{
		Use:   "unseal",
		Short: "[BASTION] Unseal Bastion Vault",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.unsealVault(cmd.Context()) },
	})
	cmd.AddCommand(&cobra.Command{
		Use:   "prod-unseal",
		Short: "[PROD] Unseal Production Vault via Ansible",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.unsealProdVault(cmd.Context()) },
	})

	return cmd
}

func (a *app) sshCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "ssh", Short: "SSH key and connectivity operations"}

	var keyName string
	var overwrite bool
	genCmd := &cobra.Command{
		Use:   "keygen",
		Short: "Generate an ed25519 SSH key for IaC automation",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.generateSSHKey(keyName, overwrite) },
	}
	genCmd.Flags().StringVar(&keyName, "name", "id_ed25519_meta-platform", "key file name under $HOME/.ssh")
	genCmd.Flags().BoolVar(&overwrite, "overwrite", false, "overwrite an existing key")
	cmd.AddCommand(genCmd)

	cmd.AddCommand(&cobra.Command{
		Use:   "verify",
		Short: "Verify guest VM connectivity via SSH",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.verifySSHConnectivity() },
	})

	return cmd
}

func (a *app) envCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "env", Short: "Environment verification"}
	cmd.AddCommand(&cobra.Command{
		Use:   "verify",
		Short: "Verify the full native IaC environment (non-interactive)",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.verifyEnvironment() },
	})
	return cmd
}

func (a *app) packerCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "packer", Short: "Packer image build management"}

	cmd.AddCommand(&cobra.Command{
		Use:   "build <base>",
		Short: "Clean and build one Packer base (or 'all')",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return a.buildPackerImage(cmd.Context(), args[0])
		},
	})
	cmd.AddCommand(&cobra.Command{
		Use:   "clean <base|all>",
		Short: "Clean Packer output artifacts and host cache",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return packerops.Clean(a.packerDir, args[0], getConfiguredPackerBases(a.env), a.packerCache, a.out)
		},
	})
	cmd.AddCommand(&cobra.Command{
		Use:   "purge-all",
		Short: "Clean every discovered Packer base's output and the host cache",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.purgeAllPackerArtifacts() },
	})

	return cmd
}

func (a *app) terraformCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "terraform", Short: "Terraform layer artifact management"}
	cmd.AddCommand(&cobra.Command{
		Use:   "clean <layer|all>",
		Short: "Report Terraform artifact cleanup status for a layer (or 'all')",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return terraformops.ReportCleanupStatus(a.terraform, args[0], getConfiguredTerraformLayers(a.env), a.out)
		},
	})
	return cmd
}

func (a *app) gitalyCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "gitaly", Short: "Gitaly operations"}
	cmd.AddCommand(&cobra.Command{
		Use:   "revert-precheck",
		Short: "[PROD] Safety pre-check before reverting Gitaly to standalone",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.confirmGitalyRevertPrecheck(cmd.Context()) },
	})
	return cmd
}

func (a *app) libvirtCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "libvirt", Short: "libvirt/KVM resource management"}
	cmd.AddCommand(&cobra.Command{
		Use:   "ensure-services",
		Short: "Start any inactive libvirt daemon sockets",
		RunE:  func(cmd *cobra.Command, args []string) error { return libvirtops.EnsureServices(a.out) },
	})
	cmd.AddCommand(&cobra.Command{
		Use:   "purge",
		Short: "Destroy every libvirt VM/pool/network under the platform project code",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.purgeLibvirtResources() },
	})
	return cmd
}

func (a *app) strategyCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "strategy", Short: "Guest-VM provisioning strategy"}
	cmd.AddCommand(&cobra.Command{
		Use:   "switch",
		Short: "Toggle ENVIRONMENT_STRATEGY between native and container",
		RunE:  func(cmd *cobra.Command, args []string) error { return a.switchStrategy() },
	})
	return cmd
}
