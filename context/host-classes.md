# Host-class profiles

Each host class, `gb10` or `strix-halo`, has one profile, which lists every row the class can serve
and is each row's one home. [classes/README.md](../classes/README.md) defines the layout, the
schema, and what `hosting profile validate` refuses; each class's runbook sits beside its profile.
This note keeps the reasoning behind the profiles and what later tasks add to them.

## Why the profiles take this shape

- **TOML, read by shell, with no Go.** The suite's shell commands read and write the profiles with
  mikefarah yq, the reader `mise.toml` pins. The schema document is the contract
  experiment.admin's Go CLI implements.
- **No host identity.** A profile names no host, so another host of the class follows it. Which
  rows a host stands on is the aliases given to `hosting engine install`, recorded on the host.
- **One port an alias, across the classes.** Each alias keeps one port on every class: `agent`
  8000, `vision` 8001, `audio` 8002, `embedding` 8003. The profile is the port's home, and the
  gateway derives each alias's port from it.
- **The fraction sum is install's.** The validator checks each fraction alone. The sum of the
  fractions of the rows standing on one host depends on that host's record, so `engine install`
  checks it in its preflight, against the recorded aliases plus the new ones.
- **No sampling override.** No standing row sets `sampling`. The vision row's source table records
  that its checkpoint's generation config carries its card's values, which vLLM applies by
  default.
- **No engine version.** A row's `measured_vllm` names the release its measurements ran on; the
  release a row runs is the image pin in `lib/vllm.env`, which currency reads.

## Class detection

`hosting_class` in `lib/hosting.sh` sets the class from the PCI vendor and device IDs a DRM card
reports under `/sys/class/drm/card*/device`: `0x10de:0x2e12`, the NVIDIA GB10, is `gb10`, and
`0x1002:0x1586`, the AMD Strix Halo, is `strix-halo`. It refuses a host matching neither.
`HOSTING_CLASS` overrides the probe and is checked against the same closed list. The function
exports `HOSTING_CLASS`, so the commands a call runs inherit the class and the host is probed once
per call. It replaces spike-model-engines' `vllm_flavor` (`host/vllm.sh` at `6ce3210`), which took
any host without AMD's vendor ID as CUDA; the IDs come from spike-hosting-upgrades' host reports,
gb10-1's at `26b6c37` and the Framework's at `12067db`.

## Replacing a model

Replacing a model runs `profile set`, `model pull`, and `engine update`, then commits the profile
(each runbook gives the commands). It is a kind of upgrade:
the `upgrades` task's convention and its `hosting-upgrades` skill will cover evaluating the
candidate (its card, its origin, a probe against the row's floors) before `profile set`. The
`embedding` task's replacement of the embedding model with `intfloat/multilingual-e5-large`, then
on the Framework beside audio, is the pattern: the card read, the pull and update, probes at the
context's edge, the sweep that sets the cap, the memory read, retrieval against the published
scores, a cell beside any row sharing the host, then pruning the old model, each a cell in
[its findings](../docs/findings/embedding.md). The `framework-2` task moved the row to framework-2
alone and re-measured it there on the LAN.

A read-only listing of the rows whose `measured_vllm` is older than the pin, the rows an upgrade
re-measures, is planned for `upgrades`; that task's plan names its verb.

## go-ai profiles

Planned for the `gateway` task: ai-hosting will publish each alias's go-ai profile as a JSON file
in go-ai's own field names, declaring the reasoning efforts the row refuses. Acceptance will run
go-ai's integration tier with them through `AI_<ROLE>_PROFILE`.

## What later tasks take from spike-model-hosting

The validator, `lib/profile.jq`, ports spike-model-hosting's `hosting/profile/profile.go`
(`Parse` and `Validate`) at `aac0764` to jq over vLLM rows. The source tables of the `agent`,
`vision`, and `audio` rows come from the spike's `devices/strix-halo/profile.toml` entries for
gpt-oss-120b, Gemma 4 26B-A4B, and Gemma 4 E4B, with each card's context moved to the row. The rest
of the spike's profile package is not carried: its Go code, llama.cpp's fields and templates, model
sets, the decode-ceiling fields, and the evaluation tooling. Two tasks take parts of it:

- **embedding**: the strix-halo runbook's embedding section states e5's `query: ` and
  `passage: ` prefixes (`hosting/profile/profile.go:340-343`).
- **architecture**: its "sizing a vLLM row" page takes the decode-ceiling method
  (`memory_bandwidth_gb_s`, `active_params_b`, `bits_per_weight`); its "reading a model card" page
  takes `docs/model-cards.md`'s first two sections, "What each value means" and "Why a model runs
  at its card's values", rewritten for a served checkpoint in place of a GGUF; and it states the
  rule that only a row whose checkpoint another publisher's card describes sets `sampling`.
