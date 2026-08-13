# Technical Note: Assessment of `role_id` and `secret_id` Exposure Paths

## Final Verdict

1. **AppRole Architecture Retention**: The existing `production_admin` AppRole design correctly reflects the principle of least privilege established during the recent PKI refactoring. Structural modification of the AppRole design is unnecessary.
2. **Rejection of Field Encryption**: Under operational parameters characterized by single-developer workflows, predominantly internal or air-gapped deployments, and public network exposure below 5%, the marginal security gain offered by Vault Transit encryption fails to justify the operational complexity of an additional cryptographic layer. Implementation of Vault Transit encryption is not recommended.

## Explanation

1. **Context and Problem Statement**

    Review feedback on [MR !26](https://gitlab.com/csning1998-lab/meta-platform/-/merge_requests/26) postulated potential credential exposure of `vault_approle_role_id` and `vault_approle_secret_id` into Terraform state via `ansible_extra_vars`. Investigation disproved the premise: the `ansible-runner` module employs Terraform 1.14+ action blocks, through which `extra_vars` values bypass state persistence entirely.

    The true exposure path resides within the `terraform_remote_state` data source cached from upstream `security-vault-approle` outputs. Consequently, any downstream consuming layer referencing the remote state unconditionally persists `role_id` and `secret_id` within the state file of the consuming layer. The persistence behavior occurs independently of `ansible_extra_vars` utilization.

2. **Evaluated Mitigation Strategies**

    Analysis rejected the following candidate solutions:

    | **Strategy**                                         | **Evaluation Outcome** | **Rationale**                                                                                                                                                                                                              |
    | ---------------------------------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
    | **OpenTofu Native State Encryption**                 | Rejected               | OpenTofu currently lacks action block support. Migration to the OpenTofu platform breaks the primary mechanics of the `action` block (e.g. `ansible-runner` module).                                                       |
    | **HashiCorp Terraform Native Encryption**            | Non-existent           | The `terraform { encryption {...} }` block is exclusive to OpenTofu. Comparable functionality in the HashiCorp ecosystem requires paid HCP Terraform or Enterprise tiers.                                                  |
    | **Short-TTL `secret_id` Rotation**                   | Rejected               | Rotation workflows inherently require prior authentication. Provisioning short-lived credentials via secondary long-lived credentials merely shifts the exposure boundary without mitigating the underlying vulnerability. |
    | **Transition to `~/.vault-token` (OIDC User Login)** | Rejected               | Verification identified the target token as a root-level credential possessing broader authorization than `production_admin`. Implementation thereof induces a security regression.                                        |
    | **Vault Transit Field-Level Encryption**             | Conditionally Feasible | Technically viable; however, adoption remains unrecommended based on the threat model evaluation below.                                                                                                                    |

3. **Threat Model Clarification**

    Initial analysis incorrectly posited that internal gateway defenses provided sufficient isolation. Re-evaluation confirms that state storage resides on `gitlab.com`, accessible over the public internet, which represents a boundary distinct from internal network gateways (such as Nutanix or Talos infrastructure).

    Primary threat vectors capable of effecting data compromise comprise compromised GitLab accounts or Personal Access Tokens (PATs), local workstation intrusions, or upstream platform breach events on `gitlab.com`. Internal network defense parameters yield no mitigation against external exposure vectors.
