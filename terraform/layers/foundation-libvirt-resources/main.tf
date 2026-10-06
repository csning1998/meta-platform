
module "foundation_libvirt_resources" {
  source = "../../modules/kvm-provisioning/configure/foundation-resources"

  domain_suffix    = var.domain_suffix
  network_baseline = var.network_baseline
  service_catalog  = var.service_catalog
}

# Local SSH client configuration resources MUST be materialized in this foundation layer
# because known_hosts verification requires live guest network connectivity realized in later stages.
module "ssh_identity_bootstrap" {
  source = "git::https://gitlab.com/csning1998-lab/terraform/terraform-provider-sshclient.git//terraform/modules/ssh-identity-bootstrap?ref=49d7d402b9b40183649139fe0eba8be88856f29d"

  identity_hosts = module.foundation_libvirt_resources.ssh_identity.hosts
}
