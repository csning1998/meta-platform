# platform-spire-parent

The layer provisions the SPIRE Parent VM, the AppRole of the upstream authority on `pki-spire`, and the PKI role of the OIDC listener on `pki-platform`.

The layer MUST run inside a tenant session, which `./governance vault tenant-session meta-platform` of `parent-group-governance` opens.

The tenant session exports `VAULT_ADDR`, `VAULT_CACERT`, and `VAULT_TOKEN`, and the `vault` provider of the layer reads the three variables alone.

The layer reads the Bastion facts from `registry/meta-platform/bastion` and `registry/platform/trust`.

The plan stops when the SPIRE trust domain is absent from `spire_trust_domains` of `registry/platform/trust`.

## Section 1. Runbook: recovery after a state loss

A state loss is the removal of the remote state of the layer while the Bastion Vault objects of the layer remain.

The Bastion Vault objects of the layer are the AppRole role `<cluster_name>-upstream-authority` and the PKI role `<cluster_name>` on `pki-platform`.

An apply inside a tenant session overwrites both roles in place, and neither role requires an import.

The secret ID of the upstream authority and the OIDC listener certificate reside on the VM and never in the state.

The play of the layer keeps a secret ID which the Bastion Vault still knows under the current role, and the play issues a new secret ID otherwise.

The play keeps a listener certificate which chains to the current `pki-platform` and stays valid beyond 30 days, and the play issues a new certificate otherwise.

```bash
./governance vault tenant-session meta-platform   # in parent-group-governance
terraform -chdir=terraform/layers/platform-spire-parent apply
```

## Section 2. Runbook: verify the trust between SPIRE Parent and the Cilium cluster

The verification is read-only and prints no token.

The Cilium nodes run no SPIRE agent, and the trust of the Cilium cluster in SPIRE Parent therefore consists of the operator identity of Cilium and the network path from SPIRE Parent to the nodes.

The verification has four links: the network path to SPIRE Parent, the TLS chain of the OIDC discovery provider, the JWT-SVID of the Cilium operator, and the JWT login at the Downstream Vault.

The commands MUST run on the operator workstation in the account of the operator.

### Task A. Set the variables

The commands run inside a tenant session, which exports the Bastion Vault address and the Bastion Vault listener CA.

The Downstream Vault address is the output `endpoint` of `platform-vault-downstream-frontend`, and the CA chain of its listener is the file `tls/listener-ca-chain.crt` of that layer.

The address of SPIRE Parent is the value `spire_parent_node_ip` in `ansible/inventory-provision-spire-parent-frontend-operator.yaml`.

The ports are the `api` and `oidc` entries of component `parent` of service `spire` in `terraform/layers/foundation-libvirt-resources/terraform.tfvars`.

```bash
ADDR=$VAULT_ADDR
LISTENER_CA=$VAULT_CACERT
DOWNSTREAM_ADDR=$(terraform -chdir=terraform/layers/platform-vault-downstream-frontend output -raw endpoint)
DOWNSTREAM_CA=terraform/layers/platform-vault-downstream-frontend/tls/listener-ca-chain.crt
PARENT=172.16.125.200
ROLE=meta-platform-terraform-operator-cilium-hubble
MOUNT=meta-platform-spire-parent-jwt-svid-provider
```

### Task B. Test the network path to SPIRE Parent

Port 8081 serves the SPIRE server API, and port 8443 serves the OIDC discovery provider.

Both ports MUST accept a TCP connection.

```bash
for p in 8081 8443
do
  timeout 4 bash -c "exec 3<>/dev/tcp/$PARENT/$p" && echo "$p open" || echo "$p CLOSED"
done
```

### Task C. Build the PKI chain file

The certificate of the OIDC discovery provider is issued by the `pki-platform` mount of the Bastion Vault.

The certificate file served by the OIDC discovery provider holds the leaf certificate and the `pki-platform` certificate.

A client MUST hold both the root and the intermediate certificate to verify the leaf certificate.

The file `tls/bastion-ca.pem` holds the listener CA of the Bastion Vault and MUST NOT serve as the trust anchor of this test.

The two CA endpoints of the Bastion Vault need no token.

The PEM files MUST be separated by a newline, and a file without the separator fails the verification without an error message.

```bash
CHAIN=$(mktemp)
for m in pki-root pki-platform
do
  curl -s --cacert "$LISTENER_CA" "$ADDR/v1/$m/ca/pem" >> "$CHAIN"
  echo >> "$CHAIN"
done
grep -c 'BEGIN CERTIFICATE' "$CHAIN"
```

The count MUST be `2`.

### Task D. Verify the OIDC discovery provider

The discovery document MUST carry the issuer `https://<PARENT>:8443`.

The key set MUST hold at least one key.

The Downstream Vault fetches both documents with the chain of Task C through the setting `oidc_discovery_ca_pem`.

```bash
curl -s --cacert "$CHAIN" "https://$PARENT:8443/.well-known/openid-configuration" | python3 -m json.tool | head -4
curl -s --cacert "$CHAIN" "https://$PARENT:8443/keys" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["keys"]), "keys")'
```

### Task E. Verify the JWT-SVID and the Vault login of the Cilium operator

The wrapper `spire-fetch-meta-platform-terraform-operator-cilium-hubble` prints a JSON document with the field `jwt`.

The subject MUST be `spiffe://<trust domain>/meta-platform/terraform-operator/cilium/hubble`, and the audience MUST be `vault`.

The login at the Downstream Vault MUST return the policy `meta-platform-terraform-operator-cilium-hubble`, after `security-vault-downstream-tenants` is applied.

The command prints the claims and the policy names only.

```bash
JWT=$(/usr/local/bin/spire-fetch-$ROLE | python3 -c 'import json,sys; print(json.load(sys.stdin)["jwt"])')
echo "$JWT" | python3 -c '
import base64, json, sys, time
p = sys.stdin.read().strip().split(".")[1]
c = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
print("sub", c["sub"])
print("aud", c["aud"])
print("expires in", int(c["exp"] - time.time()), "seconds")'
curl -s --cacert "$DOWNSTREAM_CA" -X POST "$DOWNSTREAM_ADDR/v1/auth/$MOUNT/login" -H 'Content-Type: application/json' \
  -d "{\"role\":\"$ROLE\",\"jwt\":\"$JWT\"}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("auth",{}).get("policies") or d.get("errors"))'
unset JWT
```

### Task F. Verify the SPIRE Parent server

The server MUST report `Server is healthy`.

The list MUST hold at least the agent of the operator workstation.

```bash
ssh meta-platform-spire-parent-node-00 'sudo spire-server healthcheck -socketPath /opt/spire/server/data/private/api.sock'
ssh meta-platform-spire-parent-node-00 'sudo spire-server agent list -socketPath /opt/spire/server/data/private/api.sock' | grep 'SPIFFE ID'
```

### Task G. Test the path from SPIRE Parent to the Cilium nodes

The node addresses MUST come from `kubectl get nodes -o wide`, column `INTERNAL-IP`.

The range `ip_range` of the service catalog is not the node address.

The kubeconfig lives in the Bastion Vault at `meta-platform/cilium/hubble/cluster-config`, field `content_b64`.

The temporary kubeconfig MUST be deleted after the test.

Port 6443 serves the Kubernetes API, and port 50000 serves the Talos API.

```bash
KUBECONFIG_FILE=$(mktemp)
vault kv get -mount=secret -field=content_b64 meta-platform/cilium/hubble/cluster-config | base64 -d > "$KUBECONFIG_FILE"
NODES=$(kubectl --kubeconfig "$KUBECONFIG_FILE" get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
for h in $NODES
do
  for p in 6443 50000
  do
    ssh meta-platform-spire-parent-node-00 "timeout 4 bash -c 'exec 3<>/dev/tcp/$h/$p' && echo $h:$p open || echo $h:$p CLOSED"
  done
done
rm -f "$KUBECONFIG_FILE" "$CHAIN"
```

The test covers the direction from SPIRE Parent to the nodes.

The direction from the nodes to SPIRE Parent needs a temporary pod in the cluster, and the verification does not cover that direction.

### Task H. Read the result

| Symptom                                                       | Cause                                                                                | Action                                                                                                                                    |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Task C prints a count other than `2`                          | The Bastion Vault answered with an error, or the listener CA is wrong                | Check `VAULT_CACERT` of the tenant session and the mount names `pki-root` and `pki-platform` in `registry/meta-platform/bastion`          |
| Task D fails with `unable to get local issuer certificate`    | The trust anchor lacks the intermediate, or the PEM files lack the newline separator | Rebuild the chain file with Task C                                                                                                        |
| Task D shows no key                                           | The OIDC discovery provider runs without a JWT key                                   | Check `systemctl status spire-oidc-discovery-provider` on SPIRE Parent                                                                    |
| Task E prints no JWT                                          | The agent of the workstation holds no valid identity for the current SPIRE Parent    | Apply `provision-spire-parent` again, because the role `utils_spire_agent` re-attests a stale agent                                       |
| Task E login answers `permission denied` or an audience error | The mount or the role is missing, or the audience differs from `vault`               | Apply `provision-spire-parent` and then `security-vault-downstream-tenants`                                                               |
| Task F lists no agent                                         | The workstation agent never attested to this SPIRE Parent                            | Apply `provision-spire-parent` again                                                                                                      |
| Task G reports `CLOSED` for every node                        | The addresses come from the wrong source, or the route between the segments is down  | Use the `INTERNAL-IP` column and check the route `172.16.0.0/16` on SPIRE Parent                                                          |
