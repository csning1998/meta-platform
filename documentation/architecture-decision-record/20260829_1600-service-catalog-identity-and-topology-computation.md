# ADR: `service-catalog` Identity, Network, and Volume Topology Computation

## Section 1. Executive Summary and Final Verdict

1. **Decoupled State Abstraction**: `service-catalog/locals.tf` MUST compute three isolated output projections from a unified `_flat_catalog` data source: identity and naming (`component_roles`, `identity_map`), network topology (`network_topology`, `dns_records`), and volume topology (`volume_topology`). Each domain SHALL be encapsulated within an independent `locals` block to guarantee modification scoping and structural decoupling.
2. **Single Point of Iteration**: Downstream evaluation loops SHALL consume `_flat_catalog` exclusively and MUST NOT reference `var.service_catalog` directly. This restriction ensures that `cluster_name`, `storage_pool_name`, and `hash_prefix` remain immutable across identity, network, and storage outputs for any given component.
3. **Dual RFC Domain Unification**: The `dns_san` attribute SHALL concurrently satisfy DNS hostname resolution requirements (RFC 1034 / RFC 1035) and TLS certificate validation specifications (RFC 5280 X.509 SAN / RFC 6066 SNI). A single list MUST serve both domains to maintain mandatory parity between resolvable DNS hostnames and certificate SAN extensions.
4. **Separation of Network Mathematics**: Subnet indexing, NAT-pairing, VIP assignment, and MAC address derivation logic SHALL be governed by `20260829_1400-cidr-address-space-parameterization.md`. Mathematical specification of network octets is intentionally omitted from this document.
5. **Inline Commentary Constraints**: Detailed architectural rationale SHALL be maintained within this document. Inline comments within `service-catalog/locals.tf` MUST be restricted to single-line section headers.

## Section 2. Technical Rationale and Architectural Design

### Item A. Identity and Naming Topology

`_flat_catalog` constructs a flattened resource map keyed by `${service_name}-${component_name}`. Primary identity fields SHALL be computed according to the following rules:

- `cluster_name`: Formatted as `${project_code}-${service_name}-${component_name}`. Defines the canonical identifier for Vault policies, Ansible target scopes, and Kubernetes RBAC declarations.
- `storage_pool_name`: Formatted as `${cluster_name}-pool` for explicit binding within volume topology configurations.
- `hash_prefix`: Extracted as the first 8 hexadecimal characters of `md5(cluster_name)`. Constructs deterministic, fixed-length network interface identifiers.

Network bridge identifiers (`bridge_name_host` and `bridge_name_nat`) MUST be derived from `hash_prefix` to enforce compliance with the Linux kernel 15-character interface identifier ceiling.

### Item B. DNS SAN Strategy

The `dns_san` collection MUST incorporate the default entry `${cluster_name}.${stage}.${domain_suffix}` regardless of ingress configuration.

When `comp_name` evaluates to `"frontend"`, the service-level entry `${service_name}.${stage}.${domain_suffix}` MUST be appended. Subdomains declared within `ingress` definitions SHALL be appended to default entries. Uniqueness across the aggregated collection MUST be enforced via `distinct()`.

### Item C. Runtime Authentication Branching

The `auth_config.method` attribute SHALL be evaluated based on the execution target:

- **Kubernetes Runtimes (`kubeadm`, `microk8s`)**: MUST evaluate to `"kubernetes"`, allowing workloads to authenticate via service account token exchange with Vault (`auth/kubernetes`).
- **Non-Kubernetes Runtimes**: MUST evaluate to `"approle"`, requiring credential retrieval via static AppRole identifiers.

### Item D. OIDC Client Identification

When an `oidc_client` configuration block is declared, `oidc_client.client_id` MUST be set equal to `cluster_name`. Binding client identification directly to `cluster_name` guarantees structural identity alignment across Vault roles, Kubernetes objects, and OIDC client profiles, allowing downstream modules to resolve component attributes strictly via `global_pki_map`.

### Item E. IPv4 Network Topology Mapping

Attributes within `network_topology` MUST map directly to discrete IPv4 octet positions:

- **Virtual IP (VIP) Allocation**: Evaluated as `cidrhost(<HostOnly_Subnet>, network_baseline.host_vip_offset)`. With default `host_vip_offset = 250`, component VIPs SHALL consistently occupy host offset `.250` within their designated `/24` subnets.
- **Node IP Allocation**: Evaluated via sequential `cidrhost()` calls across the offset range defined by `[start_ip, end_ip]`. Calculations MUST read directly from the component `ip_range` configuration block.
- **MAC Address Derivation**: Concatenates `network_baseline.global_mac_prefix` with a 3-byte slice extracted from `md5("${cidr_index}${key}")`, producing deterministic hardware addresses independent of IP octet values.

The `dns_records` collection MUST build a flattened mapping by pairing each `pki_map` `dns_san` hostname entry with the corresponding `network_topology[key].vip` address.

### Item F. Volume Topology Construction

`_volume_topology_raw` MUST generate discrete volume definitions for the Cartesian product of `(component, node index, data disk)` triples for all components declaring a `data_disks` block.

Volume naming SHALL conform to the structure `${cluster_name}-node-${ip_suffix}-${disk_name_suffix}.qcow2`. Embedding the host IP suffix rather than an arbitrary index counter guarantees volume identity stability during node expansion or contraction operations.
