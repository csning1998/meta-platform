package main

import (
	"context"
	"fmt"
	"os"

	"platform/internal/hostsops"
	"platform/internal/libvirtops"
	"platform/internal/ui"
)

// syncHosts rewrites the managed block of /etc/hosts from the libvirt DNS records. Only the backup and the write
// run through sudo, which keeps the libvirt read and the diff unprivileged.
func (a *app) syncHosts(ctx context.Context, apply bool) error {
	documents, err := libvirtops.ListActiveNetworkXML()
	if err != nil {
		return err
	}
	sets := make([][]hostsops.Record, 0, len(documents))
	for _, document := range documents {
		records, err := hostsops.ParseDNSRecords(document, libvirtops.ProjectCode+"-")
		if err != nil {
			return err
		}
		sets = append(sets, records)
	}

	cfg := hostsops.Config{HostsFile: "/etc/hosts", Elevate: []string{"sudo"}}
	current, err := os.ReadFile(cfg.HostsFile)
	if err != nil {
		return fmt.Errorf("hosts sync: %w", err)
	}
	candidate, err := hostsops.RewriteHostsBlock(string(current), hostsops.MergeRecords(sets...))
	if err != nil {
		return err
	}
	diff, changed, err := hostsops.DiffHosts(ctx, cfg.HostsFile, candidate)
	if err != nil {
		return err
	}
	if !changed {
		a.out.Print(ui.OK, cfg.HostsFile+" already matches the libvirt DNS records.")
		return nil
	}
	_, err = fmt.Fprint(os.Stdout, diff)
	if err != nil {
		return fmt.Errorf("hosts sync: print diff: %w", err)
	}
	if !apply {
		a.out.Print(ui.Info, "Dry run. Rerun with --apply to write "+cfg.HostsFile+".")
		return nil
	}

	err = hostsops.ApplyHosts(ctx, cfg, candidate)
	if err != nil {
		return err
	}
	a.out.Print(ui.OK, "Replaced the meta-platform block, backup at "+cfg.HostsFile+".bak.")
	return nil
}
