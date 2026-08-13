# Technical Note: Migration of the Central Load Balancer to a Talos and Cilium Bootstrap Tier

## Final Verdict

1. **Load Balancer Tier Form**: The Central Load Balancer transitions from HAProxy and Keepalived on Ubuntu guest VMs to Cilium running inside a dedicated Talos Linux bootstrap cluster. Operating on Talos eliminates interactive shell and SSH access, satisfying management plane immutability requirements.
2. **Bootstrap Identity Source**: The bastion Vault serves as the identity root for the bootstrap tier. Bootstrap credentials must originate from the bastion Vault or native Talos PKI to ensure the production Vault remains reachable via the load balancer tier. Runtime credentials (e.g., metrics endpoints) migrate to the production Vault via External Secrets Operator and cert-manager once steady-state operation is reached.

3. **Harbor OCI Registry Placement**: The `shared-harbor-bootstrapper-frontend` layer moves earlier in the deployment sequence, positioned after the load balancer tier and before the production Vault. Its PKI and KV credential dependencies shift from the production Vault to the bastion Vault.
4. **Service Discovery Mechanism**: Terraform generates Kubernetes Endpoint objects for baremetal services directly from the `service_catalog` single source of truth. The Kubernetes API acts as the service registry consumed by Cilium. HashiCorp Consul is excluded, as current platform architecture does not warrant an independent service discovery daemon.

5. **Downstream Registration Model**: Consuming projects register their own services by writing Kubernetes API objects to the load balancer cluster under project-scoped credentials. Each consuming project retains its own `service_catalog` within its own repository. The `meta-platform` project performs no re-apply when a downstream project adds a service within an existing network segment.

## Explanation

1. **Context and Problem Statement**

    The existing Central Load Balancer renders `haproxy.cfg`, `keepalived.conf`, and `pbr-rules.sh` from `service_catalog` via Jinja2 templates during Ansible runs. Modifying backend members requires executing full Terraform and Ansible pipelines, tight-coupling membership updates to infrastructure provisioning.

    Architecturally, the load balancer is positioned between the bastion Vault and production Vault. The production Vault relies on a virtual IP exposed by the load balancer, while the load balancer acquires certificates from the bastion Vault. Redesigning this tier must preserve this ordering constraint to maintain cold-start bootstrap capability.

2. **Circular Dependency Introduced by the Combined Decisions**

    Deploying Cilium inside a Talos cluster at the load balancer position while positioning Harbor after this cluster introduces a deployment deadlock. The Cilium Helm chart depends on Harbor, whereas Harbor depends on Cilium for virtual IP reachability at layer 4.

    Talos resolves this via `cluster.inlineManifests`, embedding Kubernetes manifests directly into the machine configuration. Talos applies these manifests during node bootstrap prior to `kubectl` availability. Sidero Labs specifies this pattern for production Cilium deployments alongside `machine.network.cni: none` and disabled `kube-proxy`.

    Container image resolution is handled separately via `machine.registries.mirrors` in the Talos configuration. During initial bootstrap, mirror configurations route to upstream registries, transitioning to Harbor once Harbor becomes operational.

3. **Revised Deployment Sequence**

    | **Order** | **Layer**                             | **Change**                                                    |
    | --------- | ------------------------------------- | ------------------------------------------------------------- |
    | 1         | `foundation-libvirt-resources`        | Unchanged                                                     |
    | 2         | `foundation-vault-bastion`            | Expanded scope to serve the bootstrap tier                    |
    | 3         | Talos load balancer tier              | New layer; replaces `shared-load-balancer-frontend`           |
    | 4         | `shared-harbor-bootstrapper-frontend` | Advanced in sequence; PKI/KV sources shifted to bastion Vault |
    | 5         | `shared-vault-frontend`               | Unchanged                                                     |
    | 6         | `security-vault-approle`              | Unchanged                                                     |
    | 7         | `security-pki`                        | Unchanged                                                     |
    | 8         | `security-credentials`                | Unchanged                                                     |
    | 9         | `shared-keycloak-frontend`            | Unchanged                                                     |
    | 10        | `provision-*` layers                  | Unchanged relative ordering                                   |

    Verification confirms the production Vault has no dependency on the container registry. `shared_vault` and `base_baremetal_vault` roles contain no references to Harbor, container registries, `oci://` URIs, or Helm charts. Advancing Harbor in the sequence introduces no conflicts with production Vault initialization.

    Verification also confirms that Harbor bootstrapper installation requires no external registry. The `base_docker_harbor` role reads an offline installation archive pre-populated at `/opt/harbor-install` by Packer, containing all required container images.

4. **Bootstrap Identity Partitioning**

    Bootstrap and runtime credentials follow distinct lifecycle paths.

    Bootstrap credentials must not depend on the production Vault. Any such dependency prevents cold-start recovery after full site shutdown, as the load balancer tier provides the network route to the production Vault.

    The scope of the bootstrap dependency is minimal. Cilium performs layer 4 forwarding and terminates no TLS session. The Talos cluster generates internal PKI through the `talos_machine_secrets` resource. Consequently, the load balancer tier requires no Vault-issued certificates during initial bootstrap.

    Runtime credentials transition to the production Vault post-bootstrap. Telemetry and monitoring endpoints, formerly secured through `vault_pki_secret_backend_cert.haproxy_stats`, obtain certificates from the production Vault through cert-manager and External Secrets Operator in steady state.

5. **Service Discovery Under Mixed Platform Composition**

    PostgreSQL, etcd, Redis, MinIO, Gitaly, and Praefect remain deployed on baremetal infrastructure across the planned operational timeline. Production Vault and Keycloak migrate to Kubernetes in subsequent phases. The target architecture establishes a permanent hybrid model combining Linux baremetal and Kubernetes distributions.

    Because the Kubernetes API does not serve as the sole service registry, Cilium cannot natively discover external baremetal endpoints.

    Terraform generates Kubernetes Endpoint objects for baremetal services directly from `service_catalog`. Terraform retains single-source-of-truth ownership, while the target resource format transitions from VM-rendered configuration files to Kubernetes API objects, eliminating configuration render-and-reload cycles.

6. **Federated Registration by Downstream Projects**

    Rendering `haproxy.cfg` as a monolithic configuration file prevented concurrent writes due to mutual file overwrites. Kubernetes API objects impose no single-file writing constraints. Each Service object exists as an isolated resource, with RBAC scoping write access per namespace or named resource. Terraform executions from independent repositories create distinct objects without mutating resources owned by other projects. The resulting arrangement implements the federated declaration model defined by Kubernetes Gateway API role separation, leveraging the Kubernetes reconciliation loop for continuous state convergence.

    The `provision-harbor-frontend` layer in `on-premise-gitlab-deployment` provides an existing implementation pattern. The layer retrieves a kubeconfig using `ephemeral "vault_kv_secret_v2"` to populate `api_server_connection` for the Kubernetes provider. The Talos load balancer cluster utilizes the same mechanism with scoped per-project credentials.

    Resource ownership aligns with cluster-scope boundaries. The `meta-platform` project manages cluster-scoped custom resources `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy`. The `spec.serviceSelector` field on the pool restricts address allocation to specific services via label selectors, enabling multi-project isolation. Each consuming project manages its respective `kubernetes_service` and `kubernetes_endpoints` resources, with endpoint IP addresses referencing its baremetal guest VMs.

    Address allocation derives from the consuming project's catalog using `cidr_index` and `ip_suffix`, requested via the `io.cilium/lb-ipam-ips` annotation. Field `spec.loadBalancerIP` was deprecated in Kubernetes v1.24 and MUST NOT be used in new resource definitions.

    Self-service registration boundaries are dictated by the network segment layer. Deploying a service into an existing segment requires no modification within `meta-platform`. Provisioning a new segment requires a libvirt network allocation and an additional interface attachment on each Talos node, constituting a physical topology modification that requires execution within `meta-platform`.

7. **Reusable Assets and Net-New Scope**

    The `reloader`, `external-secrets`, and `platform-trust-engine` Terraform modules operate exclusively on Kubernetes API and Helm abstractions. Variable schemas rely on `api_server_connection`, `vault_config`, `helm_config`, and `harbor_oci_config`, containing no node OS dependencies. These modules re-apply directly to application clusters on Talos without modification. However, they cannot be deployed in the bootstrap tier, as their dependencies resolve to Vault and Harbor, which execute later in the launch sequence.

    Modules including `coredns-config`, `ingress-nginx`, `local-path-provisioner`, `metric-server`, `platform-mtls-certificate`, and `helm-chart-*` follow identical migration semantics. `calico-felix-config` and `tigera-calico` are deprecated by Cilium. `microk8s-ingress` is specific to MicroK8s. `kubelet-csr-approver` requires evaluation, given native Talos kubelet certificate management.

    Net-new requirements comprise a Terraform module that provisions Talos guest VMs on libvirt and assembles the `siderolabs/talos` provider resources. The provider covers the full node and cluster lifecycle through `talos_machine_secrets`, `data.talos_machine_configuration`, `talos_machine_configuration_apply`, `talos_machine`, `talos_cluster`, `data.talos_cluster_health`, and `data.talos_cluster_kubeconfig`, with image definitions supplied by `talos_image_factory_schematic`. Node and cluster operations therefore remain within `terraform plan` and `terraform apply`, and the `talosctl` command line tool is not required for the standard workflow. Existing `base_kubernetes_kubeadm`, `base_kubernetes_microk8s`, `infra_kubeadm`, and `infra_microk8s` roles are obsolete for the load balancer tier, as all four depend on SSH and Ansible.

    The `talos_machine` resource reconciles drift on every refresh by reading the running Talos version and the active machine configuration hash from each node, which places operating system upgrades and configuration changes under the same apply cycle as every other layer.

8. **Disposition of Previously Identified Load Balancer Defects**

    | **Defect**                                  | **Disposition Under New Architecture**                                                                         |
    | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
    | `VG_ALL` sync group blast radius            | Resolved. `CiliumL2AnnouncementPolicy` provides per-service leader election, replacing Keepalived sync groups. |
    | `ip_forward` enabled without FORWARD policy | Persists in modified form. Requires adaptation to Talos and Cilium networking models.                          |
    | Central LB address absent from SSoT         | Persists. Requires mapping into Talos node configurations.                                                     |
    | Positional derivation of VRID and priority  | Persists in modified form. Cilium L2 announcements replace VRRP; deterministic selection remains required.     |
    | Two-node VRRP without arbitration           | Superseded. VRRP is removed; split-brain handling under L2 announcements requires separate evaluation.         |
    | 384 MiB memory allocation                   | Superseded. Talos and Cilium resource footprints require independent benchmarking.                             |

9. **Items Requiring Empirical Verification**

    The N-squared scope-link matrix in `pbr-rules.sh.j2` and asymmetric return traffic paths across libvirt bridges represent primary unverified areas. Talos nodes require multi-interface bindings per service segment, matching current load balancer VM topologies. Whether the Cilium eBPF datapath preserves symmetric return routing across bridges without explicit policy routing requires validation.

    Additionally, `CiliumL2AnnouncementPolicy` behavior across isolated bridge interfaces requires empirical testing prior to final adoption.

    Address assignment during first boot requires validation. The `talos_machine_configuration_apply` resource reaches each Talos node over the network while the node runs in maintenance mode, which presumes the maintenance mode address remains predictable under libvirt DHCP.

## References

1. Sidero Labs. (2026). _Deploy Cilium CNI_. Retrieved from [https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
2. Cilium Authors. (2026). _Kubernetes Without kube-proxy_. Retrieved from [https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
3. Cilium Authors. (2026). _Upgrade Guide_. Retrieved from [https://docs.cilium.io/en/stable/operations/upgrade/](https://docs.cilium.io/en/stable/operations/upgrade/)
4. Cilium Authors. (2026). _LoadBalancer IP Address Management (LB IPAM)_. Retrieved from [https://docs.cilium.io/en/stable/network/lb-ipam/](https://docs.cilium.io/en/stable/network/lb-ipam/)
5. Sidero Labs. (2026). _Talos Provider_. Terraform Registry. Retrieved from [https://registry.terraform.io/providers/siderolabs/talos/latest](https://registry.terraform.io/providers/siderolabs/talos/latest)
