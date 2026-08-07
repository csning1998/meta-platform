#!/bin/bash

set -e -u

# Define base directory and load configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPTS_LIB_DIR="${SCRIPT_DIR}/shell"
readonly TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
readonly PACKER_DIR="${SCRIPT_DIR}/packer"
readonly ANSIBLE_DIR="${SCRIPT_DIR}/ansible"

# Load core utilities first
source "${SCRIPTS_LIB_DIR}/utils.sh"
source "${SCRIPTS_LIB_DIR}/utils_environment.sh"

# MAIN ENVIRONMENT BOOTSTRAP LOGIC
host_os_detail_handler
cpu_virt_support_checker
env_file_bootstrapper "${SCRIPT_DIR}"
iac_layer_discoverer

# Source the .env file to export its variables to any sub-processes
if [ -f .env ]; then
  set -o allexport
  source .env
  set +o allexport
fi

# Set correct permissions since
# This is a leftover from an earlier container-permission mapping strategy and is not currently required.
# if [[ "${ENVIRONMENT_STRATEGY}" == "native" ]]; then
#   check_and_fix_permissions || { log_print "FATAL" "Permission fix failed."; exit 1; }
# fi

# Set Terraform directory based on the selected provider
read -r -a ALL_PACKER_BASES <<< "$ALL_PACKER_BASES"
read -r -a ALL_TERRAFORM_LAYERS <<< "$ALL_TERRAFORM_LAYERS"

# initialize_environment
# All shell/*.sh files except utils.sh and utils_environment.sh (loaded explicitly above)
# are auto-sourced here, matching meta-platform's scripts/ loading pattern.
for lib in "${SCRIPTS_LIB_DIR}"/*.sh; do
  if [[ "$lib" == *"/utils.sh" ]] || [[ "$lib" == *"/utils_environment.sh" ]]; then
    continue
  fi
  source "$lib"
done

#  Main Menu
echo
echo "======= IaC-Driven Virtualization Management ======="
echo

log_print "INFO" "Environment: ${ENVIRONMENT_STRATEGY^^}"
if [[ "${ENVIRONMENT_STRATEGY}" == "container" ]]; then
  log_print "INFO" "Engine: PODMAN"
fi
vault_status_reporter
echo

PS3=$'\n\033[1;34m[INPUT] Please select an action: \033[0m'
options=()

# [Bastion Vault: Bootstrap Unit]
options+=("[BASTION] Set up TLS for Bastion Vault (Local)")
options+=("[BASTION] Initialize Bastion Vault (Local)")
options+=("[BASTION] Unseal Bastion Vault (Local)")
options+=("[BASTION] Enable KV-v2 Engine (Manual Fallback)")

# [Production Vault: PKI Service Provider]
options+=("[PROD] Unseal Production Vault (via Ansible)")

# [Infrastructure]
options+=("Generate SSH Key")
options+=("Verify IaC Environment")

# [Operations]
options+=("Build Packer Base Image")
options+=("Verify Guest VM Connectivity via SSH")
options+=("Switch Environment Strategy")

# [Operations: GitLab]
options+=("[PROD] Revert Gitaly to Standalone for Safety Pre-check")

# [Reset]
options+=("Purge All Packer Artifacts")
options+=("Purge All Infrastructure Resources (Libvirt + Terraform)")
options+=("Quit")

select opt in "${options[@]}"; do
  readonly START_TIME=$(date +%s)

  case $opt in
    # --- Bastion Vault ---
    "[BASTION] Set up TLS for Bastion Vault (Local)")
      vault_bastion_tls_generator
      break
      ;;
    "[BASTION] Initialize Bastion Vault (Local)")
      vault_bastion_init_handler
      break
      ;;
    "[BASTION] Unseal Bastion Vault (Local)")
      vault_bastion_unseal_handler
      break
      ;;
    "[BASTION] Enable KV-v2 Engine (Manual Fallback)")
      vault_bastion_engine_enforcer
      break
      ;;

    # --- Production Vault ---
    "[PROD] Unseal Production Vault (via Ansible)")
      vault_prod_unseal_trigger
      break
      ;;

    # --- Infrastructure ---
    "Generate SSH Key")
      log_print "STEP" "Generate SSH Key for this project..."
      ssh_key_generator_handler
      log_print "OK" "SSH Key successfully generated."
      break
      ;;
    "Verify IaC Environment")
      env_native_verifier
      break
      ;;

    # --- Operations ---
    "Build Packer Base Image")
      libvirt_service_manager
      packer_menu_handler
      break
      ;;
    "Verify Guest VM Connectivity via SSH")
      if ssh_key_verifier; then ssh_verification_handler; fi
      break
      ;;
    "Switch Environment Strategy")
      strategy_switch_handler
      ;;

    # --- Operations: GitLab ---
    "[PROD] Revert Gitaly to Standalone for Safety Pre-check")
      gitaly_revert_to_standalone_trigger
      break
      ;;

    # --- Reset ---
    "Purge All Packer Artifacts")
      if manual_confirmation_prompter "All Packer artifacts (Images)"; then
        packer_artifact_cleaner "all"
      fi
      break
      ;;
    "Purge All Infrastructure Resources (Libvirt + Terraform)")
      if manual_confirmation_prompter "All Infrastructure (Libvirt VMs/Networks + Terraform States)"; then
        libvirt_service_manager
        libvirt_resource_purger "all"
        terraform_artifact_cleaner "all"
        execution_time_reporter
      fi
      break
      ;;
    "Quit")
      log_print "INFO" "Exiting script."
      break
      ;;
    *) log_print "ERROR" "Invalid option $REPLY";;
  esac
done
