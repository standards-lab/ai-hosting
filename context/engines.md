# Engines

The vLLM rows ai-hosting runs and the `engine` group that runs them. The group's verbs are listed
in [the `hosting` suite](hosting-suite.md); each row's settings live in its class's profile,
`classes/<class>/profile.toml` ([classes/README.md](../classes/README.md)); and each class's
runbook, `classes/<class>/runbook.md`, gives the root steps and each row's commands.

## Where the engine files come from

The engine files carry no source comments; this list cites each one's spike source.

- From spike-model-engines at `6ce3210`:
  - `bin/hosting`, from `host/engines`;
  - `lib/row.sh` and `lib/engine.sh`, from `host/vllm.sh` and `host/engines.sh`;
  - `lib/vllm.env`, from `host/vllm.env`;
  - the four standing rows, from `host/vllm-rows`;
  - the audio image, from `host/vllm-rocm-audio/Dockerfile`; its `MIOPEN_FIND_MODE=FAST` is
    ai-hosting's own;
  - `.shellcheckrc`.
- The GB10's CDI preflight in `lib/engine.sh` comes from spike-ai-pipeline's
  `scripts/host-update-lib.sh` at `6a631f1`.
- The GPU memory reads in `lib/observe.sh` come from spike-model-layout's
  `scripts/measure-lib.sh` at `e64d9c4`, and the Framework's `amdgpu_top --no-pc` from
  spike-model-hosting's `evaluation/scripts/footprint.sh` at `aac0764`.

The measurements behind the carried values stay in `standards-lab/context/ai-hosting.md`.

From spike-model-engines, these are not carried:

- the group `vllm-native`: `host/vllm-native.sh`, its three commands, `host/vllm-server.service`,
  `host/vllm-server.sudoers`, and the `VLLM_NATIVE_PYTHON` pin;
- the groups `llama` and `llama-native`: llama.cpp's thirteen files, and the cross-engine guards
  in `host/engines.sh` and `host/vllm.sh`;
- the other twelve rows of `host/vllm-rows`, the per-class default rows, and the default
  container `vllm` on port 8000;
- `VLLM_TRACE` and install's release argument: no row traces, since tracing is the gateway's;
- `scripts/check.sh` (ai-hosting has its own), `docs/engines/*` (each class's runbook takes their
  root steps), and `mise.host.toml` (the hf CLI is pinned in ai-hosting's `mise.toml`).

The read-only verbs `engine status`, `models`, `metrics`, and `memory` do what personal-agents'
`outpost` commands at `d3e0755` did (`admin/bin/outpost-service-status`, `outpost-server-models`,
`outpost-server-metrics`, and `outpost-amd-usage`), for vLLM's rows. `outpost`'s model load and
unload are not carried, since model management stays off the serving API, and neither are
`outpost-preset-install` and `outpost-service-restart`.

## The audio image

The audio image, [`images/vllm-openai-rocm-audio`](../images/vllm-openai-rocm-audio/Dockerfile),
sets `MIOPEN_FIND_MODE=FAST`, which skips MIOpen's live solver timing. That timing fails on the
Framework's gfx1151: the base image turns off the direct and GEMM convolutions and ships no
readable gfx1151 find database, so without FAST, Gemma 4's audio encoder fails on audio of 10 s or
more.

The suite builds the image with `--provenance=false`. Under Docker's containerd image store, which
the Framework uses, an image's ID covers the provenance attestation BuildKit attaches by default,
and that attestation differs on every build. With it, even a fully cached rebuild would get a new
ID, and `engine update`, which replaces a row whose image ID differs, would replace the audio row
on every run.

- Every audio cell ran in the audio image, under FAST, and the row's cap follows its throughput on
  docinfer's windows, with RTFx reported beside it ([audio findings](../docs/findings/audio.md)).
  The embedding row runs the stock ROCm image and takes no MIOpen setting: its long-input probe,
  512 tokens, passed on it ([findings](../docs/findings/embedding.md#e5-probes)).
- A report upstream is deferred to the backlog. The watch register's gfx1151 entry checks each
  vLLM ROCm image for a gfx1151 find database, and its action drops FAST
  ([watch.md](../docs/watch.md#a-gfx1151-miopen-find-database-in-vllms-rocm-image)).

## The vLLM release

`lib/vllm.env` pins v0.34.0, the release current when `hosts` built, with the rows' flags
unchanged. The four rows ran together on it, each matching its row alone except vision at 32
streams, which decoded no slower yet finished 3–4% fewer pages in the second half ([the layout
cell](../docs/findings/vision.md#layout)).

The Framework's gfx1151 runs v0.34.0's extensible KV cache, which sizes a row's KV cache from the
memory free after warmup, and doesn't take the fallback to the profiling estimate that a driver
without virtual memory support takes (spike-model-engines `docs/engines/vllm/update.md` at
`90fac78`, "v0.34.0's KV cache"). The audio row's start on `framework` at 2026-11-26T12:53:19Z
logged `16472 KV cache blocks (16.09 GiB) fit within the requested 33.6 GiB` and then `Extended KV
cache to 16472 blocks (16.09 GiB)`; the container's log holds four starts from 10:15:56Z, each with
the same line and none with a line disabling the extensible cache. The embedding row on
framework-2 logs `Disabling the extensible KV cache: the model has no KV cache` at each start, its
last at 2026-11-26T10:56:59Z: an encoder model's estimate, not the driver's fallback.

A candidate release runs off the pin from a branch that moves it, checked out on the host
([upgrades.md](../docs/upgrades.md#measures-three-passes)).
