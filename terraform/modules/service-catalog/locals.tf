
/**
 * service-catalog: Naming and Identity Topology
 *
 * Generates the semantic identities for all components declared in the
 * calling project's service_catalog.
 * 1. Role Names: Logical names for Vault/Ansible/K8s roles.
 *    Format: {project}-{service}-{component}-role
 * 2. DNS SANs: Subject Alternative Names for TLS certificates.
 *    Supports primary entrypoints (gitlab.prod...) and secondary (kas.gitlab.prod...).
 * 3. Identity Maps: Naming conventions for Libvirt pools, bridges, and nodes.
 */

locals {
  /**
   * 1. Consolidated Service-Component Catalog (SSoT for Naming & Metadata)
   *    This is the "One Place" where all catalog entries are flattened
   *    and assigned deterministic identities.
   */
  _flat_catalog = merge([
    for s_name, s in var.service_catalog : {
      for c_name, c in s.components : "${s_name}-${c_name}" => {
        service_name      = s_name
        comp_name         = c_name
        config            = c
        project           = s.project_code
        stage             = s.stage
        owner             = s.owner
        cluster_name      = "${s.project_code}-${s_name}-${c_name}"
        storage_pool_name = "${s.project_code}-${s_name}-${c_name}-pool"
        hash_prefix       = substr(md5("${s.project_code}-${s_name}-${c_name}"), 0, 8)
      }
    }
  ]...)

  /**
   * 2. Component Roles and DNS Names
   *    Calculates logical roles and certificate metadata.
   */
  component_roles = flatten([
    for key, item in local._flat_catalog : {
      key       = key
      role_name = "${item.cluster_name}-role"
      ttl_stage = item.stage

      # Set to true if the component features an active external ingress route, separating external
      # routing from internal mTLS SANs and avoiding redundant evaluation of the non-empty dns_san variable.
      has_ingress = length(coalesce(item.config.ingress, {})) > 0

      # DNS SAN Strategy
      # 1. DNS Resolution Validation (RFC 1034/1035):
      #    Supports many-to-one mapping. Resolver is unidirectional and does not conflict with Layer 7 routing.
      # 2. TLS/SSL Handshake Validation (RFC 5280/6066):
      #    Utilizes X.509 SAN extensions and SNI for domain-level isolation and certificate matching.

      # Always include a deterministic default SAN for internal certificates.
      # Merge with any Ingress-defined SANs to ensure dns_san[0] is always safe.
      dns_san = distinct(concat(
        flatten([
          for i_key, i_data in coalesce(item.config.ingress, {}) : [
            for sub in i_data.subdomains :
            join(".", compact([
              sub,
              # Use conditional lookup to avoid ternary operator
              lookup({ (item.service_name) = "" }, sub, item.service_name),
              item.stage,
              var.domain_suffix
            ]))
          ]
        ]),
        # Base Service SAN (e.g. keycloak.production.iac.internal)
        item.comp_name == "frontend" ? ["${item.service_name}.${item.stage}.${var.domain_suffix}"] : [],
        ["${item.cluster_name}.${item.stage}.${var.domain_suffix}"]
      ))

      # Organizational Unit (OU) encodes metadata into the certificate subject
      ou = [
        "Provider=${item.config.provider}",
        "Env=${item.stage}",
        "Owner=${item.owner}",
        "Project=${item.project}",
        "Runtime=${item.config.runtime}",
        "Tag=${join(",", coalesce(item.config.tags, []))}"
      ]

      auth_config = {
        method       = contains(["kubeadm", "microk8s"], item.config.runtime) ? "kubernetes" : "approle"
        path         = contains(["kubeadm", "microk8s"], item.config.runtime) ? "kubernetes/${item.service_name}/${item.comp_name}" : "workload-approle"
        approle_path = "workload-approle"
      }

      # Derive client_id from cluster_name to maintain uniform identity across layers.
      # Downstream OIDC provisioning modules resolve client attributes directly
      # from global_pki_map to eliminate redundant resource definitions.
      oidc_client = item.config.oidc_client != null ? merge(item.config.oidc_client, {
        client_id = item.cluster_name
      }) : null
    }
  ])

  # Final PKI attribute mapping used by TLS/Vault layers
  pki_map = { for item in local.component_roles : item.key => item }

  /**
   * 3. Semantic Identity Mapping
   *    Generates deterministic names for OS-level and Hypervisor-level objects.
   */

  # Final Identity Map, the SSoT for naming everything in the datacenter
  identity_map = {
    for key, item in local._flat_catalog : key => {
      cluster_name      = item.cluster_name
      stage             = item.stage
      storage_pool_name = item.storage_pool_name
      bridge_name_host  = "vbr${item.hash_prefix}"
      bridge_name_nat   = "vbr${item.hash_prefix}-n"
      node_name_prefix  = "${item.cluster_name}-node"
      ansible_inventory = "inventory-${item.cluster_name}.yaml"
      ssh_config        = "ssh_${item.cluster_name}"

      # Group-specific naming (e.g. master/worker nodes)
      groups = {
        for group in coalesce(item.config.node_groups, []) :
        group => {
          node_name_prefix = "${item.cluster_name}-${group}-node"
        }
      }
    }
  }
}

/**
 * service-catalog: Network Topology
 *
 * Computes the exact IPv4 addresses, subnets, and MAC addresses for all
 * components defined in service_catalog.
 * 1. Subnets: Each component is assigned a /24 subnet calculated from
 *    the base CIDR and component's cidr_index.
 * 2. Source: References the unified _flat_catalog above to ensure a
 *    single point of iteration for all metadata layers.
 * 3. IPs: Node IPs are calculated based on node_ip_start and iteration counts.
 * 4. VIPs: A fixed VIP (.250) is assigned to each segment for LB usage.
 */

locals {
  /**
   * 1. Generate Map of Network Topology
   *    Calculates CIDRs, VIPs, and host IP arrays for each component.
   */
  network_topology = {
    for key, item in local._flat_catalog : key => {
      segment_key = key
      cidr_block  = cidrsubnet(var.network_baseline.cidr_block, 8, item.config.cidr_index)

      # NAT calculation (Internal logic for gateway isolation)
      nat_gateway    = cidrhost(cidrsubnet(var.network_baseline.cidr_block, 8, item.config.cidr_index - 124), 1)
      nat_cidr_block = cidrsubnet(var.network_baseline.cidr_block, 8, item.config.cidr_index - 124)
      nat_cidr_index = item.config.cidr_index - 124

      nat_dhcp = {
        start = cidrhost(cidrsubnet(var.network_baseline.cidr_block, 8, item.config.cidr_index - 124), 100)
        end   = cidrhost(cidrsubnet(var.network_baseline.cidr_block, 8, item.config.cidr_index - 124), 199)
      }

      # Deterministic bridge name (Linux/Veth compatible)
      # References the pre-calculated hash prefix from _flat_catalog
      interface_alias = "v_${substr(replace(key, "-", ""), 0, 8)}_${substr(item.hash_prefix, 0, 4)}"
      vrid            = item.config.cidr_index
      runtime         = item.config.runtime
      ip_range        = item.config.ip_range
      ports           = coalesce(item.config.ports, {})
      tags            = coalesce(item.config.tags, [])

      # Fixed VIP (.250) for this segment
      vip = cidrhost(
        cidrsubnet(var.network_baseline.cidr_block, 8, item.config.cidr_index),
        var.network_baseline.vip_offset
      )

      # Deterministic mac_address for stable networking across re-plans
      mac_address = "${var.network_baseline.mac_prefix}:${join(":", [
        substr(md5("${item.config.cidr_index}${key}"), 0, 2),
        substr(md5("${item.config.cidr_index}${key}"), 2, 2),
        substr(md5("${item.config.cidr_index}${key}"), 4, 2)
      ])}"

      # Complete list of IPs in the reserved range
      node_ips = [
        for i in range(item.config.ip_range.end_ip - item.config.ip_range.start_ip + 1) :
        cidrhost(cidrsubnet(var.network_baseline.cidr_block, 8, item.config.cidr_index), item.config.ip_range.start_ip + i)
      ]
    }
  }

  /**
   * 2. Global DNS Registry (SSoT)
   *    Extracts all DNS SANs from the pki_map and associates them with
   *    their deterministic segment VIPs for Libvirt DNS injection.
   */
  dns_records = flatten([
    for key, pki in local.pki_map : [
      for san in pki.dns_san : {
        hostname = san
        ip       = local.network_topology[key].vip
      }
    ]
  ])
}

/**
 * service-catalog: Volume Topology
 *
 * Calculates the deterministic storage volume names and pool mappings
 * for all components that require persistent data disks.
 * 1. Segments: Filters the unified _flat_catalog above for components
 *    with data_disks.
 * 2. Mapping: Generates a Cartesian Product based on pre-calculated identities.
 * 3. Result: A flat map of volume names and their associated attributes
 *    (pool, capacity, base_id) for downstream VM provisioning.
 */

locals {
  /**
   * 1. Construct the flat Volume Topology (Cartesian Product).
   *    Time Complexity: O(Segments * Nodes * Disks)
   *
   *    This implementation references the "One Place" identity source
   *    above to ensure zero naming redundancy.
   */
  _volume_topology_raw = flatten([
    for key, item in local._flat_catalog : [
      for i in range(item.config.ip_range.end_ip - item.config.ip_range.start_ip + 1) : [
        for disk in item.config.data_disks : {
          # Use pre-calculated identities from above.
          # Suffixes the volume name for string formatting.
          base_id      = item.cluster_name
          pool_name    = item.storage_pool_name
          volume_name  = "${item.cluster_name}-node-${item.config.ip_range.start_ip + i}-${disk.name_suffix}.qcow2"
          capacity_gib = disk.capacity_gib
        }
      ]
    ]
    if length(coalesce(item.config.data_disks, [])) > 0
  ])

  # Final searchable map used by downstream VM-owning layers
  volume_topology = {
    for vol in local._volume_topology_raw : vol.volume_name => vol
  }
}
