# Host-class profiles

Each host class has one profile, which lists every row the class can serve and is each row's one
home. The schema is TOML, and `mise.toml` gains a pinned TOML reader for the hosts, which
currency reads. The `hosts` task builds the profiles and the `profile` group
([the `hosting` suite](hosting-suite.md)).

## The profile

**A row** is one alias, `agent`, `vision`, `audio`, or `embedding`; the spike's role `chat` is
`agent`. Its typed fields:

- alias, model repository, context (at most the card's context), cap, GPU memory fraction, queue
  limit, container, port, and an optional image;
- provenance;
- the reasons for its cap, context, and fraction, each stating the measurement behind the present
  value and naming a document in ai-hosting, never a goal record or a value the row doesn't run
  at;
- the vLLM release its measurement ran on;
- its load target, with the source of its measurement;
- sampling, only where the checkpoint isn't its card publisher's, with the card's values and
  their source, passed as a generation-config override; the rule's text goes to the
  `architecture` task;
- `dims`, on an embedding row.

The port's home is the profile; the gateway derives each alias's port from it.

**Invariants.** Aliases, ports, and containers are unique in the profile; a queue limit, where
set, is twice the cap; the fractions of the rows that stand together on a host sum to at most 1.

**Free flags** pass through with one stated reason. The validator refuses the flags the typed
fields and the suite own: `--host`, `--port`, `--served-model-name`, `--max-num-seqs`,
`--max-model-len`, `--gpu-memory-utilization`, and `--max-num-queued-reqs`.

**No host identity.** A profile names no host; the validator refuses an address or a MagicDNS
name anywhere in it.

**Which rows a host stands on** is the aliases given to `hosting engine install`, recorded on the
host outside git; `engine update` and `engine uninstall` with no alias read that record.

**The vLLM release** is the image pin currency reads; a profile holds no engine version. A
read-only listing of the rows whose measurement ran on a release older than the pin, the rows an
upgrade re-measures, is `upgrades`'; its verb is open at that task's plan.

**Replacing a model.** `profile set` → `model pull` → `engine update` → commit. Replacing a model
is an upgrade kind: `upgrades`' convention and its `hosting-upgrades` skill cover evaluating the
candidate (its card, its provenance, a probe against the row's floors) before `profile set`. The
embedding task's replacement is the first and sets the pattern.

**go-ai profiles.** ai-hosting publishes each alias's go-ai profile as a JSON file in go-ai's own
field names, declaring the reasoning efforts the row refuses (gateway). Acceptance runs go-ai's
integration tier with them through `AI_<ROLE>_PROFILE`.

## From spike-model-hosting's profile package

The package, at `aac0764`, carries as a documented TOML schema and a shell validator and
renderer, the `hosting profile` group; no Go carries. The schema document is the contract
experiment.admin's Go CLI implements.

| Part in ai-hosting | Source | Task |
| --- | --- | --- |
| The validation discipline: closed keys, every error at once by key path, every command that reads a profile validates it first, a value placed on a command line refused if it holds whitespace or shell syntax | `hosting/profile/profile.go:420-450`, `:495-511`; `hosting/profile/presets.go:37-39`; `hosting/profile/unit.go:38-43` | hosts |
| Provenance: publisher, origin, licence, card URL, and `origin_reason`; origin a closed list of country names, a restricted origin without `origin_reason` refused, a fine-tune's base origin recorded | `hosting/profile/profile.go:274-292`, `:574-582`; `docs/pool.md:55-58` | hosts; its first use, embedding |
| The provenance entries of gpt-oss-120b, Gemma 4 26B-A4B, and Gemma 4 E4B | `devices/strix-halo/profile.toml:69-79`, `:118-128`, `:181-194` | hosts |
| Required reasons, beside a row's cap, context, fraction, and free flags | `hosting/profile/profile.go:588-590`, `:629-631` | hosts |
| `dims`, for an embedding row | `hosting/profile/profile.go:326-329`, `:609-614` | embedding |
| Where the model store is mounted: the spike held it per machine, in its `Host` struct; the class profile holds it | `hosting/profile/profile.go:413-419` | hosts |
| One directory per host class, holding its profile beside its runbook | `hosting/profile/locate.go:12-17` | hosts |
| The check validates every committed profile, and fixture profiles: one valid, one per refusal, each with the error it must produce | `hosting/profile/profile_test.go`, `hosting/profile/testdata/README.md` | hosts |

These drop:

- all the Go code: `go.mod`, `go.sum`, and `github.com/BurntSushi/toml`; `hosting/profile/*.go`
  and `hosting/cmd/profile/main.go`, the dispatcher, with its `engines`, `set`, and `render`
  subcommands;
- `hosting/profile/edit.go`'s evaluation overrides, `Override`, and `PresetSection`
  (`hosting/profile/presets.go:73-131`); a narrow `profile set` is written fresh;
- `hosting/profile/locate.go`, since the suite resolves the clone from the command's real path
  and the class from detection;
- llama.cpp's fields and templates: `engine`, `kv`, `defaults`, `mtmd_batch_max_tokens`, the
  router-tag rule, `hosting/profile/presets.ini.tmpl`, `hosting/profile/unit.service.tmpl`,
  `RenderPresets`, and `RenderUnit`;
- `sets`, `startup`, `MaxSetModels`, `SetRoles`, and a model's `roles`;
- `memory_budget` and the decode-ceiling fields `memory_bandwidth_gb_s`, `active_params_b`, and
  `bits_per_weight`; the decode-ceiling method goes to the architecture task's "sizing a vLLM
  row" page;
- `engine.min_build` (`hosting/profile/profile.go:158-167`) and the `engines` subcommand
  (`hosting/cmd/profile/main.go:110-148`); the `hosting engine` group is unaffected;
- `sampling.reasoning` and `consumers`;
- `prompts` and the ASR rule (`hosting/profile/profile.go:340-343`, `:733-735`); the e5 prefix
  goes to the embedding row's runbook (embedding);
- the unit, the `bind` field, and `Host`'s service user;
- the golden files: `skeleton.ini`, `strix-halo.ini`, `strix-halo.service`, and
  `unified-96gb.ini` in `hosting/profile/testdata/`;
- the Strix Halo instance's values, `devices/strix-halo/profile.toml`, apart from the three
  provenance entries;
- `docs/pool.md`; its fine-tune origin rule is the provenance's base origin.

The rest of spike-model-hosting is not carried: `hosting/swap`, `hosting/router`,
`hosting/probe`, and `hosting/cmd/swap` are llama.cpp's, and `evaluation/` and
`devices/strix-halo/*`, apart from the three provenance entries above, served the spike's
evaluation.

`docs/model-cards.md`'s first two sections, "What each value means" and "Why a model runs at its
card's values", go to the architecture task's "reading a model card" page, rewritten for a served
checkpoint in place of a GGUF.

## Open at the hosts plan

- Where the host records its installed aliases.
- Which TOML reader `mise.toml` pins.
- The profiles' on-disk layout inside the one directory per class.
- The restricted-origin list, citing `standards-lab/context/ai-strategy.md`, "Constraint: model
  origin".
- Whether the vision row needs a sampling override.
