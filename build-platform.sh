#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Repository constants. The KV path and its field are frozen names of parent-group-governance.
# The SonarQube project key is the GitLab project path with slashes replaced by hyphens.
readonly cli="platform"
sonar_project_key="$(git remote get-url origin | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##; s#/#-#g')"
readonly sonar_project_key
readonly sonar_token_path="secret/parent-group-governance/sonarqube/ci-analysis-bot"
readonly sonar_token_field="sonarqube_ci_token"
readonly scanner_image="docker.io/sonarsource/sonar-scanner-cli:12.1.0.3225_8.0.1"

go test -C tools/"${cli}" -race -count=1 -coverprofile=coverage.out ./...
go build -C tools/"${cli}" -o ../../"${cli}" ./cmd/"${cli}"

# Workstation values come from .env through the binary, the sole parser of .env, unless an exported variable overrides them.
bastion_vault_addr="${BASTION_VAULT_ADDR:-$(./"${cli}" env get BASTION_VAULT_ADDR)}"
bastion_vault_cacert="${BASTION_VAULT_CACERT:-$(./"${cli}" env get BASTION_VAULT_CACERT)}"
sonar_host_url="${SONAR_HOST_URL:-http://127.0.0.1:9000}"
readonly bastion_vault_addr bastion_vault_cacert sonar_host_url

# A session token takes precedence over the token file of the vault CLI. The separate assignment stops the run on a
# failed read, which a prefix assignment of podman would ignore, and keeps the token out of every other command.
sonar_token=$(VAULT_ADDR="${bastion_vault_addr}" VAULT_CACERT="${bastion_vault_cacert}" \
    VAULT_TOKEN="${VAULT_TOKEN:-$(cat "$HOME/.vault-token")}" \
    vault kv get -field="${sonar_token_field}" "${sonar_token_path}")

# The scanner mounts only the analyzed trees read-only, since the indexer walks the whole base directory.
# The root .gitignore drives the SCM exclusion, which keeps generated files such as 0600 inventories unread.
SONAR_TOKEN="${sonar_token}" podman run --rm --network host \
    --security-opt label=type:spc_t \
    -e SONAR_HOST_URL="${sonar_host_url}" \
    -e SONAR_TOKEN \
    -e SONAR_SCANNER_OPTS="-Dsonar.projectKey=${sonar_project_key} -Dsonar.projectBaseDir=/usr/src -Dsonar.qualitygate.wait=true -Dsonar.sources=tools,terraform,ansible,packer,selinux -Dsonar.exclusions=**/testdata/**,**/.terraform/** -Dsonar.tests=tools -Dsonar.test.inclusions=**/*_test.go -Dsonar.go.coverage.reportPaths=tools/${cli}/coverage.out" \
    -v "$PWD/tools:/usr/src/tools:ro" \
    -v "$PWD/terraform:/usr/src/terraform:ro" \
    -v "$PWD/ansible:/usr/src/ansible:ro" \
    -v "$PWD/packer:/usr/src/packer:ro" \
    -v "$PWD/selinux:/usr/src/selinux:ro" \
    -v "$PWD/.git:/usr/src/.git:ro" \
    -v "$PWD/.gitignore:/usr/src/.gitignore:ro" \
    "${scanner_image}"

echo "built: $(pwd)/${cli}"
