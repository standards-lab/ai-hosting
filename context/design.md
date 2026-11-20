# Design note

What ai-hosting takes from experiment.hosting's spikes, the `hosting` suite it builds from them,
and what leaves each workstation once it stands. Spike files are cited as `path` at the spike's
commit; spike-model-engines is read at `6ce3210`, spike-model-gateway at `2f2e8c1`,
personal-agents' `outpost` at `d3e0755`, and go-web-service's compose files at `2e31ca4`.

## Layout

### From spike-model-engines `host/` at `6ce3210`

| Part in ai-hosting | Source | Task |
| --- | --- | --- |
| The dispatcher, `hosting`, running `hosting-<group>-<verb>` | `host/engines` | hosts |
| The engine library: class detection, container run and compare, labels, preflight | `host/vllm.sh`; from `host/engines.sh` only the store path, `engines_stopped`, and `engines_preflight` | hosts |
| The vLLM pin: the release and the image repositories | `host/vllm.env` | hosts |
| The `engine` group's install, update, and uninstall | `host/engines-vllm-install`, `-update`, `-uninstall` | hosts |
| The four standing rows, with their flags, in the host-class profiles | `host/vllm-rows:154-227` | hosts; the embedding row's model, embedding |
| The Framework's audio image, carrying `ENV MIOPEN_FIND_MODE=FAST` | `host/vllm-rocm-audio/Dockerfile` | hosts |
| Currency's vLLM release check, plus the audio image's `FROM` and its three Python pins | `scripts/currency.sh:71-81` | hosts |
| `.shellcheckrc`, its comment reworded | `.shellcheckrc` | hosts |

The audio image's `MIOPEN_FIND_MODE=FAST` skips MIOpen's live solver timing, which fails on the
Framework's gfx1151: the base image turns off the direct and GEMM convolutions and ships no
readable gfx1151 find database, so Gemma 4's audio encoder failed on audio of 10 s or more.

Each carried file gets a provenance line naming spike-model-engines at `6ce3210`. The rows' four
standing entries are the only rows that carry; the profile is their one home, and `vllm-rows` is
not carried beside it.

The engines group `vllm` carries, renamed `engine`. These drop:

- the group `vllm-native`: `host/vllm-native.sh`, its three commands, `host/vllm-server.service`,
  `host/vllm-server.sudoers`, and the `VLLM_NATIVE_PYTHON` pin;
- the groups `llama` and `llama-native`: llama.cpp's thirteen files, and the cross-engine guards
  in `host/engines.sh` and `host/vllm.sh`;
- the other twelve rows of `host/vllm-rows`, the per-class default rows, and the default
  container `vllm` on port 8000;
- `VLLM_TRACE` and install's release argument;
- `scripts/check.sh` (ai-hosting has its own), `docs/engines/*` (each host class's runbook takes
  their root steps), and `mise.host.toml` (the hf CLI comes from a pin in ai-hosting's
  `mise.toml` instead, which currency reads).

### From spike-model-gateway at `2f2e8c1`

The stack runs on gb10-2 from ai-hosting's clone, layered as go-web-service's is: a root
`compose.yml` names the project and `include:`s one `compose/<service>.yml` per service, and each
service builds from `compose/<service>/Dockerfile`, whose `FROM` line is its one pin and which
carries its config.

| Part in ai-hosting | Source | Task |
| --- | --- | --- |
| The root `compose.yml`: the project's name and its `include:` list | `gateway/compose.yml`; go-web-service's `compose.yml` at `2e31ca4` | gateway |
| agentgateway's service, `compose/agentgateway.yml`, and a one-line Dockerfile whose `FROM` is the v1.7.0 pin | `gateway/agentgateway.yml`; the pin from `gateway/agentgateway/deploy.env:6` | gateway |
| agentgateway's config: four routes, the serving-path allow-list, typed formats, retry, row health, the priority transformation, overflow, `storage: readOnly` | `gateway/agentgateway/config.yaml` | gateway |
| Postgres, holding the budgets and the request log | `gateway/postgres.yml`, `gateway/postgres/Dockerfile` | gateway |
| The Collector, Tempo, and Grafana | `gateway/otel-collector.yml`, `gateway/tempo.yml`, `gateway/grafana.yml`, and their directories | gateway |
| Loki and Mimir, the Collector's `prometheus` and `fluentforward` receivers, and their Grafana datasources | go-web-service's observability profile, `compose/observability.yml`, `compose/loki/`, `compose/mimir/` at `2e31ca4` | gateway |
| The `gateway` group's verbs | `scripts/agentgateway-deploy.sh`, `gateway/compose.sh` | gateway |
| Currency's `FROM` rule, over every `compose/*/Dockerfile`, with `crane` pinned in `mise.toml`; its tag pattern accepts a `v` prefix | `scripts/currency.sh:28-49`, `mise.toml:8-9` | gateway |
| The watch register, `docs/watch.md` and `scripts/watch.sh` | `docs/watch.md`, `scripts/watch.sh` | gateway; whether `upgrades`' skill runs its check is upgrades' |
| ai-hosting's gateway document: the requirements as `ai-hosting.md` settles them, and the reasoning the files' comments lose | `docs/gateway.md`, rewritten | gateway |
| `rows-down.yaml`, without its caps paragraph, and the overlay code: only if acceptance's overflow cells or the per-alias overflow switch use them | `gateway/agentgateway/probes/rows-down.yaml`, `scripts/agentgateway-deploy.sh:139-195` | acceptance; gateway |

agentgateway's config changes on the way in:

- the keys, budgets, and rate buckets are set for the named consumers, with each amount's reason
  in the gateway document; the per-key policies read a class field in the key's metadata in place
  of comparing the name with `"bulk"`, if v1.7.0 accepts one;
- each alias's Azure group gets a switch; the embedding route has no Azure group until
  acceptance's vector-parity cell passes, then names the `embedding` task's model, without the
  `dimensions` override;
- `..`, `%2e%2e`, and `%2f` are refused before routing, proven with the three requests;
- embedding's rate buckets keep their form and take the `embedding` task's figure;
- tracing stays at 100%.

Each file keeps one header and a provenance line naming spike-model-gateway at `2f2e8c1`; a
comment that explains points to the document or principle that governs it. The row-to-host map
derives from the host-class profiles, and one lookup of gb10-2's address serves every use. The
fixed `container_name` drops unless a `gateway` verb needs it, and the `spike.config-section`
label is renamed. gb10-2's Compose version is read again, and one form of the attestation
workaround stays, its reason in the gateway document.

These drop:

- six probes: `priority-flat`, `key-header`, `bulk-budget-low`, `bulk-rate-low`,
  `rate-limit-agent`, and `in-flight-1`;
- `docs/findings/*.md` and `docs/comparison.md`, which the gateway document links at `2f2e8c1`;
- the laptop's deploy, `scripts/agentgateway-deploy.sh`, `gateway/compose.sh`, and the spike's
  `gateway:*` and `agentgateway-deploy` mise tasks, replaced by the `hosting gateway` group;
- `deploy.env`'s image pin, which moves to the Dockerfile, and the deploy's removal of the
  pre-compose container;
- `postgres.env`, the rendered config's secrets, and the 0600/0700 rule (see Secrets in the
  gateway).

### Elsewhere from the spikes

- **The pin's release.** `hosts` pins the vLLM release current when it builds, with the rows'
  flags unchanged; `acceptance` reruns the layout's floors on it and reads the Framework's start
  log for the KV-cache fallback.
- **Off-pin rehearsal.** Whether an upgrade rehearsal needs a run off the pin is `upgrades`'.

## The `hosting` suite

One root command, `hosting <group> <verb> [args]`, runs `hosting-<group>-<verb>` from the clone
and lists the commands from their `# hosting:summary=` lines. A usage error goes to stderr and
exits 2.

**Install.** The install step links one file, `~/.local/bin/hosting`, to the dispatcher; the
dispatcher resolves its own path, so every command runs from the clone. Uninstall removes that
link only when it points into this clone.

### Host classes

The class list is closed, `gb10` and `strix-halo`, and shared by the profile, the detection
function, and `HOSTING_CLASS`.

- One detection function sets the class from a positive probe of each class and refuses a host
  that matches neither. `HOSTING_CLASS` overrides it and is checked against the list.
- Only a command that differs by class detects, once per call, and then calls its private
  per-class function: the image repository and device options, the preflight (the GB10's CDI
  spec), GPU memory, and model prune.
- Uninstall never detects.
- The preflight refuses unless `net.ipv4.ip_nonlocal_bind` is 1, pointing at the runbook's step.
  No command needs sudo.

### Groups and verbs

| Command | What it does | Task |
| --- | --- | --- |
| `engine install <alias>...` | Starts each named row from the class profile, and records the aliases on the host, outside git; runs `model pull` for the row's model first, and builds the row's image when it names one | hosts |
| `engine update [<alias>]` | Pulls or builds first, then replaces a row whose image ID or command differs from its running container; installs a row that is absent; removes the superseded build; runs `model pull` first. With no alias, acts on the recorded aliases | hosts |
| `engine uninstall [<alias>]` | Removes the row's container, found by its row label. With no alias, acts on the recorded aliases | hosts |
| `engine status` | Each labeled row's container state and health, and the stranded-container check: a running container with no published port or no network, printing `docker network connect bridge <container>` | hosts |
| `engine models` | The model a row serves, from its `/v1/models` | hosts |
| `engine metrics <alias>` | A summary of the row's `/metrics` | hosts |
| `engine memory` | GPU memory per process, per class | hosts |
| `model list` | The models in the host's store, their size, and which rows use them | hosts |
| `model pull <repo>` | Downloads a model with hf, using the token when `hf auth whoami` succeeds, else unauthenticated; fails clearly only on a gated repository | hosts |
| `model prune [--yes]` | Lists the models no row of the class profile uses and incomplete downloads; deletes them only with `--yes` | hosts |
| `profile validate` | Validates the host-class profiles; the check runs it over every committed profile | hosts |
| `profile render <alias>` | Prints the `vllm serve` command and container settings a row runs; install and update call the same function | hosts |
| `profile set <alias> <field>=<value>` | Edits the committed profile, validating before it writes | hosts |
| `gateway render`, `validate`, `up`, `down`, `reset`, `status`; key issue and key revoke | The gateway stack (see The `gateway` group) | gateway |

hf's token stays in the host's `~/.cache/huggingface`.

Every row is an alias, checked against the class profile before Docker is touched. Each
container carries a label with its row's id, and every listing reads the label.

**Replacing a model.** `profile set` → `model pull` → `engine update` → commit. Evaluating the
candidate before `profile set` is an upgrade kind, under `upgrades`' convention and its
`hosting-upgrades` skill; the embedding task's replacement is the first and sets the pattern.

### Operator commands from `outpost`

| Command | Source at `d3e0755` | Task |
| --- | --- | --- |
| `engine status` | `admin/bin/outpost-service-status` (unit status and `/health`); the stranded-container check is new | hosts |
| `engine models` | `admin/bin/outpost-server-models`, `list` only; load and unload drop, since model management stays off the serving API | hosts |
| `engine metrics` | `admin/bin/outpost-server-metrics`, reading vLLM's metric names in place of llama.cpp's | hosts |
| `engine memory` | `admin/bin/outpost-amd-usage` (`amdgpu_top -p`) for `strix-halo`; the GB10's source is open | hosts |

All four are read-only. The verb names `models`, `metrics`, and `memory` are this note's working
names; hosts' plan confirms them. `outpost-preset-install` and `outpost-service-restart` drop, and
`admin/install.sh`'s link-every-command install gives way to the one link above.

### The `gateway` group

The group runs on gb10-2, against the stack in ai-hosting's clone. Its verbs cover what the
spike's laptop deploy and `gateway/compose.sh` did.

| Command | What it does | Task |
| --- | --- | --- |
| `gateway render` | Renders agentgateway's config with each key's hash and no secret, validates the copy, and renames it into place only when it passes | gateway |
| `gateway validate` | Validates the config with the pinned agentgateway image, changing nothing | gateway |
| `gateway up` | Refuses when no rendered config exists; otherwise builds and starts the stack | gateway |
| `gateway down` | Stops the stack, keeping its volumes | gateway |
| `gateway reset` | Stops the stack and drops its volumes | gateway |
| `gateway status` | The stack's state, and the stranded-container check for agentgateway and the Collector, the two containers bound to gb10-2's tailnet address | gateway, on what hosts builds |
| key issue `<consumer>` | Generates a consumer's key, stores it encrypted under the consumer's name, and gives the gateway only its hash | gateway |
| key revoke `<consumer>` | Deletes the stored key and its hash | gateway |

The dispatch form of key issue and key revoke is settled at the hosts plan.

**Handover.** gb10-2's old `gateway` project comes down before the new stack binds the same
ports, and the new stack starts on a fresh Postgres volume; the old one held only the spike's
benchmark traffic. `cleanup` removes what the old project leaves (Cleanup inventory, gb10-2).

## Secrets in the gateway

- The workspace's dev-time secret store is SOPS with age, read through fnox from mise's
  `[secrets.fnox]`, with a pinned `fnox exec` as the fallback. The `secrets` task, next after
  design, sets up the convention before any other ai-hosting task; its exact shape is settled at
  the secrets and gateway plans.
- Secrets reach the containers only as Compose secrets fed by fnox: the Foundry key and the
  Postgres password. The rendered config holds no secret, so the 0600/0700 rule drops.
- `key issue <consumer>` stores the key encrypted under the consumer's name, and the gateway
  holds only its hash. A consumer's machine is a recipient and reads its key after a pull.
  `key revoke` deletes both.
- The `gateway` key verbs are the only ones that call fnox; the suite has no `secrets` group.

## Open at the gateway task's plan

The gateway task's plan comments: open points it settles, not settled here. Sources are
spike-model-gateway's at `2f2e8c1`.

1. **The `/models` root.** Each alias's `/models` is the gateway's own answer, so go-ai v0.3.0's
   `Model.Native` carries no served model; pass the row's `root` through, or keep it hidden.
   Source: `docs/gateway.md:50-56`, `gateway/agentgateway/config.yaml:298-304`.
2. **Route `ai` or `llm`.** The inline route `ai` backends are labeled legacy; the `llm` form
   serves one alias per port. Stay on `ai` under the watch register, or move. Source:
   `docs/gateway.md:20-23`, `233-239`; `docs/watch.md:60-154`;
   `gateway/agentgateway/config.yaml:9-18`.
3. **Admission on `/metrics`.** agentgateway reads no row's `/metrics` and queues nothing; leave
   the gap, or author an `extAuthz` or `extProc` service. Source: `docs/gateway.md:187-197`.
4. **A cap on bulk concurrency.** Priority orders only vLLM's waiting queue, and a bulk flood
   pushed interactive vision past its floor; cap bulk, and where. Source:
   `docs/gateway.md:209-216`; `docs/findings/priority.md`, "Benchmark D".
5. **A sliding budget window.** v1.7.0's `rolling: 1h` is a fixed clock hour, so a key can spend
   twice its budget across the boundary. Source: `docs/gateway.md:204-208`;
   `gateway/agentgateway/config.yaml:132-134`; `docs/watch.md:217-237`.
6. **Authenticated OTLP.** The Collector takes spans from any tailnet peer, unauthenticated;
   authenticate it, bind it more narrowly, or leave it to production. Source:
   `docs/gateway.md:137-141`; `gateway/otel-collector.yml:7-8`, `19`.

The plan also settles:

- the stats port's loopback publish, once the Collector scrapes agentgateway on the compose
  network, and Tempo's retention (G7);
- the key set, Cerebro, Athena, Pi, and Claude Code, with the budget and bucket amounts, and the
  class field in the key's metadata if v1.7.0 accepts one (G5, G6);
- whether agentgateway v1.7.0 reads each secret from a file or the environment, and what to do
  with any it can't (G9);
- the tracing ratio, with open point 6 (G23);
- the ports' home: the host-class profile or the gateway.

## multilingual-e5-large on Foundry managed compute

What overflow for the embedding route would deploy, researched 2026-11-19. Acceptance proves a
Foundry managed-compute endpoint through the provider shape before the route gets an Azure group.

**Sourced.**

- The catalog entry, `intfloat-multilingual-e5-large`, is a Hugging Face registry model, version 3
  (2025-10-06), MIT-licensed. It deploys on managed compute only, with no serverless or per-token
  offer, and needs a hub-based (classic) project. The registry is replicated in about 30 regions,
  East US and East US 2 among them; the deployable regions aren't stated. [A], [B]
- It serves Hugging Face TEI: a native `POST` taking `inputs`, `normalize`, `prompt_name`,
  `truncate`, and `truncation_direction`, and an OpenAI-compatible `/v1/embeddings`. The model's
  maximum is 512 tokens, and `truncate` defaults to false. [A]
- No recommended SKU is published (`inferenceRecommendedSkus` is null); the engine is
  `tei-gpu-extra-small`. [A]
- Managed hosting prices, by the hour: Standard_NC4as_T4_v3 $0.526 in East US and East US 2;
  NC8as_T4_v3 $0.752; DS3_v2 $0.293 in East US, $0.229 in East US 2. Managed compute adds no
  surcharge beyond compute and network, and quota must cover 20% more instances, which aren't
  billed. [C], [D]
- Autoscale runs through Azure Monitor with a minimum and maximum; scale to zero isn't
  documented. [E]
- For comparison, per million tokens: text-embedding-3-large $0.13 Global, $0.143 Regional or
  Data Zone; text-embedding-3-small $0.02 Global, $0.022 Regional. [C]

**Inferred.**

- The SKU is Standard_NC4as_T4_v3, from the engine name; the deploy dialog confirms it. At 730
  hours a month that is about $384; NC8as_T4_v3 about $549, DS3_v2 about $214 (East US) or $167
  (East US 2).
- No pause to zero without deleting the deployment (a community answer, [F]), so plan at least one
  instance always on.
- An input over 512 tokens is rejected unless the request sets `truncate`.

Sources: [A] `https://ai.azure.com/catalog/models/intfloat-multilingual-e5-large` (metadata
modified 2025-10-06); [B] `https://learn.microsoft.com/en-us/azure/foundry-classic/concepts/foundry-models-overview`
(2026-07-28); [C] `https://prices.azure.com/api/retail/prices` (queried 2026-11-19); [D]
`https://learn.microsoft.com/en-us/azure/machine-learning/concept-endpoints-online` (updated
2026-10-19); [E] `https://learn.microsoft.com/en-us/azure/machine-learning/how-to-autoscale-endpoints`
(2026-02-11); [F] `https://learn.microsoft.com/en-us/answers/a/12259624` (community). The deploy
flow: `https://learn.microsoft.com/en-us/azure/foundry-classic/how-to/deploy-models-managed`
(2026-01-22).

## Cleanup inventory

What the `cleanup` task removes. Nothing here was checked on the hosts; each item is to confirm
on the host. Root steps are the architect's.

**Every workstation**

- Clones of experiment.hosting's spikes (spike-model-engines, spike-model-gateway,
  spike-model-hosting, spike-hosting-upgrades, spike-model-layout).
- llama.cpp: any `llama` container, llama.cpp image, `llama-router` unit, and `/opt/llama.cpp`.
- Any vLLM container without ai-hosting's row label.
- Images, units, and sudoers rules no `hosting` command created.

**Framework**

- `~/repos/spike-model-engines`, with its uncommitted audio Dockerfile edit; the edit is left
  alone and goes with the clone.
- The spike-named audio images, `spike-model-engines/vllm-openai-rocm-audio:*`.
- The llama.cpp router's paths: `/opt/llama.cpp/current`, `/etc/llama-router`, and its system
  unit.
- `outpost`'s links in `~/.local/bin` (`outpost` and `outpost-*`).

**gb10-1 and gb10-2**

- Native vLLM: `/opt/vllm`, `/etc/systemd/system/vllm-server.service`, and
  `/etc/sudoers.d/vllm-server`.

**gb10-2**

- spike-ai-pipeline's host clone and its router.
- `~/gateway`, after the old project is down: its `postgres.env`, the rendered config, the old
  volumes, the four built images, and the pulled agentgateway image.

## Settled findings

### spike-model-engines `host/`

From the evaluation of `host/` at `6ce3210`.

| Finding | Settlement |
| --- | --- |
| H1 · detection resolves a flavor, not a class | Accepted → hosts: one detection function, positive probes, `HOSTING_CLASS`, private per-class functions, uninstall never detects |
| H2 · no standing set; defaults no host serves | Accepted → hosts: aliases at install, recorded on the host; no-arg update and uninstall read the record; every row names its container and port; the defaults drop |
| H3 · twelve of sixteen rows are benchmarks | Accepted → hosts (four rows); the embedding row's model → embedding |
| H4 · row, release, and tracing by environment | Accepted → hosts: row is a checked argument, `VLLM_TRACE` and the release argument drop; tracing → gateway; off-pin rehearsal → upgrades |
| H5 · the rows file is never validated | Accepted → hosts: the profile validator checks every row before Docker is touched |
| H6 · containers known only by current names | Accepted → hosts: row-id labels, listings by label; unlabeled containers → cleanup |
| H7 · audio image pinned twice, built by hand, spike-named | Accepted → hosts: one pin, currency reads `FROM` and the Python pins, install and update build it and remove the superseded build, named under ai-hosting; spike-named images → cleanup |
| H8 · llama.cpp leaves | Accepted → hosts: thirteen files and the guards drop; store path, `engines_stopped`, `engines_preflight` fold into the library; llama.cpp leftovers → cleanup |
| H9 · native vLLM drops | Accepted → hosts (not carried); `/opt/vllm`, unit, sudoers → cleanup |
| H10 · preflight skips the bind and CDI | Accepted → hosts: sysctl and CDI checks; `docs/engines/` not carried; a runbook per class |
| H11 · comments are history | Accepted → hosts: comments cut to the five kinds; measurements stay in `ai-hosting.md` |
| H12 · the dispatcher carries | Accepted → hosts: `hosting`, `hosting-<group>-<verb>`, one link, usage exit 2; the group is `engine` |
| H13 · surrounding files | Accepted → hosts: currency's vLLM check and `.shellcheckrc` carry; `mise.host.toml` and `scripts/check.sh` drop; hf from ai-hosting's `mise.toml` |
| H14 · v0.34.0 unmeasured | Accepted → acceptance: pin and flags carry at the current release; floors rerun, start log read |
| Q16 · audio requests of 10 s or more fail in MIOpen on gfx1151 | Accepted → hosts: the audio Dockerfile carries `ENV MIOPEN_FIND_MODE=FAST` |
| Q17 · update compares by tag and refuses an absent row | Accepted → hosts: compare image ID, install an absent row, pull or build before remove |
| Q18 · FAST's effect on audio and embedding unmeasured | Accepted → acceptance: audio RTFx and embedding throughput under FAST; embedding's image takes the ENV only if its own long-input probe fails → embedding |
| Q19 · upstream report | Deferred → backlog; upgrades' watch checks each vLLM ROCm release for a gfx1151 find db, so FAST can drop |

### spike-model-gateway

From the evaluation of spike-model-gateway at `2f2e8c1`.

| Finding | Settlement |
| --- | --- |
| G1 · docs restrict overflow to agent and vision | Accepted → gateway: the requirements follow `ai-hosting.md`, overflow on all four aliases |
| G2 · embedding overflows to `text-embedding-3-small` | Accepted → gateway: no Azure group until vector parity, then the embedding task's model, `dimensions` override dropped; acceptance proves a Foundry managed-compute endpoint through the provider shape |
| G3 · overflow can't be switched off | Accepted → gateway: a per-alias overflow switch |
| G4 · dot-segment hardening unimplemented | Accepted → gateway: refuse `..`, `%2e%2e`, `%2f` before routing, proven with the three requests |
| G5 · the spike's four keys, policies compare the name with `"bulk"` | Accepted → gateway: the plan names the key set (Cerebro, Athena, Pi, Claude Code); a class field in key metadata if v1.7.0 accepts one |
| G6 · budgets and buckets sized from benchmarks | Accepted → gateway: mechanism kept, amounts sized for the named consumers |
| G7 · telemetry is traces only | Accepted → gateway: Collector, Tempo, Grafana kept; Loki, Mimir, `prometheus` and `fluentforward` receivers added from go-web-service; stats port and Tempo retention at the plan |
| G8 · priority on Messages unproven | Accepted → acceptance: carried as is; acceptance proves it |
| G9 · rendered config holds secrets, default mode | Revised → secrets, gateway: Compose secrets fed by fnox, no secret in the rendered config, the 0600/0700 rule drops; what v1.7.0 can't read from file or environment → gateway's plan |
| G10 · laptop-side deploy | Accepted → gateway: the `hosting gateway` group; keys stored encrypted under SOPS and fnox, the gateway holds hashes |
| G11 · new stack and `~/gateway` share every name | Accepted → gateway (old project down first, fresh Postgres volume); `~/gateway`, volumes, images → cleanup |
| G12 · `compose.sh` starts with no config | Accepted → gateway: `up` refuses without a rendered config; validate-before-rename and `storage: readOnly` carry |
| G13 · comments hold reasoning and history | Accepted → gateway: one header and a provenance line per file; reasoning in the gateway document, comments link to it |
| G14 · settings for the spike's helpers | Accepted → gateway: `container_name`, `spike.config-section`, the pre-compose removal drop or rename; stats port with G7 |
| G15 · six probes served only the spike | Accepted → gateway: six drop; `rows-down` and the overlay code only if acceptance or G3's switch use them |
| G16 · attestation workaround applied twice | Accepted → gateway: re-read gb10-2's Compose version, keep one form |
| G17 · agentgateway's pin outside the image rule | Accepted → gateway: one-line Dockerfile, currency's `FROM` rule and `crane`, tag pattern for `v` tags; compose layered as go-web-service's |
| G18 · row-to-host map in three files | Accepted → gateway: derived from the host-class profiles |
| G19 · embedding's limits are granite's | Accepted → embedding (the figure, measured on the Framework beside the audio model), gateway (the value) |
| G20 · watch register and upgrade convention overlap | Accepted → gateway (the register carries), upgrades (whether its skill runs it) |
| G21 · `docs/gateway.md` lives in an archived spike | Accepted → gateway: ai-hosting's own gateway document; findings and comparison linked at `2f2e8c1` |
| G22 · tailnet-bound containers | Accepted → gateway, on hosts: `gateway status` calls the stranded-container check |
| G23 · every request traced | Accepted → gateway: 100% carried; the ratio settled with open point 6 |
