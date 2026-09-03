// Package ansibleops executes ansible-playbook tasks via go-ansible under ANSIBLE_CONFIG scoping.
package ansibleops

import (
	"context"
	"path/filepath"

	"github.com/apenella/go-ansible/v2/pkg/execute"
	"github.com/apenella/go-ansible/v2/pkg/playbook"
)

// RunPlaybook executes playbookFile using opts while injecting ANSIBLE_CONFIG derived from ansibleDir.
// If runDir is non-empty, sets the command execution directory to runDir to resolve relative playbook paths.
func RunPlaybook(ctx context.Context, ansibleDir, runDir, playbookFile string, opts *playbook.AnsiblePlaybookOptions) error {
	cmd := playbook.NewAnsiblePlaybookCmd(
		playbook.WithPlaybooks(playbookFile),
		playbook.WithPlaybookOptions(opts),
	)

	execOpts := []execute.ExecuteOptions{
		execute.WithCmd(cmd),
		execute.WithEnvVars(map[string]string{
			"ANSIBLE_CONFIG":      filepath.Join(ansibleDir, "ansible.cfg"),
			"ANSIBLE_FORCE_COLOR": "1",
		}),
	}
	if runDir != "" {
		execOpts = append(execOpts, execute.WithCmdRunDir(runDir))
	}

	return execute.NewDefaultExecute(execOpts...).Execute(ctx)
}
