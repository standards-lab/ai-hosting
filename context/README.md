# ai-hosting context

ai-hosting specifies how the organization's local model hosts serve models: the settings the two
Framework desktops and the two GB10 workstations use, stated generally enough that another host of
the same class follows them. Its secrets, the `hosting` suite, and each class's profile and
runbook are built, and each host serves its rows from its clone. One gateway on gb10-2 fronts the
rows, each alias at its own base URL behind an issued key, with overflow to Azure AI Foundry
([docs/gateway.md](../docs/gateway.md)). go-ai and docinfer hold its keys; Pi sessions, Claude
Code subagents, and the capstone's services are to reach the rows through it with keys the tasks
that build them issue. ai-hosting is low-level infrastructure outside the five tiers, beside the
harness repositories, and is the one hosting repository on each workstation.

A row is one vLLM container serving one model under its role's alias (`agent`, `vision`, `audio`,
`embedding`); a host class is `gb10` or `strix-halo`.

Each host serves one row: `agent` on gb10-1, `vision` on gb10-2, `audio` alone on `framework`,
and `embedding` alone on framework-2; each row's port is in its class's profile. Each Strix Halo
host keeps its model store on its second NVMe
([strix-halo runbook](../classes/strix-halo/runbook.md#the-model-store)), and both unlock remotely
([strix-halo runbook](../classes/strix-halo/runbook.md#remote-unlock)).

Its goals live in the coordinator's roadmap (`standards-lab/roadmap/index.toml`, v1.ai.hosting).
It is built from experiment.hosting's spikes. Each capability's note cites the spike files it
comes from, as `path` at the spike's commit; the files themselves carry no source comments. A
planned capability's note also lists what is open at the plan of the task that builds it; the goal
record holds the tasks and their order.

## Capability map

- **The `hosting` suite** (built): one command, `hosting <group> <verb>`, linked into
  `~/.local/bin` by `mise run install`, with the groups `engine`, `model`, `profile`, `gateway`,
  and `key` (`bin/`, `lib/`; [hosting-suite.md](hosting-suite.md)).
- **Host-class profiles** (built): one TOML profile per class, the one home of each row, with the
  `profile` group's validator, renderer, and `set` ([classes/README.md](../classes/README.md),
  [host-classes.md](host-classes.md)).
- **vLLM rows** (built): the `engine` group installs, updates, and uninstalls each class's rows,
  builds the audio image (`images/`), and reports the rows' status, served model, metrics, and GPU
  memory, read-only ([engines.md](engines.md)).
- **Model files** (built): the `model` group lists, pulls, and prunes the host's model store
  ([hosting-suite.md](hosting-suite.md)).
- **The gateway** (built): agentgateway's compose stack on gb10-2, with keys, priority, budgets,
  overflow, and telemetry; the `gateway` group runs it and the `key` group issues consumers' keys
  ([docs/gateway.md](../docs/gateway.md), [gateway.md](gateway.md)). The embedding route has no
  cloud fallback.
- **Secrets** (built): the Foundry key and account, age-encrypted in ai-hosting's committed
  `fnox.toml`, each described, and checked by `scripts/lint-secrets.sh` ([secrets.md](secrets.md)).
- **Runbooks** (built): one per host class, `classes/<class>/runbook.md`: the root steps, the
  suite's install, and each row's commands ([gb10](../classes/gb10/runbook.md),
  [strix-halo](../classes/strix-halo/runbook.md)).
- **The bench** (built): GuideLLM and MTEB in mise's `bench` environment, with a GuideLLM
  scenario for each purpose, the agent's among them, the cell runner `bench/cell.sh`, which runs
  a scenario against one row a level at a time, and the BelebeleRetrieval runner, all run from the
  laptop ([bench/README.md](../bench/README.md)). The scenarios and `levels.jq` derive from
  spike-model-layout's `bench/` at `e64d9c4`.
- **Findings** (built): the measurements behind a row's settings, each cell with its command,
  time, figures, and tool versions, which the profile's reasons cite: the embedding row's in
  [docs/findings/embedding.md](../docs/findings/embedding.md), the audio row's in
  [docs/findings/audio.md](../docs/findings/audio.md), and the vision row's image budget and cap in
  [docs/findings/vision.md](../docs/findings/vision.md).
- **Upgrade evaluation** (built): the convention for evaluating a vLLM release, a row's settings,
  or a replacement model ([docs/upgrades.md](../docs/upgrades.md)), the policy every candidate
  meets ([docs/policy.md](../docs/policy.md)), one descriptor a host
  ([docs/hosts/](../docs/hosts/)), and the `hosting-upgrades` skill, whose `setup`, `survey`, and
  `measure` modes run it
  ([.claude/skills/hosting-upgrades/](../.claude/skills/hosting-upgrades/)).
- **Admin tooling** (planned): experiment.admin's Go CLI, which implements the profile schema
  ([classes/README.md](../classes/README.md)), built after experiment.admin's intake.
- **One hosting repository per workstation** (built): each host runs the suite from one clone,
  `~/ai-hosting`, and `engine install` and `update` refuse a container outside the rows that holds
  a row's name or port ([gb10](../classes/gb10/runbook.md#install-the-suite),
  [strix-halo](../classes/strix-halo/runbook.md#install-the-suite)).
