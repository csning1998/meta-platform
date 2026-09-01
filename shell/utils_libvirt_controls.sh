#!/bin/bash

# This script contains functions for controlling KVM/libvirt services and VMs.

# Project code filter that matches project_code in foundation-metadata terraform.tfvars
readonly PROJECT_CODE="platform"

# Function: Ensure every modular libvirt daemon socket is running before executing a command.
# The purge routine dispatches pool/net commands to virtstoraged/virtnetworkd, not only virtqemud.
libvirt_service_manager() {
  log_print "INFO" "Checking status of libvirt sockets..."

  for _sock in virtqemud.socket virtnetworkd.socket virtstoraged.socket; do
    # Query-only: unprivileged users can read systemd unit status without sudo.
    if ! systemctl is-active --quiet "$_sock"; then
      log_print "WARN" "$_sock is not running. Attempting to start it..."

      # Use 'sudo' since starting a system-level socket unit requires privilege
      # regardless of the rootless virsh client connection.
      if sudo systemctl start "$_sock"; then
        log_print "OK" "$_sock started successfully."
        # Give the service a moment to initialize networks.
        sleep 2
      else
        log_print "FATAL" "Failed to start $_sock. Please check 'systemctl status $_sock'."
        # Exit the script if a core dependency cannot be started.
        exit 1
      fi
    else
      log_print "OK" "$_sock is already running."
    fi
  done
}

# Function: Forcefully clean up all libvirt resources with project_code = PROJECT_CODE.
libvirt_resource_purger() {
  log_print "STEP" "Detecting and purging all resources with project_code = '${PROJECT_CODE}'..."

  # 1. Purge VMs (Domains) starting with PROJECT_CODE-
  log_print "STEP" "Purging Virtual Machines (Domains)..."
  for vm in $(virsh -c qemu:///system list --all --name | grep "^${PROJECT_CODE}-" || true); do
    if [[ -n "$vm" ]]; then
      log_print "TASK" "Destroying and undefining VM: $vm"
      virsh -c qemu:///system destroy "$vm" >/dev/null 2>&1 || true
      virsh -c qemu:///system undefine "$vm" --nvram --remove-all-storage >/dev/null 2>&1 || true
    fi
  done

  # 2. Purge Storage Volumes and Pools starting with PROJECT_CODE-
  log_print "STEP" "Purging Storage Volumes and Pools..."
  for pool in $(virsh -c qemu:///system pool-list --all --name | grep "^${PROJECT_CODE}-" || true); do
    if virsh -c qemu:///system pool-info "$pool" >/dev/null 2>&1; then
      # Delete all volumes within the pool
      for vol in $(virsh -c qemu:///system vol-list "$pool" | awk 'NR>2 {print $1}' || true); do
        if [[ -n "$vol" ]]; then
          log_print "TASK" "Deleting volume: $vol from pool $pool"
          virsh -c qemu:///system vol-delete --pool "$pool" "$vol" >/dev/null 2>&1 || true
        fi
      done
      # Destroy and undefine the pool itself
      log_print "TASK" "Destroying and undefining pool: $pool"
      virsh -c qemu:///system pool-destroy "$pool" >/dev/null 2>&1 || true
      virsh -c qemu:///system pool-undefine "$pool" >/dev/null 2>&1 || true
    else
      log_print "INFO" "Storage pool $pool does not exist, skipping."
    fi
  done

  # 3. Purge Networks starting with PROJECT_CODE-
  log_print "STEP" "Purging Networks..."
  for net in $(virsh -c qemu:///system net-list --all --name | grep "^${PROJECT_CODE}-" || true); do
    if virsh -c qemu:///system net-info "$net" >/dev/null 2>&1; then
      log_print "TASK" "Destroying and undefining network: $net"
      virsh -c qemu:///system net-destroy "$net" >/dev/null 2>&1 || true
      virsh -c qemu:///system net-undefine "$net" >/dev/null 2>&1 || true
    fi
  done

  log_divider
  log_print "OK" "Libvirt resource purge complete."
  log_divider
}
