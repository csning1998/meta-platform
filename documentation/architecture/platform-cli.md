# Platform CLI Architecture Specification

`tools/platform` provides an integrated virtualization and infrastructure management tool for `meta-platform`. The compiled binary MUST reside at the repository root as `meta-platform/platform`.

## Section 1. System Architecture and Interface Model

### Item A. Dual Entry Point

1. The binary MUST support both direct command execution and interactive menu navigation using shared internal operations.
2. Direct execution MUST follow the syntax `platform <group> <verb> [args] [flags]` for non-interactive and scriptable automation.
3. Invocation without subcommands MUST launch the interactive menu defined in `cmd/platform/menu.go`.
4. Core operational logic MUST reside in the `internal/` packages.
5. The CLI command definitions and interactive menu handlers MUST call identical underlying package functions without duplicating business logic.

### Item B. Build and Execution Constraints

1. The binary MUST be built with the command `cd tools/platform && go build -o ../../platform ./cmd/platform`.
2. The executable MUST be invoked with the working directory set to the `meta-platform` repository root.
3. Automatic environment initialization MUST determine `PROJECT_ROOT` from the current working directory.
4. The compiled `platform` binary MUST NOT be tracked in version control and MUST be excluded by `.gitignore`.

## Section 2. Command Reference and Group Specifications

### Item A. Vault Operations (`vault`)

1. `platform vault tls-generate` MUST regenerate the Bastion Vault Certificate Authority and server certificates under `vault/tls/`.
2. `platform vault tls-generate` MUST require explicit confirmation by typing `yes` before overwriting existing cryptographic assets.
3. `platform vault init` MUST initialize the local Bastion Vault using 5 Shamir shares and a 3-share reconstruction threshold.
4. `platform vault init` MUST persist unseal keys to `vault/keys/unseal.key`, persist the root token to `$HOME/.vault-token`, and execute auto-unseal.
5. `platform vault init` MUST refuse execution if `vault/keys/init-output.json` already exists.
6. `platform vault unseal` MUST read unseal keys from `vault/keys/unseal.key` and apply them to the Bastion Vault instance until the sealed status clears.
7. `platform vault enable-kv` MUST mount the `kv-v2` secrets engine at path `secret/` if the mount is not present.
8. `platform vault prod-unseal` MUST execute the `shared-vault-frontend` Ansible playbook with tag `vault-unseal` against the discovered Production Vault inventory.

### Item B. SSH Operations (`ssh`)

1. `platform ssh keygen [--name <key>] [--overwrite]` MUST generate an unencrypted ed25519 keypair at `$HOME/.ssh/<key>` and persist `SSH_PRIVATE_KEY` in `.env`.
2. `platform ssh keygen` MUST default the key name to `id_ed25519_meta-platform`.
3. `platform ssh keygen` MUST fail if the target key file exists and `--overwrite` is not asserted.
4. `platform ssh verify` MUST verify strict public-key connectivity to every `Host` declared in configuration files matching `$HOME/.ssh/ssh_*`.

### Item C. Environment Verification (`env`)

1. `platform env verify` MUST verify the availability of `qemu-system-x86_64`, `virsh`, `packer`, `terraform`, `tofu`, `vault`, and `ansible` on `PATH`.
2. `platform env verify` MUST exit with status code 1 if any prerequisite tool binary is missing.

### Item D. Packer Image Operations (`packer`)

1. `platform packer build <base|all>` MUST clean existing artifacts and execute `packer init` followed by `packer build` for the designated base image.
2. `platform packer clean <base|all>` MUST remove designated build output directories under `packer/output/` and purge non-ISO files from `$HOME/.cache/packer`.
3. `platform packer purge-all` MUST clean all build outputs and host caches across all discovered Packer bases.

### Item E. Terraform Layer Operations (`terraform`)

1. `platform terraform clean <layer|all>` MUST verify the existence of layer directories under `terraform/layers/` and report artifact cleanup status.
2. `platform terraform clean` MUST NOT delete state files because Terraform remote state is stored in the GitLab HTTP backend.

### Item F. Gitaly Operations (`gitaly`)

1. `platform gitaly revert-precheck` MUST execute the `core-gitlab-praefect` Ansible playbook with tag `gitaly-revert-standalone`.
2. `platform gitaly revert-precheck` MUST require explicit confirmation by typing `Y` or `y` prior to execution.
3. A failure in `platform gitaly revert-precheck` MUST block removal of Praefect nodes in Terraform configuration.

### Item G. Libvirt and KVM Operations (`libvirt`)

1. `platform libvirt ensure-services` MUST verify that modular libvirt sockets (`virtqemud.socket`, `virtnetworkd.socket`, `virtstoraged.socket`) are active, starting inactive units via `sudo systemctl start`.
2. `platform libvirt purge` MUST destroy and undefine all domains, storage pools, storage volumes, and virtual networks whose names begin with the `platform-` prefix.
3. `platform libvirt purge` MUST require explicit user confirmation by typing `Y` or `y` prior to resource destruction.

### Item H. Strategy Configuration (`strategy`)

1. `platform strategy switch` MUST toggle `ENVIRONMENT_STRATEGY` between `native` and `container`.
2. `platform strategy switch` MUST remove `terraform/.terraform` and `terraform/.terraform.lock.hcl`.
3. `platform strategy switch` MUST recompute `PKR_VAR_NET_BRIDGE` and `PKR_VAR_NET_DEVICE` based on strategy and bridge availability.

## Section 3. Interactive Menu Navigation

### Item A. Menu Structure and Action Mapping

The interactive menu MUST present options in the following sequence:

| Number | Menu Option Label                                          | Target Command                                                      |
| :----- | :--------------------------------------------------------- | :------------------------------------------------------------------ |
| 1      | `[BASTION] Set up TLS for Bastion Vault (Local)`           | `platform vault tls-generate`                                       |
| 2      | `[BASTION] Initialize Bastion Vault (Local)`               | `platform vault init`                                               |
| 3      | `[BASTION] Unseal Bastion Vault (Local)`                   | `platform vault unseal`                                             |
| 4      | `[BASTION] Enable KV-v2 Engine (Manual Fallback)`          | `platform vault enable-kv`                                          |
| 5      | `[PROD] Unseal Production Vault (via Ansible)`             | `platform vault prod-unseal`                                        |
| 6      | `Generate SSH Key`                                         | Interactive prompt for key name, then `platform ssh keygen`         |
| 7      | `Verify IaC Environment`                                   | `platform env verify`                                               |
| 8      | `Build Packer Base Image`                                  | Packer category submenu                                             |
| 9      | `Verify Guest VM Connectivity via SSH`                     | Confirmation prompt, then `platform ssh verify`                     |
| 10     | `Switch Environment Strategy`                              | `platform strategy switch`                                          |
| 11     | `[PROD] Revert Gitaly to Standalone for Safety Pre-check`  | `platform gitaly revert-precheck`                                   |
| 12     | `Purge All Packer Artifacts`                               | `platform packer purge-all`                                         |
| 13     | `Purge All Infrastructure Resources (Libvirt + Terraform)` | `platform libvirt purge` followed by `platform terraform clean all` |
| 14     | `Quit`                                                     | Terminates menu execution                                           |

### Item B. Packer Submenu Navigation

1. Selection of `Build Packer Base Image` MUST display four category choices: `Base OS Layers`, `Service Layers`, `Build ALL`, and `Back to Main Menu`.
2. `Base OS Layers` MUST enumerate all `*.pkrvars.hcl` files in `packer/distro/` alongside `Build ALL in Base OS Images` and `Back`.
3. `Service Layers` MUST enumerate all `*.pkrvars.hcl` files in `packer/services/` alongside `Build ALL in Service Images` and `Back`.
4. `Build ALL` MUST execute artifact cleanup for all layers, build all distro base layers in alphabetical sequence, and subsequently build all service layers in alphabetical sequence.

## Section 4. Architectural Implementation Strategy

### Item A. Delegation Strategy and Trade-offs

1. Operations MUST use official or standard Go client libraries when direct network APIs exist.
2. Operations MAY delegate to system command-line binaries when no Go library exists or when exact CLI behavior and configuration compatibility must be preserved.

### Item B. Component Implementation Classification

| Subsystem                                         | Implementation Mechanism         | Architectural Rationale and Cost Analysis                                                                                            |
| :------------------------------------------------ | :------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------- |
| `internal/vaultops`                               | `github.com/hashicorp/vault/api` | Direct HTTP/TLS API communication without container execution overhead. Requires TLS CA certificate configuration.                   |
| `internal/vaultops` (TLS)                         | `crypto/x509`, `crypto/rsa`      | Native standard library execution. Eliminates runtime dependencies on the `openssl` binary.                                          |
| `internal/sshops` (Keygen/Scan)                   | `golang.org/x/crypto/ssh`        | In-memory key generation and concurrent TCP host key scanning. Eliminates external shell script forks.                               |
| `internal/sshops` (Verify)                        | `ssh` CLI binary                 | Preserves full OpenSSH configuration compatibility (`Host`, `ProxyJump`, `UserKnownHostsFile`). Incurs child process execution cost. |
| `internal/libvirtops` (Purge)                     | `libvirt.org/go/libvirt` (CGO)   | Direct RPC interaction with `libvirtd`. Requires system development headers at compile time.                                         |
| `internal/packerops` (Build)                      | `packer` CLI binary              | Official CLI automation of HCL templates and plugins. Incurs subprocess management overhead.                                         |
| `internal/gitalyops`, `vaultops.UnsealProduction` | `ansible-playbook` CLI binary    | Playbook execution utilizing existing Ansible role collections. Incurs Python interpreter startup overhead.                          |
| `internal/libvirtops.EnsureServices`              | `systemctl` CLI binary           | Systemd socket activation management. Avoids heavyweight D-Bus library bindings.                                                     |

### Item C. Libvirt Resource Cleanup Invariant

1. `virDomainUndefineFlags` in the Libvirt API does not provide a flag equivalent to `virsh undefine --remove-all-storage`.
2. `libvirtops.Purge` MUST destroy and undefine domains with `DOMAIN_UNDEFINE_NVRAM`.
3. Domain disk volumes living in storage pools matching the `platform-` prefix MUST be deleted during the subsequent storage pool iteration sweep.

## Section 5. Configuration and State Management

### Item A. Environment Configuration (`.env`)

1. All environment variable keys read or modified by the application MUST be declared as constants in `internal/config/keys.go`.
2. Variables in `.env` MUST use `KEY="VALUE"` format for interoperability with shell environments.
3. `config.Bootstrap` MUST discover Packer bases from `packer/distro` and `packer/services`, Terraform layers from `terraform/layers`, and Vault Ansible inventory from `ansible/inventory-*-vault-frontend.yaml`.
4. `config.Env.Environ()` MUST expand variable references in the form `${VAR_NAME}` against preceding file keys and the parent process environment.

### Item B. Idempotency Guarantees

1. File modifications to `.env` and `$HOME/.vault-token` MUST be performed via atomic temporary file writes followed by file renames.
2. Token synchronization in `vaultops.SyncToken` MUST enforce file permissions `0600` on `$HOME/.vault-token`.
3. SSH configuration injection in `sshops.AddIncludeConfig` MUST check for line existence before modification to guarantee idempotency across repeated runs.

## Section 6. Build Prerequisites and Compilation Constraints

1. Compiling `internal/libvirtops` REQUIRES the `libvirt-devel` package on Fedora/RHEL systems or `libvirt-dev` on Debian/Ubuntu systems.
2. System dependency installation is automated by Ansible role `ansible/roles/hypervisor_baseline/tasks/libvirt-dev-headers.yaml`.
3. The build environment MUST support CGO compilation (`CGO_ENABLED=1`).

## Section 7. Quality Assurance and Testing Standards

1. Unit tests MUST NOT depend on active Vault, SPIRE, or Libvirt daemon instances.
2. Unit tests MUST NOT modify paths outside `t.TempDir()`.
3. Filesystem paths, home directories, and operational contexts MUST be passed as explicit parameters to internal packages to enable test isolation.
4. All packages MUST satisfy `golangci-lint` verification with zero errors.
