# SPIRE and Vault Workload Identity Federation

This specification states the coordination contract between the SPIRE trust domain rooted at `platform-spire-parent` and the Bastion Vault instance managed by `foundation-vault-bastion`. Section 1 through Section 3 state the overall Parent and Child SPIRE topology, the Bastion and Downstream Vault trust chain, the design rationale behind that architecture, and the tradeoffs accepted in reaching that architecture. Section 4 through Section 10 state the implementation-level contract already realized in Terraform and Ansible. Scope covers the OIDC Discovery Provider deployment, the `vault-spiffe-workload-identity-federation` module, and the `utils_vault_agent` and `utils_spire_workload_entry` Ansible roles consumed by `platform-harbor-origin-frontend`. Service-specific identity and PKI role decisions belong to the consuming layer's own configuration, rather than to the present specification. Architectural rationale for the broader SPIFFE/SPIRE and Vault convergence resides in `planning/architecture_meta-platform.md` Section 9.

## Section 1. Overall Architecture and Trust Chain Topology

### Item A. Zero-Key Distribution Motivation

1. A zero-key trust model authenticates a workload through runtime attestation and issues a short-lived credential, eliminating a static secret that requires pre-generation, distribution, and rotation.
2. The AppRole authentication model requires a static `secret_id` credential that exists throughout the full generation-to-consumption lifecycle.
3. A trusted-orchestrator pattern secures the delivery path for that credential without removing the credential.
4. SPIRE issues a short-lived SPIFFE Verifiable Identity Document (SVID) after runtime attestation, removing the pre-generation and rotation requirement that the AppRole `secret_id` model carries.
5. Vault's native `auth/spiffe` method requires a Vault Enterprise license, and Bastion Vault runs the Community edition through the public `docker.io/hashicorp/vault:2.0` image, an edition lacking that method.
6. SPIRE's own `spire-oidc-discovery-provider` component publishes JWT signing keys as an OIDC discovery and JWKS endpoint, and Vault's existing `auth/jwt` method validates a JWT-SVID against that endpoint.

### Item B. Nested Parent and Child Topology within One Trust Domain

1. SPIRE Server deploys in two tiers under one trust domain, following a Nested topology: SPIRE Parent runs as a bare-metal virtual machine, and SPIRE Child runs on Talos through the `spire-nested` Helm chart.
2. SPIRE Parent serves the operator workstation, whose identities reach the Bastion Vault. SPIRE Child serves every downstream workload, which comprises the pods of the Cilium-fronted Kubernetes cluster, the rootless Podman workloads of the Keycloak and Harbor Origin virtual machines, and the operator identities which reach the Downstream Vault.
3. SPIRE Child obtains an Intermediate CA from SPIRE Parent through the `upstreamauthority/spire` plugin, using a SPIRE Agent colocated with SPIRE Child that authenticates against SPIRE Parent through the Workload API.
4. A single SPIRE Server instance accepts exactly one `UpstreamAuthority` configuration, and SPIRE Child MUST NOT configure `UpstreamAuthority "vault"` alongside `UpstreamAuthority "spire"`.
5. Nested topology chains multiple SPIRE Server instances within a single trust domain, distinct from federation, which exchanges trust bundles across separate trust domains.

### Item C. The Four-Tier PKI Hierarchy: Root, Intermediate, Issuer, and Leaf

1. Bastion Vault's `pki-root` mount holds a self-signed Root CA, Tier 1 of the hierarchy, and signs exclusively the `pki-intermediate` mount.
2. Bastion Vault's `pki-intermediate` mount holds the Bootstrap Issuing Intermediate CA, Tier 2 of the hierarchy, signed by `pki-root`.
3. A dedicated Issuer CA, Tier 3 of the hierarchy, signed by `pki-intermediate`, precedes a consumer's own leaf certificates, Tier 4, for every consumer requiring an independent signing authority.
4. Module `vault-pki-setup`, invoked by layer `security-vault-downstream-pki`, realizes the Tier 3 role for Downstream Vault. Downstream Vault generates the CSR and keeps the private key, Bastion Vault's `pki-intermediate` mount signs the CSR through `root/sign-intermediate`, and the signed certificate returns to Downstream Vault. The chain is `pki-root`, `pki-intermediate`, the Downstream Issuing Intermediate, and leaf.
5. SPIRE Parent's own Intermediate CA realizes the same Tier 3 role for the SPIFFE workload identity hierarchy, signed directly by `pki-intermediate` through SPIRE's built-in `upstreamauthority/vault` plugin.
6. Downstream Vault's Issuing Intermediate and SPIRE Parent's own Intermediate CA stand as sibling Tier 3 branches under the shared `pki-intermediate` mount since Downstream Vault plays no role in signing SPIRE Parent's Intermediate CA.
7. Resource `pki_root` carries `prevent_destroy = true`, and every downstream Tier 3 and Tier 4 certificate inherits that protection through the shared `pki-intermediate` dependency.
8. SPIRE Parent's own Intermediate CA additionally signs SPIRE Child's Intermediate CA on the SPIRE branch, and SPIRE Child signs a workload's leaf SVID, extending that branch to five tiers for a Child-attested workload.

### Item D. Bootstrap Leaf Issuance Bypasses the Issuer Tier

1. Layer `security-vault-downstream-pki` requires an authenticated connection to Downstream Vault, and Downstream Vault becomes reachable only after Cilium, HAProxy, and SPIRE Child complete in the platform deployment order.
2. The Tier 3 Issuing Intermediate carries no issued certificate until that layer applies.
3. The listener certificates of Downstream Vault, SPIRE Parent, and HAProxy issue directly from Bastion Vault's Tier 2 `pki-intermediate` mount. The arrangement is permanent since these services do not follow the rebuild lifecycle of Downstream Vault.
4. Each platform layer creates the Bastion PKI role of its own service, named after the `cluster_name`, and issues the bootstrap listener certificate through that role: `vault_pki_secret_backend_role.vault_listener` in `platform-vault-downstream-frontend`, `vault_pki_secret_backend_role.leaf` in `platform-spire-parent`, and `vault_pki_secret_backend_role.stats` in `platform-haproxy-frontend`.
5. Module `vault-spiffe-workload-identity-federation`, invoked by layer `provision-spire-parent` for the operator identities, receives argument `pki_mount_path` set to the `pki-intermediate` mount.
6. Keycloak, Harbor Origin, and Cilium start after Downstream Vault and take their listener certificates from the Downstream Issuing Intermediate. The layer `security-vault-downstream-pki` declares the PKI role of each service, and the layers `platform-keycloak-frontend` and `platform-harbor-origin-frontend` issue the bootstrap leaf through that role.

### Item E. Per-Issuer JWT Federation Boundary

1. The `upstreamauthority/vault` plugin does not support the `PublishJWTKey` RPC, a limitation that would normally block global JWT-SVID interoperability across a Nested topology.
2. Global JWT interoperability is not required across the Nested SPIRE topology since JWT-SVID authentication follows a one-issuer-one-mount convention already established for `gitlab-saas-ci-job-jwt-provider`.
3. SPIRE Parent's workload authentication mounts on the `auth/jwt` backend of the Bastion Vault, fronted by SPIRE Parent's own `spire-oidc-discovery-provider` instance. The Bastion Vault trusts only that mount.
4. SPIRE Child's workload authentication mounts on an independent `auth/jwt` backend of the Downstream Vault, fronted by SPIRE Child's own OIDC Discovery Provider instance, requiring no JWT key relay from SPIRE Parent. The Downstream Vault trusts that mount for every tenant and for the operator role.
5. Layer `security-vault-downstream-tenants` retains a legacy Parent mount and the role `operator_parent` on the Downstream Vault until every downstream consumer logs in through SPIRE Child. Removing that mount is the last step of the migration.
6. X.509-SVID authentication follows the PKI certificate chain established in Item C and carries no dependency on the `PublishJWTKey` RPC.

### Item F. Trust Chain Topology Diagram

```mermaid
flowchart TD
    subgraph BASTION ["Bastion Vault: Tier 1 Root, Tier 2 Intermediate"]
        ROOT["pki-root: Root CA\n(prevent_destroy)"]
        INTER["pki-intermediate: Bootstrap Issuing Intermediate"]
    end

    subgraph PARENT ["SPIRE Parent: Tier 3 Issuer, Bare Metal"]
        PARENT_CA["SPIRE Parent Intermediate CA\n(upstreamauthority/vault)"]
        PARENT_OIDC["spire-oidc-discovery-provider"]
        PARENT_SVID["Operator Workstation Leaf SVID: Tier 4"]
    end

    subgraph CHILD ["SPIRE Child: Talos, Nested, Pending Deployment"]
        CHILD_CA["SPIRE Child Intermediate CA: Tier 4\n(upstreamauthority/spire)"]
        CHILD_OIDC["OIDC Discovery Provider"]
        CHILD_SVID["Cluster Workload Leaf SVID: Tier 5"]
    end

    subgraph PRODVAULT ["Downstream Vault: Tier 3 Issuer, security-vault-downstream-pki Layer, Pending Apply"]
        PROD_ISSUER["Downstream Issuing Intermediate"]
        PROD_LEAF["Keycloak, Harbor Origin, and Cilium Leaf: Tier 4"]
    end

    ROOT --> INTER
    INTER --> PARENT_CA
    INTER --> PROD_ISSUER
    PROD_ISSUER --> PROD_LEAF
    PARENT_CA --> CHILD_CA
    PARENT_CA --> PARENT_SVID
    CHILD_CA --> CHILD_SVID
    PARENT_CA --> PARENT_OIDC
    CHILD_CA --> CHILD_OIDC
    PARENT_OIDC -.->|JWT-SVID| BASTION_JWT["Bastion Vault: auth/jwt, meta-platform-spire-parent-jwt-svid-provider"]
    CHILD_OIDC -.->|JWT-SVID| CHILD_JWT["Downstream Vault: auth/jwt, meta-platform-spire-child-jwt-svid-provider"]
    INTER -.->|Bootstrap Direct Leaf, Item D| BOOTSTRAP_LEAF["Downstream Vault, SPIRE OIDC, and HAProxy Listener Certs"]
```

## Section 2. Design Rationale

### Item A. Bastion `pki-intermediate` Precedes Downstream Vault in Sequencing

1. SPIFFE/SPIRE deployment is prioritized ahead of the Downstream Vault provisioning chain.
2. Signing SPIRE Parent's Intermediate CA against Downstream Vault would require Downstream Vault's own PKI to already be available, and Downstream Vault's availability depends on the Harbor bootstrapper and Cilium completing first in the platform deployment order.
3. Signing against Bastion Vault's `pki-intermediate` mount removes that ordering dependency since Bastion Vault MUST already be available before any Terraform apply operation across the repository.

### Item B. `join_token` Node Attestor Selection

1. The bare-metal environment provides no cloud instance identity document and no established TPM provisioning process, excluding the `aws_iid`, `gcp_iit`, and `tpm_devid` node attestor plugins.
2. Host count remains small and fixed rather than dynamically scaled, and `join_token` node attestation carries the lowest operational cost at that scale.
3. `spire-server token generate` produces a single-use token consumed once during initial attestation, and a SPIRE Agent completes subsequent identity renewal using the credential obtained from that attestation, without reusing the original token.

### Item C. AppRole for the `upstreamauthority/vault` Bootstrap Exception

1. SPIRE Server holds no SVID during a first Intermediate CA signing request, excluding SVID-based authentication for that request.
2. The `upstreamauthority/vault` plugin supports AppRole, Token, and TLS client certificate authentication for that bootstrap request.
3. TLS client certificate authentication is excluded since issuance of that certificate would itself require prior authentication against `pki-intermediate`, the mount SPIRE seeks to reach through the bootstrap request under evaluation.
4. Token authentication carries a coarser permission scope than AppRole.
5. AppRole authentication is selected, and layer `platform-spire-parent` creates the AppRole and its policy under the name `<cluster_name>-upstream-authority` without introducing a new credential type.

### Item D. `docker` Workload Attestor and Rootless Podman Alignment

1. The `docker` WorkloadAttestor plugin natively supports rootless Podman, detecting a workload's cgroup path and selecting the corresponding per-UID Podman socket automatically upon matching a `/user-<uid>.slice/` pattern.
2. Both `meta-platform` and `on-premise-agent` already run workloads under rootless Podman, and the `docker` WorkloadAttestor plugin requires no change to that execution model.
3. SPIRE Child, once deployed on Talos, uses the Helm chart's default `k8s_psat` node attestor and `k8s` workload attestor, an attestor pairing independent of SPIRE Parent's `docker` attestor selection.

## Section 3. Accepted Tradeoffs

### Item A. Automated Token Generation Removes a Manual Approval Boundary

1. Role `utils_spire_agent` generates and consumes a `join_token` within a single automation run, removing the manual approval boundary that would otherwise separate identity generation from identity consumption.
2. Accepting that removal trades a smaller manual-approval control for a lower operational cost, given a small and Terraform-version-controlled consumer host list.

### Item B. Token Regeneration Invalidates Existing Workload Entries

1. The `join_token` node attestor produces no node selector, and the resulting Agent SPIFFE ID embeds the token value directly as `spiffe://<trust_domain>/spire/agent/join_token/<token>`.
2. Since no node-alias mechanism exists without a node selector, a workload registration entry's `parentID` argument references that token-embedded Agent ID directly.
3. Regenerating a `join_token` produces a new Agent identity, and every workload entry registered under the previous Agent ID becomes invalid, requiring individual re-registration rather than a single token refresh.

### Item C. The Bootstrap AppRole Remains a Permanent Static Trust Root

1. SPIFFE/SPIRE removes the static-credential requirement for a workload capable of runtime attestation.
2. The `upstreamauthority/vault` plugin's own bootstrap authentication in Section 2 Item C falls outside that capability since SPIRE Server cannot attest itself before holding a CA.
3. The bootstrap AppRole is accepted as a permanent, deliberately retained trust root rather than an incomplete migration item.
4. Risk reduction for that path proceeds through narrowing the AppRole's permission scope and shortening the AppRole's credential lifetime, rather than through replacing AppRole with SPIFFE authentication.

### Item D. Single Bastion Root Creates a Shared Failure Domain

1. A full rebuild of Bastion Vault that discards Raft storage forces re-signing of SPIRE's Intermediate CA since the shared `pki-root` trust anchor would no longer exist.
2. That failure mode already exists in the pre-SPIRE PKI design, affecting Downstream Vault's own intermediate certificate under the same condition.
3. SPIRE's adoption of `pki-intermediate` introduces no new instance of that risk.

## Section 4. Trust Chain Establishment at the Bastion Vault Boundary

### Item A. OIDC Discovery Provider Release Artifact

1. The SPIRE distribution publishes the OIDC Discovery Provider binary in a release archive named `spire-extras`, separate from the primary `spire-<version>` archive containing `spire-server` and `spire-agent`.
2. The `base_baremetal_spire` role MUST download and checksum-verify both archives as independent steps since neither archive supersedes or contains the other.

### Item B. OIDC Discovery Provider Listener Binding

1. The OIDC Discovery Provider listener domain MUST equal `spire_parent_node_ip`.
2. DNS resolution for the SPIRE trust domain is unavailable during the bootstrapping stage, and a Vault discovery request sends `spire_parent_node_ip` in the HTTP Host header.
3. A listener domain value other than `spire_parent_node_ip` causes the listener's virtual-host check to reject an incoming Vault discovery request with an HTTP 400 response.

### Item C. Bastion Vault JWT Auth Backend Provisioning

1. Resource `vault_jwt_auth_backend.spire_oidc` declares `oidc_discovery_url` as `https://<spire_parent_node_ip>:<spire_oidc_port>`.
2. Vault validates `oidc_discovery_url` through an active HTTP fetch at resource creation.
3. Resource `vault_jwt_auth_backend.spire_oidc` references no attribute of module `platform_spire_parent`, and the Terraform graph infers no implicit dependency ordering from an attribute reference alone.
4. An explicit `depends_on = [module.platform_spire_parent]` argument enforces execution after module `platform_spire_parent` completion since the discovery fetch in Item C.2 requires an already-running OIDC Discovery Provider listener.
5. Argument `oidc_discovery_ca_pem` requires exactly one PEM string since the underlying provider schema declares a scalar `string` type rather than a list type.

### Item D. Tenant ACL Scope

1. Bastion Vault grants tenant `meta-platform` one ACL policy, `meta-platform-terraform-operator`, which the tenant registry of `parent-group-governance` generates. The rules fall into the categories KV, auth mount, auth role, policy, PKI, and cross-tenant grants.
2. The KV category scopes secret data, metadata, delete, and destroy paths to the `meta-platform` namespace of the `secret` mount.
3. The auth mount category scopes mount management to `sys/auth/meta-platform-*`, `sys/mounts/auth/meta-platform-*`, and `auth/meta-platform-*`, so mount `meta-platform-spire-parent-jwt-svid-provider` and its roles fall within the scope.
4. The auth role category scopes AppRole and JWT role management to the `meta-platform-` prefix.
5. The policy category scopes ACL policy management to `sys/policies/acl/meta-platform-*`.
6. The PKI category grants read on the `pki-intermediate` mount, role management under `roles/meta-platform-*`, and issuance under `issue/meta-platform-*`.
7. A new mount, role, or policy that carries the `meta-platform-` prefix requires no ACL change.

### Item E. Cross-Tenant Grants

1. The tenant policy grants read on `secret/data/parent-group-governance/terraform/state-backend`, which holds the credential of the Terraform state backend.
2. The tenant policy grants read on `secret/data/parent-group-governance/github/publication`, which the project governance layer requires.
3. The tenant policy grants create and update on `pki-intermediate/root/sign-intermediate`, which Downstream Vault needs to have its Issuing Intermediate signed.
4. The SPIRE upstream authority AppRole holds a separate policy which grants create and update on that same signing path only.
5. The operator policy of the Downstream Vault, which layer `provision-spire-parent` generates, grants create and update on that same signing path, and no other operator policy holds the grant. Layer `security-vault-downstream-pki` signs through the JWT-SVID of that operator instead of the tenant AppRole.
6. Only the layers `platform-spire-parent` and `security-vault-bastion-credentials` keep the tenant AppRole, because both run before SPIRE Parent exists.
7. The registry of `parent-group-governance` records each cross-tenant grant together with its reason.

## Section 5. Per-Consumer Role Provisioning

### Item A. Module Contract for `vault-spiffe-workload-identity-federation`

1. Variable `spiffe_id` binds to argument `bound_subject` on resource `vault_jwt_auth_backend_role.this`, constraining JWT-SVID authentication to a single exact SPIFFE ID.
2. Argument `bound_audiences` is a required argument for `role_type = "jwt"` and defaults to `["vault"]`, matching the `jwt_audience` value that `spiffe-helper` requests from the SPIRE Workload API.
3. Argument `user_claim = "sub"` directs Vault to read the authenticating identity from the JWT-SVID subject claim, the field carrying the SPIFFE ID string.

### Item B. Policy Naming

1. Resource `vault_policy.this` names the policy after the role, so the policy name equals the identity string of the workload.
2. The tenant ACL allows policy management only under `sys/policies/acl/meta-platform-*`, and a policy name outside that prefix causes Vault to reject the write with an HTTP 403 response.
3. The former `jwt-policy-` prefix is retired.

## Section 6. Workload Attestation and Containerization Constraint

### Item A. `docker` Workload Attestor Scope

1. The `docker` WorkloadAttestor plugin attests exclusively processes running inside a Docker or Podman container, confirmed through a failed `spire-agent api fetch jwt` invocation against a bare host process.
2. A workload requiring JWT-SVID issuance MUST run inside a container carrying a label matching the selector registered for the workload's own SPIRE entry.

### Item B. `spiffe-helper` Containerization at Packer Build Time

1. Role `base_docker_spiffe_helper` builds a container image for `spiffe-helper` at Packer build time, appended to the `base-docker-harbor` build immediately after role `base_docker`.
2. The container image builds from an empty `scratch` base layer since the `spiffe-helper` binary links statically without a libc runtime dependency.
3. A running `spiffe-helper` container carries label `spiffe-workload` set to `spire_cluster_name`, matching the selector value registered by role `utils_spire_workload_entry`.

## Section 7. Vault Agent Certificate Deployment

### Item A. JWT Auto-Auth Method

1. Vault Agent's `auto_auth` stanza uses method `jwt`, reading the JWT-SVID file that `spiffe-helper` writes to `utils_vault_agent_jwt_dir`.
2. Argument `remove_jwt_after_reading` is set to `false`, departing from the HashiCorp default of `true` since `spiffe-helper` rewrites the JWT-SVID file on a fixed rotation schedule rather than on a per-read basis.

### Item B. Listener Certificate Authority Separation

1. The certificate template deployed to `utils_vault_agent_cert_files` appends the intermediate CA decoded from `vault_intermediate_ca_b64`.
2. Vault Agent's own HTTPS listener certificate MUST source a trusted CA from `utils_vault_agent_vault_listener_ca_cert_b64`, a variable distinct from `vault_intermediate_ca_b64`.
3. The issuing CA record for the `pki-intermediate` chain remains self-signed pending a rotation fix, and reusing the `pki-intermediate` issuing CA record as the listener CA would couple an unrelated rotation state to Vault Agent's own connectivity.

### Item C. Script-Based Certificate Deployment

1. Template `vault-agent.hcl.j2` renders a single executable shell script for certificate deployment, invoked through the `command` argument on the `template` stanza.
2. A single-script design eliminates a JSON-parsing dependency.
3. A single-script design eliminates a certificate-and-key mismatch that a template-per-file design would risk under partial write failure.

## Section 8. Workload Entry Registration

### Item A. Agent Parent ID Resolution

1. Role `utils_spire_workload_entry` reads `join_token` from Bastion Vault as the lookup key for `inventory_hostname`'s Agent SPIFFE ID. The token lives at the join-token leaf below the SPIRE server which issued the token, `<project>/spire/parent/join-token/<cluster>/<host>` or `<project>/spire/child/join-token/<cluster>/<host>`.
2. A persisted Vault record allows a subsequent playbook run to resolve the same parent ID since Ansible facts from the initial node attestation do not survive across separate playbook invocations.

### Item B. Idempotent Entry Creation

1. Task `spire-server entry show` MUST precede task `spire-server entry create` within Block B.
2. Task `spire-server entry create` executes only when the preceding `entry show` query returns zero existing entries for the target SPIFFE ID.

## Section 9. Harbor Origin Consumption Ordering

### Item A. Role Sequencing in `platform_harbor_origin`

1. Role 83 (`utils_spire_agent`) and Role 84 (`utils_spire_workload_entry`) execute before Role 82 (`utils_vault_agent`) since certificate issuance in Role 82 depends on an SPIFFE ID already registered as a SPIRE workload entry.
2. Role 82 executes only when `vault_auth_path` and `vault_agent_auth_role_name` are defined. Both variables come from the tenant login of the Downstream Vault, and the auth path is the mount of SPIRE Child.
3. Role 83 and Role 84 attest the Harbor Origin agent to SPIRE Child. Variable `vault_agent_jwt_audience` carries the audience which the Child mount requires, the cluster name of the Downstream Vault.

## Section 10. Local Terraform Operator Identity

### Item A. Derived Names

1. Layer `provision-spire-parent` derives the operator identity string `<owner>-terraform-operator-<service>-<component>` for each consumer service, and that string names the JWT role and its policy.
2. The SPIFFE ID path of the operator is `/<owner>/terraform-operator/<service>/<component>`.
3. The workload of the consumer uses a role and policy named after its `cluster_name`, and the SPIFFE ID path `/<project_code>/<service>/<component>`.
4. The layer exports the derived role name and wrapper name through output `terraform_operator`, which every layer that reaches the Bastion Vault reads.

### Item B. Host Provisioning and Verification

1. Playbook `playbook_host_terraform_operator.yaml` provisions the SPIRE Agent of the operator host, the service user and JWT-SVID fetch wrapper of each identity, and then verifies each identity.
2. The verification play logs in to Bastion Vault as the operator user without privilege escalation, and asserts that each login grants the policy named after its identity.
3. The operator supplies the sudo password through environment variable `ANSIBLE_BECOME_PASS`, which the playbook and the Terraform action, a child process, both inherit.
4. Role `utils_spire_agent` removes stale agent identity data when the agent fails its health check, and the caller supplies the Bastion Vault CA file through `bastion_vault_ca_cert_path`.

### Item C. Operator Identity for the Downstream Vault

1. The Downstream Vault trusts SPIRE Child only, and the operator identity which reaches the Downstream Vault therefore comes from SPIRE Child.
2. Layer `provision-spire-child` installs a second SPIRE Agent instance, `child`, on the operator host. The instance has its own unit `spire-agent-child`, its own directories, and its own Workload API socket.
3. The same layer registers each operator identity on SPIRE Child and creates the JWT-SVID fetch wrapper `spire-fetch-<identity>-child`. Output `terraform_operator_downstream` exposes the role name, the wrapper name, and the audience, keyed like output `terraform_operator`.
4. The JWT-SVID of that wrapper carries the cluster name of the Downstream Vault as audience, and the operator role on the Child mount of `security-vault-downstream-tenants` binds that audience and the SPIFFE ID glob `spiffe://<trust domain>/<owner>/terraform-operator/*`.
5. The layers which write to the Downstream Vault read the wrapper name from output `terraform_operator_downstream` and log in through the Child mount. The layers which write to the Bastion Vault keep the Parent wrapper.

## Section 11. SPIRE Child as the Server of Downstream Consumers

### Item A. Agent Endpoint

1. Service `spire-internal-server` of the Child chart is a LoadBalancer service. Cilium LB IPAM assigns the VIP at host offset plus two of the Child segment, and L2 announcement makes the VIP reachable from the virtual machines and the operator host.
2. Layer `provision-spire-child` exports the address and port through output `spire_child_agent_endpoint`, and the platform layers of Keycloak and Harbor Origin pass both to role `utils_spire_agent`.
3. The Child server enables the `join_token` node attestor, and the agents of the virtual machines attest with a token which role `utils_spire_agent` generates on the Child server.

### Item B. Registrar Credential

1. Role `utils_spire_server_command` runs `spire-server` commands. For kind `parent`, the role runs the command on the Parent host over SSH. For kind `child`, the role runs the command through `kubectl exec` in the pod of the Child server.
2. Layer `provision-spire-child` creates ServiceAccount `registrar` with a Role limited to `pods get` and `pods/exec get, create` on pod `spire-internal-server-0`, and stores the resulting kubeconfig in the Bastion Vault at the registrar leaf of the Child.
3. The operator policies of `provision-spire-parent` grant read on the registrar leaf, and the roles never hold the admin kubeconfig of the Child cluster.

### Item C. Vault Agent of the Virtual Machines

1. The tenants of Keycloak and Harbor Origin declare issuer `child` in `security-vault-downstream-tenants`, and the Vault Agent logs in through the Child mount.
2. The workload entries of both services register on SPIRE Child through role `utils_spire_workload_entry` with server kind `child`.
