# ai-hosting context

ai-hosting specifies how the organization's local model hosts serve models: the settings the
Framework desktop and the two GB10 workstations use, stated generally enough that another host of
the same class follows them. Its secrets, the `hosting` suite, and each class's profile and
runbook are built, and each host serves its rows from its clone. It will serve Pi sessions, Claude
Code subagents, go-ai, and the capstone's services through one gateway, with overflow to Azure AI
Foundry; until then, callers use the rows directly. It is low-level infrastructure outside the
five tiers, beside the harness repositories, and is the one hosting repository on each
workstation.

A row is one vLLM container serving one model under its role's alias (`agent`, `vision`, `audio`,
`embedding`); a host class is `gb10` or `strix-halo`.

Its goals live in the coordinator's roadmap (`standards-lab/roadmap/index.toml`, v1.ai.hosting).
It is built from experiment.hosting's spikes. Each capability's note cites the spike files it
comes from, as `path` at the spike's commit; the files themselves carry no source comments. A
planned capability's note also lists what is open at the plan of the task that builds it; the goal
record holds the tasks and their order.

## Capability map

- **The `hosting` suite** (built): one command, `hosting <group> <verb>`, linked into
  `~/.local/bin` by `mise run install`, with the groups `engine`, `model`, and `profile` built and
  `gateway` and `key` planned (`bin/`, `lib/`; [hosting-suite.md](hosting-suite.md)).
- **Host-class profiles** (built): one TOML profile per class, the one home of each row, with the
  `profile` group's validator, renderer, and `set` ([classes/README.md](../classes/README.md),
  [host-classes.md](host-classes.md)).
- **vLLM rows** (built): the `engine` group installs, updates, and uninstalls each class's rows,
  builds the audio image (`images/`), and reports the rows' status, served model, metrics, and GPU
  memory, read-only ([engines.md](engines.md)).
- **Model files** (built): the `model` group lists, pulls, and prunes the host's model store
  ([hosting-suite.md](hosting-suite.md)).
- **The gateway** (planned): agentgateway's compose stack, with keys, priority, budgets,
  overflow, and telemetry; the `gateway` group runs it and the `key` group issues consumers' keys
  ([gateway.md](gateway.md)). The embedding route overflows to Foundry managed compute
  ([foundry-overflow.md](foundry-overflow.md)).
- **Secrets** (built): the Foundry key and account, age-encrypted in ai-hosting's committed
  `fnox.toml`, each described, and checked by `scripts/lint-secrets.sh` ([secrets.md](secrets.md)).
- **Runbooks** (built): one per host class, `classes/<class>/runbook.md`: the root steps, the
  suite's install, and each row's commands ([gb10](../classes/gb10/runbook.md),
  [strix-halo](../classes/strix-halo/runbook.md)).
- **The bench** (built): GuideLLM and MTEB in mise's `bench` environment, with the GuideLLM
  scenarios and the BelebeleRetrieval runner the `embedding` task measures with, run from the laptop
  ([bench/README.md](../bench/README.md)). The scenarios and `levels.jq` come from
  spike-model-layout's `bench/` at `e64d9c4`.
- **Findings** (built): the measurements behind a row's settings, each cell with its command,
  time, figures, and tool versions, which the profile's reasons cite: the embedding row's in
  [docs/findings/embedding.md](../docs/findings/embedding.md).
- **Upgrade evaluation** (planned): the convention and its `hosting-upgrades` skill
  ([host-classes.md](host-classes.md), [engines.md](engines.md)).
- **Admin tooling** (planned): experiment.admin's Go CLI, which implements the profile schema
  ([classes/README.md](../classes/README.md)), built after experiment.admin's intake.
- **One hosting repository per workstation** (built): each host runs the suite from one clone,
  `~/ai-hosting`, and `engine install` and `update` refuse a container outside the rows that holds
  a row's name or port ([gb10](../classes/gb10/runbook.md#install-the-suite),
  [strix-halo](../classes/strix-halo/runbook.md#install-the-suite)).
