# Policy

The gates every candidate meets, how it is judged on the host before it serves a row, and the rule
that tunes a row once it does. A survey and a measure read this document and never write to it; when
one needs a value this document doesn't state, it stops and asks the architect. How the rules are
applied is in [the upgrade convention](upgrades.md).

## Model origin

No model of Chinese origin serves a row unless it is cleared, and a fine-tune takes its base's
origin. A model's origin is that of the entity that trained it; an entity based in, or controlled
from, the People's Republic of China, Hong Kong and Macau included, is of Chinese origin.

The rule is read at three levels, and a model of Chinese origin at any of them excludes the
candidate:

1. **The weights and their base chain**: the publisher of the checkpoint, every ancestor it was
   fine-tuned, quantized, or merged from, and every model merged into it. A quantization takes
   the origin of the weights it quantizes, not its quantizer's.
2. **Any distillation teacher**: a model whose generated outputs are the candidate's training
   targets, such as synthetic responses or data it learned to reproduce, or whose logits it was
   trained to match, read by its role in the publisher's own documents, whatever they call it. A
   teacher the documents leave unnamed passes only when they place it in the publisher's own
   pipeline. A model that only filtered, labeled, punctuated, or cleaned human data is not a
   teacher: that is dataset work, and not origin. So:
   - a card that names no teacher and no external generator passes this level;
   - a card that names synthetic data from an external generator it leaves unnamed is "origin
     unclear", as an unnamed teacher outside the publisher's pipeline is;
   - "relabeled" data is labeling, dataset work, so its relabeling model is not a teacher;
   - LLM-generated query-passage pairs for an embedding model are its training targets, so their
     generator is a teacher;
   - a base model's own teachers bind its fine-tunes, since a fine-tune takes its base's origin and
     the base's origin is read at all three levels.
3. **Each component in the inference path**: a vision or audio encoder, a projector, or the
   tokenizer, as the publisher ships it.

A candidate passes when its publisher is identified and its own documents establish its base chain
and its teachers, with no Chinese origin found at any level. A candidate whose chain can't be
established is held out as "origin unclear", with what was checked. The profile records the
outcome in the row's `source` table: the publisher and its `origin`, and the base model and its
`base_origin` for a checkpoint built on another publisher's
([classes/README.md](../classes/README.md#source)).

Only the three levels decide. A quantization's calibration data, the human data in a training mix
and the models that only prepared it, and conventions such as a chat template's or a tool-call
format's layout are not read as origin. Data a model generated for the candidate to reproduce is
not dataset work: its generator is a teacher, read at level 2.

### Clearance

The ban guards against covert behavior, such as a backdoor, that no current method can rule out
from a model's weights. Clearance keeps a path open should a model of Chinese origin far outstrip
other open weights, as soon as a government evaluator can vouch for that release.

A candidate that fails origin is admitted only when all of these hold:

- NIST's CAISSI (formerly CAISI) or the UK AI Security Institute (AISI) published an evaluation
  of that exact release: the weights' repository and commit;
- the evaluation assessed covert behavior or backdoors, and agent hijacking;
- it found the model at parity with the U.S. reference models it tested.

The architect then admits it, and the row's `source` table records the evaluation
([classes/README.md](../classes/README.md#source)). A candidate that fails origin with no such
evaluation is refused, "origin, no clearance". This section is revisited from the model security
proposals each survey makes ([the convention](upgrades.md#when-survey-runs)).

## Artifact integrity

The files a row loads must not run code when they are loaded.

- **Weights are safetensors.** vLLM reads the weight format from the files it loads, not from the
  repository's name: a `.bin` or `.pt` checkpoint is a pickle, which runs code on load, and fails.
  A repository that ships safetensors beside other exports, such as ONNX, passes on its
  safetensors, which vLLM prefers.
- **Repository code only from the accepted list.** A model that needs `--trust-remote-code`, so
  that vLLM runs Python shipped in its repository (a model class, a processor, or a tokenizer),
  fails unless that code is on the list below, at the revision the row would load. No row sets
  the flag today ([gb10](../classes/gb10/profile.toml),
  [strix-halo](../classes/strix-halo/profile.toml)), even where a card's sample command passes it.
- **The chat template.** vLLM renders the template the repository ships. For a checkpoint built
  on another publisher's model, the template is compared with the base's; one that adds text the
  model sees, such as a system prompt or instructions, fails.

**Accepted code.** The repository code the architect has reviewed and accepts, which only the
architect edits. Each entry is one line: `<repository>` at `<commit>`, `<file>`, accepted
`<date>`. A new revision is a new entry.

- None.

## Support and fit

Any quantization or format is eligible: one the publisher trained in, a post-training checkpoint,
or a community quantization, at any width. A candidate goes on to a screen when:

- **vLLM serves it**: vLLM at the pin serves its architecture, in the format its
  `quantization_config` names, through the role's interface
  ([the roles](../.claude/skills/hosting-upgrades/sources.md#roles));
- **it fits**: its weights fit the row's memory share, the host's memory pool at the row's current
  fraction.

## Judged on the host

Whether a candidate serves is settled by our own measurement on the host it would serve on, in the
candidate screen ([the convention](upgrades.md#measures-three-passes)), against the incumbent:
accuracy and capability first, then speed and efficiency, its throughput peak at the row's cap and
queue limit. It serves only when it fits the host's memory and compute, and gives accurate results
with acceptable performance within its concurrent session cap and queue limit.

A card's evals only rank which candidates to screen first; they never admit or refuse one.

The KV cache's dtype is a row's setting, not a checkpoint format, and the tuning rule below judges
it: the agent row's FP8 KV cache stands on an accuracy check against BF16, which its `flags_reason`
cites ([gb10 profile](../classes/gb10/profile.toml)).

## The tuning rule

A row is tuned for accuracy first, then for its throughput peak.

- **Accuracy first.** A setting that changes what the row returns, such as an image budget, the
  audio a request carries, or a cache's dtype, is set where the row's accuracy measure holds; a
  setting is never lowered below that for speed.
- **Then the throughput peak.** At those settings, the row's cap follows its throughput peak, the
  work it completes over time, not a request's latency. Each row's `cap_reason` in its class
  profile gives how, and cites the cell that sets it.
- **Latency sizes client timeouts only.** A request's latency is reported, and clients set their
  timeouts from it; it doesn't set a cap.
- **The agent keeps its floor.** The agent row's sessions are interactive, so it holds an
  inter-token latency median of 100 ms or less at its load target, and its cap is the most
  sessions at which it still does.
