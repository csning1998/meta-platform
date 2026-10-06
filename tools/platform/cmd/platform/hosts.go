package main

import (
	"context"

	"platform/internal/hostsops"
	"platform/internal/libvirtops"
	"platform/internal/ui"
)

// syncHosts rewrites the managed block of /etc/hosts from the libvirt DNS records. Only the backup and the write
// run through sudo, which keeps the libvirt read and the diff unprivileged.
func (a *app) syncHosts(ctx context.Context, cfg hostsops.SyncConfig, apply bool) error {
	result, err := hostsops.Sync(ctx, cfg, apply)
	if err != nil {
		return err
	}
	if !result.Changed {
		a.out.Print(ui.OK, cfg.HostsFile+" already matches the libvirt DNS records.")
		return nil
	}
	a.out.PrintText(result.Diff)
	if !apply {
		a.out.Print(ui.Info, "Dry run. Rerun with --apply to write "+cfg.HostsFile+".")
		return nil
	}
	a.out.Print(ui.OK, "Replaced the meta-platform block, backup at "+cfg.HostsFile+".bak.")
	return nil
}

// newHostsSyncConfig returns the sync configuration of /etc/hosts on qemu:///system.
func newHostsSyncConfig() hostsops.SyncConfig {
	return hostsops.SyncConfig{
		Config:         hostsops.Config{HostsFile: "/etc/hosts", Elevate: []string{"sudo"}},
		Prefix:         libvirtops.ProjectCode + "-",
		ListNetworkXML: libvirtops.ListActiveNetworkXML,
	}
}
