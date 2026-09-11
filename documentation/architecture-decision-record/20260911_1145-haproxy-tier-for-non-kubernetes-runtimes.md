# ADR: Reinstatement of HAProxy and Keepalived for Non-Kubernetes Runtimes

## Section 1. Executive Summary and Final Verdict

1. **Ownership Partitioning by Runtime**: Cilium exclusively manages in-cluster Kubernetes-native workloads and their Service and CiliumL2AnnouncementPolicy forwarding. Any `service_catalog` component whose `runtime` attribute is not `talos`, `kubeadm`, `microk8s`, or `minikube` is managed end-to-end by a dedicated HAProxy and Keepalived tier. This partitioning is a mechanical function of the existing `runtime` field, rather than a static enumeration of service names. A component transitioning between runtimes shifts its load-balancing tier automatically, with no code modifications required on either tier.
2. **Scope of the HAProxy Tier**: External bare-metal and virtual machine services, including Harbor Origin, SPIRE Parent, and any future non-Kubernetes service, are exposed through the `platform-haproxy-frontend` layer. The architecture provisions one HAProxy tier per platform repository holder, including `meta-platform`, `on-premise-gitlab-deployment`, and `meta-platform-observability`. The HAProxy configuration utilizes `mode tcp` with full TLS passthrough. TLS certificates do not terminate at this tier.
3. **Return-Path Symmetry Architecture**: Outbound connections from HAProxy to a backend do not require policy routing, since each backend segment constitutes a directly connected subnet with no routing ambiguity. The client-to-VIP reply leg requires policy routing, because two or more VIPs on distinct segment interfaces can receive traffic from an identical external client CIDR block which the single main routing table cannot disambiguate by destination address alone. The platform implements this routing through a VIP-scoped source-routing block within the `platform_haproxy` role, which avoids reintroducing the retired `utils_asymmetric_routing` role.
4. **Multi-Interface Provisioning Mechanism**: Multiple network interfaces on HAProxy, consisting of one client-facing interface and one interface per fronted backend segment, are provisioned through the `extra_networks` parameter of the generic `hypervisor-kvm` module. This approach reuses the mechanism established for Bastion Vault guest reachability, which eliminates the requirement for a bespoke multi-NIC Terraform module.

## Section 2. Technical Rationale and Architectural Design

### Item A. Context and Root Cause Analysis

The D2 deployment health check for `platform-harbor-origin-frontend` timed out against the catalog VIP announced by Cilium. Investigation confirmed that Cilium resources, including CiliumL2AnnouncementPolicy, LB-IPAM pools, Services, Endpoints, and BPF load-balancing maps, were programmed correctly. Diagnostic procedures ruled out routing-mode variations (tunnel and native), libvirt network filtering rules, and Talos host firewall configurations.

Packet capture via `tcpdump -e` on the backend network segment isolated the routing failure. While the DNAT destination IP address was rewritten correctly, the SNAT source IP address was rewritten to the single `directRoutingDevice` address of the Talos node. The external backend possesses no network route back to this `directRoutingDevice` network, which prevents reply delivery.

The kube-proxy-replacement datapath in Cilium always rewrites the source address of Service backend traffic to that single direct-routing interface. This behavior is valid exclusively when the backend is an in-cluster Pod on the same node, and fails whenever the backend is an external bare-metal host on a distinct Layer 2 segment.

Cilium upstream Issue `#22429`, which requested per-interface SNAT support, is closed as not planned. Upstream Issue `#39121` and Discussion `#39139` confirm that one direct-routing device per node is an architectural constraint which cannot be resolved through the `bpf.masquerade` configuration.

### Item B. Mechanical Ownership Partitioning by Runtime

To avoid maintaining a hardcoded list of services, the platform partitions load-balancing tiers using the `runtime` attribute declared by each `service_catalog` component.

The `fronted_segments` filter in `provision-cilium-frontend` requires that `contains(kubernetes_native_runtimes, seg.runtime)` evaluates to true. The `fronted_segments` filter in `platform-haproxy-frontend` requires the logical negation of that condition.

A component migrating from `docker` or `baremetal` to `talos` transitions out of HAProxy management and into Cilium management without requiring code changes in either provisioning module.

### Item C. Empirical Verification of Return-Path Symmetry

Outbound traffic from HAProxy to a backend does not require policy routing, since each backend segment provides the sole directly connected route to that destination. Standard kernel destination-based routing resolves the outbound path unambiguously.

The client-to-VIP reply leg presents an asymmetric routing condition. The HAProxy tier in `meta-platform` fronts multiple VIPs across distinct segment interfaces, including Harbor Origin and SPIRE Parent. Both VIP interfaces receive requests from an identical external client CIDR block assigned to the Talos nodes of Cilium.

The Linux main routing table stores only one route per destination prefix. When two VIP interfaces require a route to the same client CIDR block, the main table can bind that destination to only one interface, which causes reply packets for the second VIP to exit through the wrong physical interface.

The platform resolves this routing conflict through a dedicated source-routing table per VIP (`ip rule from <vip> table rt_<segment>`). This table contains only the directly connected subnet of that segment and a default route via the gateway of that segment. This routing configuration resides directly within `platform_haproxy`, scoped exclusively to its fronted VIPs, while `utils_asymmetric_routing` remains retired.

### Item D. Diagnostic Verification Chain on Live Infrastructure

A curl execution from SPIRE Parent (`172.16.126.200`) to the Harbor Origin VIP (`172.16.127.250`) timed out. A simultaneous `tcpdump` capture on the HAProxy segment interface `v_platformharbo` captured zero client packets, recording only backend health-check probes initiated by HAProxy. This packet trace localized the failure to the network path between the client and HAProxy, rather than within HAProxy itself.

An `ip neigh` query on the hypervisor host resolved the VIP to a MAC address which belonged to a residual NIC on `platform-cilium-frontend-node-00` on that same segment, rather than to HAProxy. The runtime exclusion filter in `provision-cilium-frontend` had been updated in code but not applied to the cluster. The `CiliumL2AnnouncementPolicy` resource for Harbor Origin remained active and continued answering ARP requests for the VIP, which preempted ARP responses from Keepalived on HAProxy.

Applying `provision-cilium-frontend` suppressed the conflicting Cilium L2 announcement. A subsequent curl execution established a valid TCP handshake to `172.16.127.250` on port 443 (`Connected to 172.16.127.250 port 443`). The subsequent TLS handshake failure occurred as expected, because the backend virtual machine for Harbor Origin had not been provisioned at the time of this verification test.

### Item E. Multi-Interface Provisioning Architecture

The legacy `lb-interface-planner` and `hypervisor-kvm-lb` modules computed MAC addresses and interface aliases manually because `foundation-libvirt-resources` did not centrally manage `libvirt_network` resources at that time, and `hypervisor-kvm` did not provide multi-interface support. Both architectural prerequisites have changed.

The `foundation-libvirt-resources` layer centrally provisions the `libvirt_network` resource for every service segment. The `hypervisor-kvm` module provides a generic `extra_networks` map (network name to static IP address), which was introduced to support guest network reachability for Bastion Vault. The multi-interface requirements of HAProxy are satisfied entirely through this existing `extra_networks` configuration.

Investigation revealed that interfaces provisioned through `extra_networks` in `hypervisor-kvm` did not declare `systemd-networkd` `set-name` directives. A guest virtual machine equipped with multiple extra interfaces received kernel PCI-slot-ordered names, which conflicted with the stable interface names to which Keepalived and policy routing scripts bind. The `hypervisor-kvm` module resolves this defect generically by generating a deterministic `alias` derived from the network name, which benefits every consumer of the `extra_networks` mechanism.

### Item F. Configuration Alignment Between Node Suffix and Catalog Range

The Host configuration block in `sshclient_host_config` computes its `HostName` attribute from the `ip_range.start_ip` reservation declared in `service_catalog`, independently of the `ip_suffix` value specified in `service_config.nodes`. Existing single-node modules set both attributes to identical values by convention.

The initial `terraform.tfvars.example` file for `platform-haproxy-frontend` assigned discordant values, which created an active virtual machine whose assigned IP address conflicted with its generated SSH configuration alias. The resolution aligned the `ip_suffix` value in `terraform.tfvars.example` directly with the `ip_range.start_ip` reservation in `service_catalog`, which required no modifications to shared modules.

### Item G. Revised Bootstrap Launch Sequence

The platform deployment sequence begins with Bastion Vault, followed by the Harbor bootstrapper virtual machine and offline registry with listener certificates from Bastion PKI. The HAProxy tier deploys next to front the virtual IPs of the Harbor bootstrapper and SPIRE Parent. The production Vault instance deploys following HAProxy, followed by Keycloak.

Cilium deploys on an independent, parallel track which serves exclusively Kubernetes-native workloads. Cilium is no longer a prerequisite for the Harbor Origin VIP or for the production Vault instance, both of which previously depended on Cilium L2 announcements.

In `platform-harbor-origin-frontend`, the `data.terraform_remote_state.cilium_provision` postcondition, which gated the plan on Cilium registering the Harbor Origin VIP, is removed as obsolete under this sequence.

### Item H. Open Architectural Items

Whether Harbor Origin and Keycloak remain fronted by HAProxy following the deployment of the production Vault instance, or transition to an alternative routing architecture, is deferred to the production Vault deployment phase.

Talos registry-mirror authentication against Harbor Origin using robot accounts or alternative mechanisms is not implemented within this repository. The architectural premise that container image pulls do not depend on the OIDC and Keycloak integration of Harbor represents a general property of container registries, rather than an assertion verified against the specific configuration of this codebase.

## Section 3. References

1. Cilium Authors. (2026). _Issue #22429: Support per-interface SNAT for externalTrafficPolicy_. GitHub. Retrieved from [https://github.com/cilium/cilium/issues/22429](https://github.com/cilium/cilium/issues/22429)
2. Cilium Authors. (2026). _Issue #39121: Multiple direct routing devices_. GitHub. Retrieved from [https://github.com/cilium/cilium/issues/39121](https://github.com/cilium/cilium/issues/39121)
3. Cilium Authors. (2026). _Discussion #39139_. GitHub. Retrieved from [https://github.com/cilium/cilium/discussions/39139](https://github.com/cilium/cilium/discussions/39139)
4. Cilium Authors. (2026). _LoadBalancer IP Address Management (LB IPAM)_. Retrieved from [https://docs.cilium.io/en/stable/network/lb-ipam/](https://docs.cilium.io/en/stable/network/lb-ipam/)
