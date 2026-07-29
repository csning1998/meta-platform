# csning1998-lab-governance

This repository provides group-scoped governance through several Terraform layers, container services, and shell entry points that provision the GitLab group topology, the shared runner, the SonarQube instance, and the Vault instance supporting this namespace.

## Section 1. SELinux Configuration

The services defined in `compose.yml` run under rootless Podman on a host with SELinux in enforcing mode. Every bind mount originates from a path beneath the user home directory, whose policy default type is `user_home_t`. A process confined as `container_t` has no access to `user_home_t`, which makes an explicit `container_file_t` label necessary on every mount source.

### Item A. Standing Conventions

Four conventions MUST hold for every service declared in `compose.yml`.

1. **Bind mounts declare no relabel flag**. Neither `:z` nor `:Z` MUST appear on any volume line. Item F documents the incident that motivated this restriction.
2. **The `security_opt: label=disable` setting MUST NOT appear** on any long-running service. Disabling label separation removes confinement outright rather than resolving the underlying label mismatch.
3. **Mount source paths are registered through `semanage fcontext`**. The registration establishes `container_file_t` as the policy default rather than a manually applied label.
4. **Any service that reaches the rootless Podman socket MUST declare `label=type:container_engine_t`**. The policy module under `selinux/` supplies the `connectto` permission required by that type.

### Item B. Registering Persistent File Contexts

1. Registering the mount source paths and applying the labels requires root privileges.

    ```bash
    sudo semanage fcontext -a -t container_file_t "$PWD/(vault|sonarqube|runner-config)(/.*)?"
    sudo restorecon -RFv "$PWD/vault" "$PWD/sonarqube" "$PWD/runner-config"
    ```

2. The `-F` flag is mandatory, because the type `container_file_t` appears in `/etc/selinux/targeted/contexts/customizable_types`, whose entries `restorecon` leaves untouched unless the flag is supplied. Omitting the flag produces `not reset as customized by admin` for each path.

3. A correct label appears as `container_file_t:s0` without any category suffix. An empty category set is dominated by every possible container category, which is why a bare `container_file_t:s0` label remains readable by any of the four services regardless of the category each one receives at its own startup.

4. This step MUST be repeated whenever an unrelated tool recursively relabels a path beneath `vault/`, `sonarqube/`, or `runner-config/`, as described in Item F. No relabel flag on the services' own volumes prevents Podman from reintroducing the problem, but it does not protect against third-party tooling that mounts a broader path.

### Item C. Installing the Policy Module

The default policy grants no `connectto` permission on the container runtime socket to either `container_t` or `container_engine_t`. The module under `selinux/` grants the `connectto` permission to `container_engine_t` alone. Containers of every other type remain unaffected. This mechanism operates at the SELinux type level and is independent of the MCS category handling described in Item B; installing or removing it has no bearing on category drift.

```bash
cd selinux
checkmodule -M -m -o gitlab_runner_podman.mod gitlab_runner_podman.te
semodule_package -o gitlab_runner_podman.pp -m gitlab_runner_podman.mod
sudo semodule -i gitlab_runner_podman.pp
sudo semodule -l | grep gitlab_runner_podman
```

Only `gitlab_runner_podman.te` is tracked in version control. The compiled `.mod` and `.pp` artifacts are build outputs excluded through `.gitignore`.

### Item D. Verification

1. Each container MUST report a non-empty process label. An empty value indicates that label separation is disabled.

    ```bash
    for c in meta-provision-vault-server meta-provision-sonarqube-db \
            meta-provision-sonarqube gitlab-runner-csning1998-lab-shared; do
      printf '%s\t' "$c"
      podman inspect "$c" --format '{{.ProcessLabel}}'
    done
    ```

2. The following command reports the distinct set of labels carried by every file beneath the mount sources, a set that MUST contain the single entry `container_file_t:s0` without a category suffix.

    ```bash
    ls -RZ vault sonarqube runner-config | grep -o 'container_file_t:s0[^ ]*' | sort -u
    ```

3. The runner MUST be able to reach the Podman socket. The following request confirms access through an HTTP status of 200.

    ```bash
    podman exec gitlab-runner-csning1998-lab-shared \
        curl -s -o /dev/null -w '%{http_code}\n' \
        --unix-socket /run/podman/podman.sock http://d/v1.41/_ping
    ```

### Item E. Diagnosing a Denial

1. Attribution requires the audit log, because access failures appear only as ordinary permission errors inside the container. The following command isolates denials raised by confined container processes.

    ```bash
    sudo ausearch -m avc -ts recent | grep 'scontext=system_u:system_r:container'
    ```

2. Denials raised by `pasta_t` against `config_home_t` or `data_home_t` are unrelated to this configuration. Such denials originate from file descriptors that the rootless network backend inherits from the process that launches Podman.

3. A denial whose `tcontext` carries a non-empty MCS category on a path beneath `vault/`, `sonarqube/`, or `runner-config/` indicates category drift. Item B restores the baseline, and Item F identifies which tool caused the drift.

4. A denial whose `tcontext` names `container_runtime_t` with class `unix_stream_socket` and permission `connectto` indicates that the policy module described in Item C is absent, or that the service omits the `container_engine_t` declaration.

5. The policy default for any path is retrieved through `matchpathcon`, which MUST report `container_file_t:s0` for every registered mount source.

    ```bash
    matchpathcon vault/data sonarqube/data runner-config
    ```

### Item F. Avoiding Recursive Relabeling from Local Tooling

Podman relabel flags `:z` and `:Z` each recursively rewrite the MCS category of every file beneath the mounted path at container start. A tool that mounts the repository root with either flag therefore rewrites `vault/`, `sonarqube/`, and `runner-config/` as a side effect, even when that tool is unrelated to the services defined in `compose.yml`.

This failure was traced to `.githooks/pre-commit` and `.githooks/commit-msg`, each of which ran `podman run -v "${REPO_ROOT}":/repo:Z` on every commit. The recursive relabel left the three service directories with a category that matched neither the hooks' own short-lived container nor any of the four running services, producing denials unrelated to container startup or restart. A resulting denial can cause Vault's raft storage to fail a write, panicking the process and losing the unseal state.

Both hooks read the repository without writing to it and therefore require no relabeling at all. The fix replaces `:Z` with `--security-opt label=disable`, scoped to these two short-lived, non-secret-holding containers, which presents a different risk profile from disabling confinement on a long-running service such as `vault-server`.

Any future local tool that mounts the repository root, or any ancestor of `vault/`, `sonarqube/`, or `runner-config/`, MUST avoid `:z` and `:Z` for the same reason.
