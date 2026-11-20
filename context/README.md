# ai-hosting context

ai-hosting specifies how the organization's local model hosts serve models: the settings the
Framework desktop and the two GB10 workstations use, stated generally enough that another host of
the same class follows them. It serves Pi sessions, Claude Code subagents, go-ai, and the
capstone's services through one gateway, with overflow to Azure AI Foundry. It is low-level
infrastructure outside the five tiers, beside the harness repositories, and the one hosting
repository on each workstation.

Its goals live in the coordinator's roadmap (`standards-lab/roadmap/index.toml`, v1.ai.hosting).
It is built from experiment.hosting's spikes. Each capability's note settles which parts come from
which spike, citing spike files as `path` at the spike's commit, and lists what is open at the
plan of the task that builds it; the goal record holds the tasks and their order.

## Capability map

- **The `hosting` suite** (planned): one command, `hosting <group> <verb>`, linked into
  `~/.local/bin` by `mise run install`, with the groups `engine`, `model`, `profile`, `gateway`,
  and `key`. A command that differs by host class detects the class once and calls its private
  per-class function ([hosting-suite.md](hosting-suite.md)).
- **Host-class profiles** (planned): one TOML profile per class, the one home of each row, with
  the `profile` group's validator, renderer, and `set` ([host-classes.md](host-classes.md)).
- **vLLM rows** (planned): the `engine` group installs, updates, and uninstalls each class's rows,
  and reports their status, served model, metrics, and GPU memory, read-only
  ([engines.md](engines.md)).
- **Model files** (planned): the `model` group lists, pulls, and prunes the host's model store
  ([hosting-suite.md](hosting-suite.md)).
- **The gateway** (planned): agentgateway's compose stack, with keys, priority, budgets,
  overflow, and telemetry; the `gateway` group runs it and the `key` group issues consumers' keys
  ([gateway.md](gateway.md)). The embedding route overflows to Foundry managed compute
  ([foundry-overflow.md](foundry-overflow.md)).
- **Secrets** (planned): read through fnox from the private `secrets` store repository
  ([secrets.md](secrets.md)).
- **Runbooks** (planned): one per host class.
- **Upgrade evaluation** (planned): the convention and its `hosting-upgrades` skill.
- **Admin tooling** (planned): after experiment.admin's intake, experiment.admin's Go CLI,
  implementing the profile schema ([host-classes.md](host-classes.md)).
- **One hosting repository per workstation** (planned): the `cleanup` task removes what the
  spikes left on each host ([cleanup.md](cleanup.md)).
