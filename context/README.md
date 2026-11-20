# ai-hosting context

ai-hosting specifies how the organization's local model hosts serve models: the settings the
Framework desktop and the two GB10 workstations use, stated generally enough that another host of
the same class follows them. It serves Pi sessions, Claude Code subagents, go-ai, and the
capstone's services through one gateway, with overflow to Azure AI Foundry. It is low-level
infrastructure outside the five tiers, beside the harness repositories, and the one hosting
repository on each workstation.

Its goals live in the coordinator's roadmap (`standards-lab/context/roadmap.toml`, v1.ai.hosting).
It is built from experiment.hosting's spikes, and its design note settles which parts come from
which spike.

- [`design.md`](design.md): the design note: the layout, the `hosting` suite, the cleanup
  inventory, and the settled findings.

## Capability map

- **The `hosting` suite**: one command, `hosting <group> <verb>`, symlinked into `~/.local/bin`;
  a command that differs by host class detects the class once and calls its private per-class
  function.
- **Host-class profiles**: the schema, its validator, and its renderer.
- **vLLM rows**: each host class's rows, with install, update, and uninstall.
- **Operator commands**: a row's status, served model, metrics, and GPU memory, read-only.
- **The gateway**: agentgateway's compose stack, with keys, priority, budgets, overflow, and
  telemetry.
- **Runbooks**: one per host class.
- **Upgrade evaluation**: the convention and its `hosting-upgrades` skill.
- **Admin tooling**: after experiment.admin's intake.
