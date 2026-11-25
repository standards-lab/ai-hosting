# Policy

The rules every candidate meets before it serves a row, and the rule that tunes a row once it
does. A survey and a measure read this document and never write to it; when one needs a value
this document doesn't state, it stops and asks the architect. How the rules are applied is in
[the upgrade convention](upgrades.md).

## Model origin

No model of Chinese origin serves a row, and a fine-tune takes its base's origin. A model's origin
is that of the entity that trained it; an entity based in, or controlled from, the People's
Republic of China, Hong Kong and Macau included, is of Chinese origin.

The rule is read at three levels, and a model of Chinese origin at any of them excludes the
candidate:

1. **The weights and their base chain**: the publisher of the checkpoint, every ancestor it was
   fine-tuned, quantized, or merged from, and every model merged into it. A quantization takes
   the origin of the weights it quantizes, not its quantizer's.
2. **Any distillation teacher**: a model whose outputs or logits the candidate was trained to
   reproduce, read by its role in the publisher's own documents, whatever they call it. A teacher
   the documents leave unnamed passes only when they place it in the publisher's own pipeline.
3. **Each component in the inference path**: a vision or audio encoder, a projector, or the
   tokenizer, as the publisher ships it.

A candidate passes when its publisher is identified and its own documents establish its base chain
and its teachers, with no Chinese origin found at any level. A candidate whose chain can't be
established is held out as "origin unclear", with what was checked. The profile records the
outcome in the row's `source` table: the publisher and its `origin`, and the base model and its
`base_origin` for a checkpoint built on another publisher's
([classes/README.md](../classes/README.md#source)).

Only the three levels decide. A quantization's calibration data, the datasets in a training mix,
and conventions such as a chat template's or a tool-call format's layout are not read as origin.

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

## Quantization floor

The floor is read from the checkpoint's own `quantization_config`, the format vLLM loads, not from
the repository's name. A checkpoint meets it by one of three paths.

1. **Formats the publisher trained in.** A model's native format, released by its publisher as
   the model itself, passes at any size. The agent row's `openai/gpt-oss-120b` ships its expert
   weights in MXFP4, OpenAI's own format for the model.
2. **A post-training checkpoint its publisher evaluated.** An NVFP4, FP8, or other post-training
   checkpoint passes when its card reports evals against the full-precision base and none falls
   more than about 1% below the base's score, relative ((base − quantized) / base). The vision
   row's `nvidia/Gemma-4-26B-A4B-NVFP4` passes this way: its card's largest loss is
   LiveCodeBench's, 80.50% to 79.80%, 0.87%, and two evals rose
   ([its card](https://huggingface.co/nvidia/Gemma-4-26B-A4B-NVFP4), "Evaluation Results", read
   2026-11-25).
3. **Everything else**: a community quantization, or a post-training checkpoint whose card gives
   no evals or a larger loss. It runs at FP8 weights or wider, never at a 4-bit format such as
   AWQ, GPTQ INT4, bitsandbytes, or an unevaluated NVFP4. Embedding models, audio models, and
   dense models under 8B parameters run at FP8 or wider by this path too.

Full-precision weights pass every path: BF16 or FP16 as published, or as vLLM casts a float32
checkpoint. The audio row's `google/gemma-4-E4B-it` serves its published BF16, and the embedding
row's `intfloat/multilingual-e5-large`, a float32 checkpoint, serves as float16
([e5-update](findings/embedding.md#e5-update)). A model's size is the parameters its card names as
effective.

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
