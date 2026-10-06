package main

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"

	"platform/internal/clusterops"
	"platform/internal/libvirtops"
	"platform/internal/operatorops"
	"platform/internal/ui"
)

// readClusterCredential reads the cluster-config of target from the Vault which the tenants output names. The
// Downstream token stays inside this process, and the shell receives the files alone.
func (a *app) readClusterCredential(ctx context.Context, coordinates clusterops.Coordinates, target operatorops.OperatorSubject) (clusterops.Credential, error) {
	op, err := coordinates.ResolveOperator(target)
	if err != nil {
		return clusterops.Credential{}, err
	}
	if op.ClusterConfig.Vault == "bastion" {
		client, err := clusterops.NewBastionClient(os.Getenv)
		if err != nil {
			return clusterops.Credential{}, err
		}
		return clusterops.ReadCredential(ctx, client, op.ClusterConfig)
	}

	wrapper := operatorops.ResolveWrapperPath(operatorops.Config{
		WrapperDir: operatorops.DefaultWrapperDir,
		OwnerCode:  libvirtops.ProjectCode,
	}, target)
	jwt, err := operatorops.FetchJWT(ctx, wrapper)
	if err != nil {
		return clusterops.Credential{}, err
	}
	client, err := clusterops.LoginDownstream(ctx, coordinates.Address, coordinates.CACertPath, op, jwt)
	if err != nil {
		return clusterops.Credential{}, err
	}
	return clusterops.ReadCredential(ctx, client, op.ClusterConfig)
}

// readTenantsCoordinates reads the output of security-vault-downstream-tenants.
func (a *app) readTenantsCoordinates(ctx context.Context) (clusterops.Coordinates, error) {
	return clusterops.ReadCoordinates(ctx, filepath.Join(a.terraform, "layers", "security-vault-downstream-tenants"))
}

// writeSessionFiles writes the kubeconfig and the talosconfig of target into a new session directory, and removes
// the directory when a write fails.
func (a *app) writeSessionFiles(ctx context.Context, target operatorops.OperatorSubject, cred clusterops.Credential) (string, error) {
	dir, err := clusterops.CreateSessionDir(clusterops.ResolveRuntimeDir(os.Getenv))
	if err != nil {
		return "", err
	}
	kubeconfig, err := clusterops.WriteSessionFile(dir, "kubeconfig", cred.Kubeconfig)
	if err != nil {
		return "", errors.Join(err, os.RemoveAll(dir))
	}
	nodes, err := clusterops.ListNodeAddresses(ctx, kubeconfig)
	if err != nil {
		a.out.Print(ui.Warn, "The talosconfig carries no endpoints, pass talosctl --endpoints: "+err.Error())
	}
	_, err = clusterops.WriteSessionFile(dir, "talosconfig", []byte(clusterops.RenderTalosconfig(target, nodes, cred)))
	if err != nil {
		return "", errors.Join(err, os.RemoveAll(dir))
	}
	a.out.Print(ui.Info, fmt.Sprintf("Cluster %s/%s, nodes: %s", target.Service, target.Component,
		cmp.Or(strings.Join(nodes, " "), "unresolved")))
	return dir, nil
}

// openClusterShell opens a shell whose KUBECONFIG and TALOSCONFIG point at the session files of target.
func (a *app) openClusterShell(ctx context.Context, arg string) error {
	target, err := clusterops.ParseTarget(arg)
	if err != nil {
		return err
	}
	coordinates, err := a.readTenantsCoordinates(ctx)
	if err != nil {
		return err
	}
	cred, err := a.readClusterCredential(ctx, coordinates, target)
	if err != nil {
		return err
	}
	dir, err := a.writeSessionFiles(ctx, target, cred)
	if err != nil {
		return err
	}
	a.out.Print(ui.Info, "Exit the shell to remove the session files.")
	return clusterops.RunSession(ctx, dir, clusterops.BuildShellEnv(os.Environ(), dir, target), a.runClusterShell)
}

// reportClusterStatus prints the nodes and the pods of target, or of every target for all.
func (a *app) reportClusterStatus(ctx context.Context, arg string) error {
	coordinates, err := a.readTenantsCoordinates(ctx)
	if err != nil {
		return err
	}
	if arg != "all" {
		target, err := clusterops.ParseTarget(arg)
		if err != nil {
			return err
		}
		return a.printClusterStatus(ctx, coordinates, target)
	}

	for _, target := range coordinates.ListTargets() {
		err := a.printClusterStatus(ctx, coordinates, target)
		switch {
		case errors.Is(err, clusterops.ErrClusterConfigMissing):
			a.out.Print(ui.Info, "No cluster-config, the component runs on the VM runtime.")
		case err != nil:
			a.out.Print(ui.Warn, err.Error())
		}
	}
	return nil
}

// printClusterStatus prints the nodes and the pods of target through temporary session files.
func (a *app) printClusterStatus(ctx context.Context, coordinates clusterops.Coordinates, target operatorops.OperatorSubject) error {
	a.out.PrintDivider("=")
	a.out.Print(ui.Step, fmt.Sprintf("Cluster %s/%s", target.Service, target.Component))
	cred, err := a.readClusterCredential(ctx, coordinates, target)
	if err != nil {
		return err
	}
	dir, err := a.writeSessionFiles(ctx, target, cred)
	if err != nil {
		return err
	}
	return clusterops.RunSession(ctx, dir, nil, func(ctx context.Context, _ []string) error {
		kubeconfig := filepath.Join(dir, "kubeconfig")
		for _, args := range [][]string{{"get", "nodes", "-o", "wide"}, {"get", "pods", "-A"}} {
			cmd := exec.CommandContext(ctx, "kubectl", append([]string{"--kubeconfig", kubeconfig, "--request-timeout=10s"}, args...)...)
			cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
			err := cmd.Run()
			if err != nil {
				a.out.Print(ui.Warn, "kubectl "+strings.Join(args, " ")+": "+err.Error())
			}
		}
		return nil
	})
}

// runClusterShell runs $SHELL with env and reports the exit status of the shell as information.
// A caught SIGINT keeps platform alive for the removal of the session files, while exec resets the SIGINT disposition inside the shell.
func (a *app) runClusterShell(ctx context.Context, env []string) error {
	interrupts := make(chan os.Signal, 1)
	signal.Notify(interrupts, os.Interrupt)
	defer signal.Stop(interrupts)

	cmd := exec.CommandContext(ctx, cmp.Or(os.Getenv("SHELL"), "/bin/sh"))
	cmd.Env = env
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	err := cmd.Run()
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		a.out.Print(ui.Info, fmt.Sprintf("Session shell exited with status %d.", exitErr.ExitCode()))
		return nil
	}
	return err
}
