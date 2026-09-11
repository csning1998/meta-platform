# ADR: Migration of the Central Load Balancer to a Talos and Cilium Bootstrap Tier

> [!IMPORTANT]
> The platform architecture partially supersedes this document through `20260911_1145-haproxy-tier-for-non-kubernetes-runtimes.md`. The Service backend SNAT within Cilium continuously rewrites the source IP address to the single `directRoutingDevice` of the node, which remains valid exclusively for in-cluster Pod backends. External bare-metal services including Harbor Origin and SPIRE Parent are exposed by a reinstated HAProxy and Keepalived tier. Selection between the two tiers is governed by the `runtime` attribute in the `service_catalog` schema. The invalidations apply specifically to Item 1 in Section 1, Item C in Section 2, and Item I in Section 2. The remaining specifications in this document, including bootstrap identity partitioning, advancing the deployment sequence of Harbor Origin, and Kubernetes Endpoint generation for Kubernetes-native services, remain in full effect.

## Section 1. Executive Summary and Final Verdict

1. **Load Balancer Tier Form**: The Central Load Balancer transitions from HAProxy and Keepalived on Ubuntu guest virtual machines to Cilium within a dedicated Talos Linux bootstrap cluster exclusively for Kubernetes-native workloads. Operation on Talos Linux eliminates interactive shell and SSH access, which satisfies platform requirements for management-plane immutability. External workloads which execute outside Kubernetes are excluded from this tier and remain fronted by HAProxy.
2. **Bootstrap Identity Source**: The bastion Vault instance serves as the identity root for the bootstrap tier. Bootstrap credentials MUST originate from either the bastion Vault instance or native Talos PKI to guarantee production Vault reachability through the load-balancing tier during cold-start sequences. Runtime credentials migrate to the production Vault instance through External Secrets Operator and cert-manager upon reaching steady-state operations.
3. **Harbor OCI Registry Placement**: The `platform-harbor-origin-frontend` deployment layer moves earlier in the launch order, positioned after the load-balancing tier and prior to the production Vault instance. PKI and KV credential dependencies for Harbor Origin shift from the production Vault instance to the bastion Vault instance.
4. **Service Discovery Mechanism**: Terraform generates Kubernetes Endpoint objects for bare-metal services directly from the `service_catalog` single source of truth. The Kubernetes API functions as the service registry consumed by Cilium. HashiCorp Consul is excluded from the architecture because the platform does not require an independent service discovery daemon.
5. **Downstream Registration Model**: Consuming projects register their services by applying Kubernetes API objects to the load-balancing cluster using project-scoped credentials. Each consuming project maintains an independent `service_catalog` repository. The `meta-platform` project executes no Terraform re-apply when a downstream project provisions a service within an existing network segment.

## Section 2. Technical Rationale and Architectural Design

### Item A. Context and Architectural Constraints

The legacy Central Load Balancer generates `haproxy.cfg`, `keepalived.conf`, and `pbr-rules.sh` from `service_catalog` using Jinja2 templates during Ansible playbook runs. Modifying backend pool members requires full executions of both Terraform and Ansible pipelines, which tightly couples membership state to infrastructure provisioning.

The load-balancing tier resides between the bastion Vault instance and the production Vault instance in the platform dependency hierarchy. The production Vault instance depends on a virtual IP address exposed by the load-balancing tier. The load-balancing tier retrieves TLS certificates from the bastion Vault instance. Redesigning the load-balancing tier MUST preserve this ordering constraint to sustain cold-start bootstrap capability.

### Item B. Circular Dependency Resolution via Machine Configuration

Deploying Cilium inside a Talos cluster at the load-balancing position while placing Harbor after the cluster introduces a deployment deadlock. The Cilium Helm chart depends on Harbor for container image retrieval, while Harbor depends on Cilium for Layer 4 virtual IP reachability.

Talos resolves this conflict through the `cluster.inlineManifests` configuration parameter, which embeds Kubernetes manifests directly into the machine configuration. Talos applies these embedded manifests during node bootstrap prior to the availability of the Kubernetes API server. Sidero Labs specifies this inline pattern for production Cilium deployments alongside `machine.network.cni` set to `none` and disabled `kube-proxy`.

Container image resolution operates through `machine.registries.mirrors` in the Talos configuration. Registry mirror configurations route requests to upstream public registries during initial bootstrap, and subsequently transition to Harbor once Harbor becomes operational.

### Item C. Revised Deployment Sequence

The ordered sequence of platform deployment layers is structured as follows:

| Order | Layer                             | Change                                                            |
| ----- | --------------------------------- | ----------------------------------------------------------------- |
| 1     | `foundation-libvirt-resources`    | Unchanged                                                         |
| 2     | `foundation-vault-bastion`        | Expanded scope to serve the bootstrap tier                        |
| 3     | Talos load balancer tier          | New layer; replaces `platform-haproxy-frontend`                   |
| 4     | `platform-harbor-origin-frontend` | Advanced in sequence; PKI and KV sources shifted to bastion Vault |
| 5     | `platform-vault-frontend`         | Unchanged                                                         |
| 6     | `security-vault-approle`          | Unchanged                                                         |
| 7     | `security-pki`                    | Unchanged                                                         |
| 8     | `security-credentials`            | Unchanged                                                         |
| 9     | `platform-keycloak-frontend`      | Unchanged                                                         |
| 10    | `provision-*` layers              | Unchanged relative ordering                                       |

Verification confirms that the production Vault instance does not maintain dependencies on the container registry. The `platform_vault` and `base_baremetal_vault` Ansible roles do not contain references to Harbor, container registries, `oci://` URIs, or Helm charts. Advancing Harbor Origin in the deployment sequence does not introduce conflicts with production Vault initialization.

Verification also confirms that the Harbor bootstrapper installation does not require an external registry. The `base_docker_harbor` role reads an offline installation archive pre-populated at `/opt/harbor-install` by Packer, which contains all required container images.

### Item D. Bootstrap Identity Partitioning

Bootstrap credentials and runtime credentials follow distinct lifecycle paths.

Bootstrap credentials MUST NOT depend on the production Vault instance. Any dependency on the production Vault instance prevents cold-start recovery after a full site shutdown because the load-balancing tier provides the network route to the production Vault instance.

The scope of the bootstrap credential dependency remains minimal. Cilium executes Layer 4 forwarding and does not terminate TLS sessions. The Talos cluster generates internal PKI assets through the `talos_machine_secrets` resource. Consequently, the load-balancing tier does not require Vault-issued certificates during initial bootstrap.

Runtime credentials transition to the production Vault instance after bootstrap completion. Telemetry and monitoring endpoints obtain certificates from the production Vault instance through cert-manager and External Secrets Operator in steady-state operation.

### Item E. Service Discovery Under Mixed Platform Composition

PostgreSQL, etcd, Redis, MinIO, Gitaly, and Praefect remain deployed on bare-metal infrastructure across the planned operational timeline. Production Vault and Keycloak migrate to Kubernetes in subsequent project phases. The target architecture establishes a permanent hybrid model combining Linux bare metal and Kubernetes distributions.

Since the Kubernetes API does not serve as the sole service registry for the platform, Cilium cannot natively discover external bare-metal endpoints.

Terraform generates Kubernetes Endpoint objects for bare-metal services directly from `service_catalog` definitions. Terraform retains single-source-of-truth ownership over service topology. The target resource format transitions from VM-rendered configuration files to Kubernetes API objects, which eliminates configuration render-and-reload cycles.

### Item F. Federated Registration by Downstream Projects

Rendering `haproxy.cfg` as a monolithic configuration file prevented concurrent writes due to mutual file overwrites. Kubernetes API objects do not impose single-file writing constraints. Each Service object exists as an isolated resource with RBAC scoping write access per namespace or per named resource. Terraform executions from independent repositories create distinct objects without mutating resources owned by other projects.

This arrangement implements the federated declaration model defined by Kubernetes Gateway API role separation, utilizing the Kubernetes reconciliation loop for continuous state convergence.

The `provision-harbor-frontend` layer in `on-premise-gitlab-deployment` demonstrates an established implementation pattern. The layer retrieves a kubeconfig token using an ephemeral `vault_kv_secret_v2` data source to populate `api_server_connection` for the Kubernetes provider. The Talos load-balancing cluster utilizes this same mechanism with scoped per-project credentials.

Resource ownership aligns with Kubernetes cluster-scope boundaries. The `meta-platform` project manages cluster-scoped custom resources `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy`. The `spec.serviceSelector` field on `CiliumLoadBalancerIPPool` restricts address allocation to specific services through label selectors, which provides multi-project isolation. Each consuming project manages its respective `kubernetes_service` and `kubernetes_endpoints` resources, with endpoint IP addresses referencing bare-metal guest virtual machines.

Address allocation derives from the catalog of the consuming project using `cidr_index` and `ip_suffix`, requested through the `io.cilium/lb-ipam-ips` annotation. The `spec.loadBalancerIP` field is deprecated in Kubernetes v1.24 and MUST NOT be used in resource definitions.

Self-service registration boundaries follow network segment layers. Deploying a service into an existing segment requires no modification within `meta-platform`. Provisioning a new segment requires a libvirt network allocation and an additional interface attachment on each Talos node, which constitutes a physical topology modification that MUST be executed within `meta-platform`.

### Item G. Reusable Assets and Net-New Scope

The `reloader`, `external-secrets`, and `platform-trust-engine` Terraform modules operate exclusively on Kubernetes API and Helm abstractions. Variable schemas rely on `api_server_connection`, `vault_config`, `helm_config`, and `harbor_oci_config`, with no node operating system dependencies. These modules apply directly to application clusters on Talos without modification. These modules MUST NOT be deployed in the bootstrap tier because their dependencies resolve to Vault and Harbor, which execute later in the launch sequence.

Modules including `coredns-config`, `ingress-nginx`, `local-path-provisioner`, `metric-server`, `platform-mtls-certificate`, and `helm-chart-*` follow identical migration semantics. Cilium deprecates the `calico-felix-config` and `tigera-calico` modules. The `microk8s-ingress` module remains specific to MicroK8s. The `kubelet-csr-approver` module requires evaluation given native Talos kubelet certificate management.

Net-new requirements comprise a Terraform module which provisions Talos guest virtual machines on libvirt and manages `siderolabs/talos` provider resources. The provider manages the full node and cluster lifecycle through `talos_machine_secrets`, `data.talos_machine_configuration`, `talos_machine_configuration_apply`, `talos_machine`, `talos_cluster`, `data.talos_cluster_health`, and `data.talos_cluster_kubeconfig`, with image definitions supplied by `talos_image_factory_schematic`. Node and cluster operations remain within standard `terraform plan` and `terraform apply` workflows, and the `talosctl` command-line utility is not required for standard operations.

Existing `base_kubernetes_kubeadm`, `base_kubernetes_microk8s`, `infra_kubeadm`, and `infra_microk8s` roles are obsolete for the load-balancing tier because all four roles depend on SSH and Ansible.

The `talos_machine` resource reconciles state drift on every refresh by reading the running Talos version and active machine configuration digest from each node, which integrates operating system upgrades and configuration updates into the standard apply cycle.

### Item H. Disposition of Previously Identified Load Balancer Defects

The disposition of historical load balancer defects under the new architecture is cataloged below:

| Defect                                      | Disposition Under New Architecture                                                                             |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `VG_ALL` sync group blast radius            | Resolved. `CiliumL2AnnouncementPolicy` provides per-service leader election, replacing Keepalived sync groups. |
| `ip_forward` enabled without FORWARD policy | Persists in modified form. Requires adaptation to Talos and Cilium networking models.                          |
| Central LB address absent from SSoT         | Persists. Requires mapping into Talos node configurations.                                                     |
| Positional derivation of VRID and priority  | Persists in modified form. Cilium L2 announcements replace VRRP; deterministic selection remains required.     |
| Two-node VRRP without arbitration           | Superseded. VRRP is removed; split-brain handling under L2 announcements requires separate evaluation.         |
| 384 MiB memory allocation                   | Superseded. Talos and Cilium resource footprints require independent benchmarking.                             |

### Item I. Items Requiring Empirical Verification

The N-squared scope-link matrix in `pbr-rules.sh.j2` and asymmetric return traffic paths across libvirt bridges represent the primary unverified areas. Talos nodes require multi-interface bindings per service segment, matching the existing load-balancer virtual machine topology. Whether the Cilium eBPF datapath preserves symmetric return routing across bridges without explicit policy routing requires empirical validation.

`CiliumL2AnnouncementPolicy` behavior across isolated bridge interfaces requires empirical testing prior to final adoption.

Network address assignment during first boot requires validation. The `talos_machine_configuration_apply` resource reaches each Talos node over the network while the node runs in maintenance mode, which presumes that the maintenance mode address remains predictable under libvirt DHCP.

## Section 3. References

1. Sidero Labs. (2026). _Deploy Cilium CNI_. Retrieved from [https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
2. Cilium Authors. (2026). _Kubernetes Without kube-proxy_. Retrieved from [https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
3. Cilium Authors. (2026). _Upgrade Guide_. Retrieved from [https://docs.cilium.io/en/stable/operations/upgrade/](https://docs.cilium.io/en/stable/operations/upgrade/)
4. Cilium Authors. (2026). _LoadBalancer IP Address Management (LB IPAM)_. Retrieved from [https://docs.cilium.io/en/stable/network/lb-ipam/](https://docs.cilium.io/en/stable/network/lb-ipam/)
5. Sidero Labs. (2026). _Talos Provider_. Terraform Registry. Retrieved from [https://registry.terraform.io/providers/siderolabs/talos/latest](https://registry.terraform.io/providers/siderolabs/talos/latest)
