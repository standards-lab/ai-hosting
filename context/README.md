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

- [`design.md`](design.md): the design note: the layout, the `hosting` suite, secrets, what each
  later task's plan settles, the Foundry scope for embedding overflow, the cleanup inventory, and
  the settled findings.

## Capability map

- **The `hosting` suite**: one command, `hosting <group> <verb>`, linked into `~/.local/bin` by
  `mise run install`, with the groups `engine`, `model`, `profile`, `gateway`, and `key`. A
  command that differs by host class detects the class once and calls its private per-class
  function.
- **Host-class profiles**: one TOML profile per class, the one home of each row, with the
  `profile` group's validator, renderer, and `set`.
- **vLLM rows**: the `engine` group installs, updates, and uninstalls each class's rows, and
  reports their status, served model, metrics, and GPU memory, read-only.
- **Model files**: the `model` group lists, pulls, and prunes the host's model store.
- **The gateway**: agentgateway's compose stack, with keys, priority, budgets, overflow, and
  telemetry; the `gateway` group runs it and the `key` group issues consumers' keys.
- **Secrets**: read through fnox from the private `secrets` store repository.
- **Runbooks**: one per host class.
- **Upgrade evaluation**: the convention and its `hosting-upgrades` skill.
- **Admin tooling** (planned, after experiment.admin's intake): experiment.admin's Go CLI,
  implementing the profile schema.
