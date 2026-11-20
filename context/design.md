# Design note

What ai-hosting takes from experiment.hosting's spikes, the `hosting` suite it builds from them,
and what leaves each workstation once it stands. Spike files are cited as `path` at the spike's
commit; spike-model-engines is read at `6ce3210`, personal-agents' `outpost` at `d3e0755`.

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
| `gateway render`, `validate`, `up`, `down`, `reset`, `status`, `key issue`, `key revoke` | The gateway stack; `status` calls the stranded-container check | gateway |

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
