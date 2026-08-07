
# This file defines all variables for the data-driven Packer build.

# Build Control Variables

variable "build_name" {
  type        = string
  description = "The name of the build, derived from the var-file name."
}

variable "vnc_port" {
  type        = number
  description = "VNC port for the build."
}

# Common Variables, from *.pkrvars.hcl or command line

variable "common_spec" {
  type = object({
    cpus      = number
    memory    = number
    disk_size = number
  })
  description = "Defines common hardware parameters shareable across any OS."
}

variable "os_spec" {
  type = object({
    distro  = string
    version = string
  })
  description = "Defines OS-specific metadata (distro, version) used for the output image name."
}

variable "source_image" {
  type        = string
  description = "Relative path to the backing qcow2 image produced by the distro build stage."
}

variable "source_image_checksum" {
  type    = string
  default = "none"
}

variable "net_bridge" {
  type    = string
  default = "virbr0"
}

variable "net_device" {
  type    = string
  default = "virtio-net"
}

variable "secrets_path" {
  type    = string
  default = "secret/data/meta-platform/guest_vm"
}
