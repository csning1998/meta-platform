# Platform and Provision Cilium Frontend

This layer provisions a Talos Linux cluster replacing `platform-haproxy-frontend` as the Central Load Balancer, with strategic justification documented in `documentation/architecture-decision-record/20260813_1630-clb-migration-to-talos-cilium.md`. This specification captures technical implementation constraints unexpressible in HCL configuration.

## Section 1. Platform Cilium Layer

### Item A. Layer Contract

Ownership boundaries, downstream output interfaces, and catalog constraints constitute the contractual interface consumed by dependent layers.

1. Ownership Split. Layer `platform-cilium-frontend` manages guest virtual machines, Talos machine configurations, and the Cilium bootstrap manifest, while `provision-cilium-frontend` manages Kubernetes API resources requiring an active control plane. This separation maintains architectural symmetry across repository platform and provision pairs.
2. Downstream Output Names. Five exported output names (`infrastructure_map`, `infrastructure_vips`, `global_topology_identity`, `global_topology_network`, and `global_network_baseline`) maintain compatibility with existing exports from `platform-haproxy-frontend`. Downstream consumers (`platform-harbor-origin-frontend`, `platform-keycloak-frontend`, and `platform-vault-frontend`) require only updated remote state references without modification to their underlying HCL declarations.
3. Catalog Projection. The `segments_map` structure is duplicated from `platform-haproxy-frontend` as a service catalog property, decoupled from specific HAProxy or Cilium load-balancer implementations. Short identifiers in `var.node_config` (e.g., `00`) are expanded into fully qualified hostnames (e.g., `platform-cilium-frontend-node-00`), exposing strictly qualified keys to downstream modules.
4. Resolved SSoT Reservation. Earlier revisions omitted the Central Load Balancer cluster from `net_service_segments`, leaving the cluster endpoint bound to a single node address without a Single Source of Truth (SSoT) IP reservation. The service catalog declares the `cilium` segment with an explicit `cidr_index`, and `svc_network_map` propagates the resulting VIP into this module. Item C describes the endpoint binding that consumes the reservation.

### Item B. Bootstrap Sequence

Cilium MUST achieve active state prior to Kubernetes API availability and Harbor service initialization. The bootstrap sequence defines the CNI manifest injection path, Talos-specific Helm parameters, Hubble disablement for render stability, and post-installation address handoff procedures.

1. Cilium Injection Without Harbor. Direct installation via `helm_release` is impossible during initial provisioning because the Kubernetes API server is offline and Harbor helm repository services depend on the cluster VIP. Instead, `data.helm_template.cilium` renders the upstream chart locally for injection via `cluster.inlineManifests`, enabling Talos to apply the CNI manifest during early node initialization before API availability. To align with Sidero Labs production recommendations, `cluster.network.cni.name` is set to `none` and `cluster.proxy.disabled` is set to `true`.
2. Cilium Values Required by Talos. Because Talos restricts the `SYS_MODULE` capability from workloads, Helm configuration explicitly defines required system capabilities while disabling `cgroup.autoMount` to leverage host-managed `cgroupv2` and `bpffs` mounts. With `kube-proxy` disabled, `k8sServiceHost` and `k8sServicePort` route traffic through the node-local KubePrism endpoint (`localhost:7445`, matching `machine.features.kubePrism.port`) to ensure API connectivity prior to CNI initialization. Setting `ipam.mode` to `kubernetes` alongside `kubeProxyReplacement` and `l2announcements` enables direct service VIP broadcasting across attached network bridges.
3. Hubble Disabled. Hubble remains disabled (`hubble.enabled = false`). Stateless `helm_template` evaluation emits a new self-signed CA on every render. Embedding those certificates in `cluster.inlineManifests` produces spurious `machine_configuration_hash` diffs for Hubble, which this layer does not operate.
4. eBPF Masquerading. Helm value `bpf.masquerade` MUST resolve to `true`. The IPTables masquerade implementation selects an incorrect source device when routing toward bare-metal backends behind the catalog VIPs, and the eBPF implementation binds the source address to the egress path Cilium itself programs.
5. Address Handoff After Installation. Initial node configuration (`talos_machine_configuration_apply`) reaches maintenance-mode nodes via temporary NAT DHCP leases, whereas post-installation bootstrapping (`talos_machine_bootstrap`) and health probes target static HostOnly addresses. Resource creation timeouts accommodate disk installation reboots and non-bootstrap etcd cluster joins up to `constants.EtcdJoinTimeout` (30 minutes in Talos v1.13.8), while health check deadlines account for container image retrieval required for CNI-dependent kubelet readiness.

### Item C. Guest Topology

Node roles, network interface ordering, and boot media configuration define the topology contract shared between `lb-interface-planner` and `hypervisor-kvm-talos`.

1. Control Plane Membership. The cluster provisions a 3-node topology where all nodes act as control plane members to satisfy etcd quorum requirements for combined control plane and data plane execution. The lowest lexicographically sorted node key designates the etcd bootstrap target. Network creation is omitted (`create_networks = false`), deferring interface lifecycle management to `foundation-libvirt-resources`.
2. Control Plane Endpoint. The `cluster_endpoint` local MUST resolve to the catalog VIP (`local.svc_net.vip`) rather than to any individual node address. Talos machine configuration slices away the index 0 NAT interface and assigns the VIP to the first remaining entry through the `vip` block, which is the index 1 HostOnly interface. Talos leader election then moves the address between control plane members. A node failure therefore leaves the endpoint reachable without a Terraform apply.
3. Interface Order. Interfaces generated by `lb-interface-planner` follow a strict structural order.
    1. Index 0 (NAT interface): Configured via DHCP for early maintenance-mode provisioning (`talos_machine_configuration_apply`).
    2. Index 1 (HostOnly interface): Binds the static host IP address, the Kubernetes API control endpoint, and the Talos-managed control plane VIP.
    3. Index 2+ (Service segments): Assigns segment-specific static IPs calculated from `ip_suffix`.

    The `interface_planner` consumes `var.talos_iso_path` via the required `base_image_path` attribute, preserving shared MAC address and interface mapping logic with legacy `cloud-init` workflows.

4. Lease Acquisition Gate. The `wait_for_ip` block MUST apply to the index 0 NAT interface alone, with a 300 second timeout against the DHCP lease source. Domain creation therefore completes only after the maintenance-mode address becomes reachable, which is the address `talos_machine_configuration_apply` targets. Interfaces at index 1 and above carry static addresses, which never depend on a lease.
5. Disk and Boot Media. Operating system volumes deploy as empty `raw` disks that Talos partitions dynamically upon receiving configuration, bypassing `cloud-init`. Item D states the reason the format is `raw` rather than `qcow2`. Initial boot falls through from empty disk `vda` to the attached read-only ISO installer, while `talos.halt_if_installed` prevents secondary installations on subsequent reboots. To prevent persistent state drift in Terraform, `libvirt_domain.devices` changes are ignored post-creation, and network interface queries reference domain UUIDs rather than transient numeric runtime IDs. A subsequent topology change to `node_config` falls under the same ignore rule and requires `terraform apply -replace` against the affected node.

### Item D. Consensus Storage and Scheduling Stability

The disk format decision recorded in commit `591b1ae` propagates into scheduling and timeout constraints. Each requirement below traces back to the fsync sensitivity of etcd.

1. Copy-on-Write Exclusion. The `backing_store` attribute of `libvirt_volume` implements Copy-on-Write by layering a thin overlay above a shared base image, and the attribute accepts `qcow2` alone. Guests running a consensus protocol MUST declare `os_disk_format = "raw"`, because the Copy-on-Write layer introduces metadata write amplification and latency variance on the fsync path that etcd and Vault Raft interpret as storage failure. The service catalog assigns `raw` to `cilium` and `vault`, and assigns `qcow2` to `spire-parent`, `harbor-origin`, and `keycloak`, which never run a consensus protocol and therefore retain thin provisioning together with snapshot capability.
2. Raw Volume Population. A `raw` volume forfeits the base image overlay and materializes empty at the declared capacity. Guests other than Talos require an Ansible role to populate the volume through `qemu-img convert` before first boot, and `start_domains` gates domain startup until that population completes. Talos never requires a population step, because Talos partitions and installs onto an unformatted volume after receiving machine configuration.
3. CPU Pinning. Module `hypervisor-kvm-talos` MUST pin every guest vCPU to a dedicated physical core. The `talos_core_base` local subtracts the total vCPU count of the cluster from `data.libvirt_node_info.host.cpu_cores_total`, placing the allocation at the highest core indices. The `talos_node_core_offset` local then assigns each node a contiguous non-overlapping range by accumulating the vCPU counts of preceding nodes in sorted key order, and `cpu_tune.vcpu_pin` binds vCPU `i` of a node to physical core `offset + i`. Unpinned domains concentrate toward low-numbered cores under the default Linux scheduler, and the resulting contention produces the scheduling jitter that etcd reports as peer timeouts.
4. Etcd Timeout Widening. The `cluster.etcd.extraArgs` block MUST raise `election-timeout` to 2500 milliseconds and `heartbeat-interval` to 250 milliseconds above the Talos baseline. Pinning reduces the jitter source, and the widened timeouts raise tolerance for the residual jitter that a shared hypervisor cannot eliminate.
5. Reboot Apply Mode. Resource `talos_machine_configuration_apply` MUST declare `apply_mode = "reboot"`. An in-place reconfiguration cannot reconcile an etcd learner that already holds inconsistent in-memory state, and a full node restart discards that state.

## Section 2. Provision Cilium Layer

### Item A. Control Plane Access

Binds Kubernetes API clients strictly to credentials exported by `platform-cilium-frontend`, isolating Talos OS credentials from Kubernetes object provisioning.

1. Remote State Source: `terraform_remote_state.cilium_frontend` reads `kubeconfig_raw` and `infrastructure_map` directly from `platform-cilium-frontend` state, bypassing Vault.
2. Credential Partitioning: Local `api_server_connection` decodes `kubeconfig_raw` into `host`, `ca_cert`, `client_certificate`, and `client_key`. Unused Talos `client_configuration` isolates OS-level `apid` credentials from Kubernetes control-plane credentials.
3. Provider Binding: Provider `hashicorp/kubernetes` serves both typed resources (`kubernetes_namespace_v1`, `kubernetes_service_v1`, `kubernetes_endpoints_v1`) and untyped Cilium custom resources through `kubernetes_manifest`. Provider `gavinbunney/kubectl` is removed, and the `manifest` attribute accepts a native HCL object where `kubectl_manifest` required a `yamlencode` string.
4. Vault Authentication: The `vault` provider MUST authenticate through the SPIRE JWT backend rather than through an AppRole credential pair. The `data.external.spire_jwt` block invokes the per-cluster wrapper `spire-fetch-<cluster_name>` deployed by Ansible role `utils_terraform_operator_identity`, and the returned JWT-SVID authenticates against `auth/spire-oidc-jwt/login` under the role named by `local.cilium_cluster_name`. The `ca_cert_file` attribute reads output `bastion_vault_listener_ca_cert_path` instead of a hardcoded relative path.

### Item B. Apply-Time Health Gate

Kubernetes object creation MUST NOT proceed against a control plane whose quorum is still converging.

1. Ephemeral Health Probe: The `ephemeral "talos_cluster_health" "this"` block validates every control plane node at apply time, with a 10 minute timeout. Client credentials come from `ephemeral.vault_kv_secret_v2.cilium_frontend`, keeping the Talos CA certificate, client certificate, and client key out of Terraform state.
2. Dependency Edges: Resources `kubernetes_namespace_v1.platform_lb`, `kubernetes_manifest.lb_ip_pool`, and `kubernetes_manifest.l2_announcement_policy` MUST each declare `depends_on` against the health probe. Concurrent disk activity from sibling layers applying against the same hypervisor destabilizes etcd consensus, and Section 1 Item D records the storage decision that produces that sensitivity. The probe converts a transient quorum loss into an explicit apply failure rather than an opaque Kubernetes API error.

### Item C. Resource Ownership

Defines cluster-scoped Cilium resources and namespaced Services per ownership boundaries in ADR `20260813_1630-clb-migration-to-talos-cilium.md`.

1. Cluster-Scoped Custom Resources: Provisions `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy` (`meta-platform-catalog`). Both match `spec.serviceSelector.matchLabels` (`platform.io/lb-managed=cilium-frontend`), isolating managed allocations from external workloads.
2. Project-Scoped Service Objects: Consuming projects own respective `kubernetes_service` and `kubernetes_endpoints` resources. This layer generates those objects for `meta-platform` catalog entries, as `meta-platform` acts as the consuming project for bare-metal services.
3. Namespace Isolation: Encapsulates generated objects within namespace `platform-lb`. Output `fronted_service_vips` exposes allocated VIPs keyed by catalog segment.

### Item D. Catalog Fronting

Local `fronted_segments` maps `infrastructure_map` entries to selector-less `LoadBalancer` Services backed by catalog bare-metal guest IP endpoints.

1. Segment Exclusion: Omits keys matching `global_topology_identity["cilium"]["frontend"].cluster_name` and `global_topology_identity["central-lb"]["frontend"].cluster_name` to eliminate circular routing and self-referential load balancing.
2. Selector-less Service Pair: `kubernetes_service_v1.catalog` sets `type = LoadBalancer` without pod selectors, linking to a matching `kubernetes_endpoints_v1.catalog` object. Endpoint target addresses iterate over `backend_servers`; Service ports bind `frontend_port` and forward to `backend_port`.
3. VIP Allocation: Annotation `io.cilium/lb-ipam-ips` requests `lb_config.vip` per Service, with pool `spec.blocks` assigning corresponding `/32` CIDR prefixes. Field `spec.loadBalancerIP` remains unset per Kubernetes v1.24 deprecation. `CiliumL2AnnouncementPolicy` sets `loadBalancerIPs = true` to enable Layer 2 VIP advertisement.

## Section 3. References

1. Architecture decision record for this migration, stored at `documentation/architecture-decision-record/20260813_1630-clb-migration-to-talos-cilium.md`.
2. Sidero Labs. (2026). _Deploy Cilium CNI_. Retrieved from [https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
3. Cilium Authors. (2026). _Kubernetes Without kube-proxy_. Retrieved from [https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
4. Cilium Authors. (2026). _LoadBalancer IP Address Management (LB IPAM)_. Retrieved from [https://docs.cilium.io/en/stable/network/lb-ipam/](https://docs.cilium.io/en/stable/network/lb-ipam/)
5. Sidero Labs. (2026). _Talos Provider_. Terraform Registry. Retrieved from [https://registry.terraform.io/providers/siderolabs/talos/latest](https://registry.terraform.io/providers/siderolabs/talos/latest)
