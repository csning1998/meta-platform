#!/usr/bin/env bash
# Removes the Terraform operator identities of earlier designs, keeping those of the provision-spire-parent output.
# The default run prints the plan alone. Run with --apply under sudo to remove the listed items.
set -euo pipefail

APPLY=false
[ "${1:-}" = "--apply" ] && APPLY=true

KEEP=(
  meta-platform-terraform-operator-cilium-hubble
  meta-platform-terraform-operator-harbor-origin-frontend
  meta-platform-terraform-operator-keycloak-frontend
  meta-platform-terraform-operator-spire-child
  meta-platform-terraform-operator-vault-downstream-frontend
)
SPIRE_PARENT_HOST="${SPIRE_PARENT_HOST:-meta-platform-spire-parent-node-00}"
SPIRE_SOCKET="/opt/spire/server/data/private/api.sock"

run() {
  if $APPLY; then "$@"; else printf 'would run: %s\n' "$*"; fi
}

is_kept() {
  local name="$1" kept
  for kept in "${KEEP[@]}"; do [ "$name" = "$kept" ] && return 0; done
  return 1
}

if $APPLY && [ "$(id -u)" -ne 0 ]; then
  echo "cleanup: --apply MUST run under sudo" >&2
  exit 1
fi

# The wrappers name every identity which a play of an earlier design registered on this workstation.
for wrapper in /usr/local/bin/spire-fetch-*; do
  [ -e "$wrapper" ] || continue
  name="${wrapper#/usr/local/bin/spire-fetch-}"
  is_kept "$name" && continue
  run rm -f "$wrapper"
  run rm -f "/etc/sudoers.d/terraform-operator-identity-${name}"
  user="svc-${name%-child}"
  if getent passwd "$user" >/dev/null && ! is_kept "${name%-child}"; then
    run userdel "$user"
  fi
done

# The workstation no longer attests to SPIRE Child, since the operators log in with JWT-SVIDs of SPIRE Parent.
if systemctl list-unit-files spire-agent-child.service >/dev/null 2>&1; then
  run systemctl disable --now spire-agent-child.service
  run rm -f /etc/systemd/system/spire-agent-child.service
  run rm -rf /etc/spire/agent-child /opt/spire/agent/data-child
  run systemctl daemon-reload
fi

# SPIRE Parent keeps the workload entry of each removed identity until the entry is deleted.
cat <<EOF

Workload entries on SPIRE Parent for removed operator SPIFFE IDs, listed for review:
  ssh -t ${SPIRE_PARENT_HOST} 'sudo spire-server entry show -socketPath ${SPIRE_SOCKET} -output json' \\
    | jq -r '.entries[] | select(.spiffe_id.path | test("/terraform-operator/")) | [.id, .spiffe_id.path] | @tsv'
Delete each entry whose path is not one of /meta-platform/terraform-operator/{cilium/hubble,harbor-origin/frontend,keycloak/frontend,spire/child,vault-downstream/frontend}:
  ssh -t ${SPIRE_PARENT_HOST} 'sudo spire-server entry delete -socketPath ${SPIRE_SOCKET} -entryID <id>'
EOF
