# Host-class profiles

The schema of a host-class profile: what each key means and what `hosting profile validate`
refuses. It is the contract every reader of a profile implements, the `hosting` suite's shell
commands and any later tool. Why the profiles take this shape is in
[host-classes.md](../context/host-classes.md).

## Layout

`classes/` holds one directory per host class, named for it: `gb10` and `strix-halo`, the closed
list the suite's class detection shares. Each holds exactly two files:

- `profile.toml`, the class's profile: every row a host of the class can serve, and each row's one
  home;
- `runbook.md`, the class's runbook.

A profile names no host. Which of its rows a host stands on is the aliases given to
`hosting engine install`, recorded on the host outside git.

Profiles are TOML, read and written with mikefarah yq, the reader `mise.toml` pins, and committed
in the format yq writes in place, so `hosting profile set` changes only the lines it edits. A
profile's only comment is its header, which describes it and links this document.

## The profile's keys

| Key | Required | Meaning |
| --- | --- | --- |
| `store` | yes | The absolute path of the class's model store, the Hugging Face cache every row's container mounts. |
| `rows` | yes | The rows, an array of tables, at least one. |

## A row's keys

Each `[[rows]]` table is one vLLM container serving one model under its alias.

| Key | Required | Meaning | `vllm serve` flag |
| --- | --- | --- | --- |
| `alias` | yes | The name the row serves under: `agent`, `vision`, `audio`, or `embedding`. The gateway routes the alias to the row. | `--served-model-name` |
| `model` | yes | The Hugging Face repository of the checkpoint served. | the model argument |
| `container` | yes | The container's name. | |
| `port` | yes | The port the row publishes on the host's tailnet address and listens on, 1 to 65535. The gateway derives each alias's port from it. | `--port` |
| `image` | no | An image the host builds and serves in place of the class's vLLM image, at the pinned release's tag. | |
| `context` | yes | The tokens a sequence may hold, a positive integer at most `card_context`. | `--max-model-len` |
| `card_context` | yes | The longest context the model's card states, or its config's `max_position_embeddings` where the card states none. | |
| `context_reason` | yes | Why the row runs at `context`. | |
| `cap` | yes | The sequences the row serves at once, a positive integer. | `--max-num-seqs` |
| `cap_reason` | yes | Why the row runs at `cap`. | |
| `queue_limit` | no | The requests the row admits in flight, running and waiting, before it answers 503: a whole number of at least `cap`, twice `cap` unless `queue_limit_reason` says why not. Without it the row queues without bound. | `--max-num-queued-reqs` |
| `queue_limit_reason` | when `queue_limit` isn't twice `cap` | Why the row's queue limit isn't twice its cap. Only such a row has it. | |
| `fraction` | yes | The share of the GPU's memory the row reserves, over 0 and at most 1. | `--gpu-memory-utilization` |
| `fraction_reason` | yes | Why the row reserves `fraction`. | |
| `dims` | on an embedding row | The embedding's width, as the card states it. Only an `embedding` row has it. | |
| `flags` | no | Free flags: `vllm serve` arguments the schema doesn't type, one word an element, passed as given after the typed ones. | as given |
| `flags_reason` | with `flags` | Why the row sets its free flags. | |
| `measured_vllm` | yes | The vLLM release the row's measurements ran on, such as `v0.33.0`. The vLLM the row runs is the suite's image pin; a row whose release is older than the pin is one an upgrade re-measures. | |
| `load` | yes | The row's load target, a table. | |
| `source` | yes | The served checkpoint's source: its publisher, origin, and licence, a table. | |
| `sampling` | no | A sampling override, a table. | `--override-generation-config` |

Each reason states the measurement behind the present value and names the document that records
it. It never names a goal record, or a value the row doesn't run at.

### `load`

| Key | Required | Meaning |
| --- | --- | --- |
| `target` | yes | The load the row is sized to hold, such as `4 sessions`. |
| `source` | yes | The measurement at the target, and the document that records it. |

### `source`

| Key | Required | Meaning |
| --- | --- | --- |
| `publisher` | yes | The organization that published the served checkpoint. |
| `origin` | yes | The publisher's country, by its short English name, such as `United States`. |
| `licence` | yes | The licence the checkpoint is released under, as its card states it, such as `Apache-2.0`. |
| `card_url` | yes | The served checkpoint's model card. |
| `base_model` | with `base_origin` | The repository of the model another publisher's checkpoint derives from, by quantization or fine-tuning, whose card describes it. |
| `base_origin` | with `base_model` | The base model's publisher's country. A fine-tune takes its base's origin. |
| `origin_reason` | when `origin` or `base_origin` is `China` | Why the model was chosen: the alternatives that don't serve. Set on no other model. |
| `generation_config` | with `base_model`, unless the row sets `sampling` | That the checkpoint's `generation_config.json` carries the base model card's sampling, which vLLM applies by default. |

The restricted origin is China alone (`standards-lab/context/ai-strategy.md`, "Constraint: model
origin").

### `sampling`

Only a row whose checkpoint another publisher's card describes, one with `base_model`, sets it,
and only when the checkpoint's generation config doesn't carry the card's values. It holds the
card's values, passed as vLLM's generation-config override.

| Key | Required | Meaning |
| --- | --- | --- |
| `source` | yes | The card the values come from. |
| `temperature`, `top_p`, `top_k`, `min_p` | at least one | The card's value, a number. |

## What `hosting profile validate` refuses

`hosting profile validate` with no argument checks the layout above and validates every class's
profile; given files, it validates each. The check runs it with no argument. Every command that
reads a profile validates it first. It reports every error at once, one line each,
`hosting: <file>: <key path>: <message>`, with the key path in TOML's dotted form, such as
`rows[1].source.origin_reason`, and exits 1 if it finds any. It refuses:

- a key this document doesn't define, in any table;
- a required key that is absent, or a value of the wrong kind;
- an alias outside the four;
- an alias, port, or container that an earlier row already has;
- a fraction over 1;
- a queue limit under the cap, one that isn't twice the cap without `queue_limit_reason`, and
  `queue_limit_reason` on a row whose queue limit is twice the cap or that has none;
- a context over the card's;
- a missing reason: for the cap, context, or fraction, or for free flags;
- a free flag that a typed field or the suite sets: `--host`, `--port`, `--served-model-name`,
  `--max-num-seqs`, `--max-model-len`, `--gpu-memory-utilization`, `--max-num-queued-reqs`,
  `--model`, and `--override-generation-config`;
- a value a command line carries, `store`, `model`, `container`, `image`, `base_model`, or a free
  flag, that holds whitespace or shell syntax;
- an IP address or a MagicDNS name in any value;
- an origin or base origin of China without `origin_reason`, and `origin_reason` on any other;
- `dims` on a row other than `embedding`, or an `embedding` row without it;
- a `base_model` without `base_origin` or the other way round, and one without `generation_config`
  or `sampling`;
- `sampling` on a row without `base_model`, or without its source or a value.

The validator doesn't check the sum of the fractions of the rows standing on one host:
`hosting engine install` does, over the host's recorded aliases and the ones it installs.
