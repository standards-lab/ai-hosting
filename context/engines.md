# Engines

The vLLM rows ai-hosting runs, the `engine` group that runs them, and what ai-hosting takes from
spike-model-engines `host/` at `6ce3210`. The `hosts` task builds them; the group's verbs are
listed in [the `hosting` suite](hosting-suite.md), and each row's settings live in its
[host-class profile](host-classes.md).

## From spike-model-engines `host/`

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

Each carried file gets a provenance line naming spike-model-engines at `6ce3210`. Carried
comments are cut to the five kinds, and the measurements behind them stay in
`standards-lab/context/ai-hosting.md`. The rows' four standing entries are the only rows that
carry; the profile is their one home, and `vllm-rows` is not carried beside it.

The engines group `vllm` carries, renamed `engine`. These drop:

- the group `vllm-native`: `host/vllm-native.sh`, its three commands, `host/vllm-server.service`,
  `host/vllm-server.sudoers`, and the `VLLM_NATIVE_PYTHON` pin;
- the groups `llama` and `llama-native`: llama.cpp's thirteen files, and the cross-engine guards
  in `host/engines.sh` and `host/vllm.sh`;
- the other twelve rows of `host/vllm-rows`, the per-class default rows, and the default
  container `vllm` on port 8000;
- `VLLM_TRACE` and install's release argument; tracing is the gateway's;
- `scripts/check.sh` (ai-hosting has its own), `docs/engines/*` (each host class's runbook takes
  their root steps), and `mise.host.toml` (the hf CLI comes from a pin in ai-hosting's
  `mise.toml` instead, which currency reads).

What the spikes left on the hosts is in [cleanup](cleanup.md).

## The audio image

The audio image's `MIOPEN_FIND_MODE=FAST` skips MIOpen's live solver timing, which fails on the
Framework's gfx1151: the base image turns off the direct and GEMM convolutions and ships no
readable gfx1151 find database, so without it Gemma 4's audio encoder fails on audio of 10 s or
more.

- The image has one pin, which currency reads; install and update build it and remove the
  superseded build, and it is named under ai-hosting, not the spike.
- `acceptance` measures audio RTFx and embedding throughput under FAST. The embedding row's image
  takes the ENV only if the `embedding` task's own long-input probe fails.
- A report upstream is deferred to the backlog; `upgrades`' watch checks each vLLM ROCm release for
  a gfx1151 find database, so FAST can drop.

## The vLLM release and off-pin rehearsal

- **The pin's release.** `hosts` pins the vLLM release current when it builds, with the rows'
  flags unchanged; `acceptance` reruns the layout's floors on it and reads the Framework's start
  log for the KV-cache fallback.
- **Off-pin rehearsal.** Whether an upgrade rehearsal needs a run off the pin is `upgrades`'.

## Operator commands from `outpost`

| Command | Source at `d3e0755` | Task |
| --- | --- | --- |
| `engine status` | `admin/bin/outpost-service-status` (unit status and `/health`); the stranded-container check is new | hosts |
| `engine models` | `admin/bin/outpost-server-models`, `list` only; load and unload drop, since model management stays off the serving API | hosts |
| `engine metrics` | `admin/bin/outpost-server-metrics`, reading vLLM's metric names in place of llama.cpp's | hosts |
| `engine memory` | `admin/bin/outpost-amd-usage` (`amdgpu_top -p`) for `strix-halo`; the GB10's source is open | hosts |

Sources are personal-agents' `outpost` at `d3e0755`. All four are read-only.
`outpost-preset-install` and `outpost-service-restart` drop, and `admin/install.sh`'s
link-every-command install gives way to the suite's one link.

## Open at the hosts plan

- The read-only verb names: `engine status`, `models`, `metrics`, and `memory` are working names.
- The GB10's source for `engine memory`'s GPU memory.
- Whether `engine uninstall` also removes the row's images.
