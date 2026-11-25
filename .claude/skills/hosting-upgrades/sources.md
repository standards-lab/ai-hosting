# Sources

Where a run reads each fact, and how it tiers what it reads. Every source is read fresh in the run
that cites it, and cited with its URL or command and its read time in UTC.

## Reading a source

- **WebFetch** reads pages and JSON: the Hugging Face API, model cards, raw files from
  `raw.githubusercontent.com`, and Docker Hub's tags API. Ask it for fields by name and figures
  verbatim.
- **WebSearch** finds what the list below doesn't hold; a found page is then read with WebFetch.
- **`gh`** reads GitHub: `gh release list` and `gh release view` for release notes,
  `gh search issues` and `gh search prs` for the tracker, and `gh issue view` and `gh pr view`
  with `--json state,comments` for one thread. A comment whose `authorAssociation` is `MEMBER`,
  `OWNER`, or `COLLABORATOR` is a maintainer's.
- **`gh api`** only when the reads above can't answer, since it asks each time.

## Tiers

- **Primary**: the vendor's or publisher's own release notes, documentation, model cards, and
  tracker, and a maintainer's comment. It settles what shipped and what is supported. A release
  note's "faster" is a claim, not a measurement.
- **Attributed benchmark**: a measurement that names its hardware, its vLLM version, and its
  method. Only this tier, or this project's own findings, supports a verify on a claimed gain.
- **Lead**: anything short of that. It names something to check, never a verdict alone.

A source whose tier is unclear is a pause, with lead as the default.

## vLLM

| What | Read | Notes |
|---|---|---|
| Releases | `gh release list -R vllm-project/vllm --limit 30`; `gh release view <tag> -R vllm-project/vllm` | The pin and the latest come from `mise run currency`; read every release after a row's `measured_vllm` up to the latest. Notes group changes by area, ROCm and CUDA among them, each citing its pull request. |
| Images | `https://hub.docker.com/v2/repositories/<repository>/tags?name=<tag>` | The repository per class is in [`lib/vllm.env`](../../../lib/vllm.env); `mise run currency` reports the digests the built images rest on. A release with no image for a class is no candidate on that class. |
| Engine arguments | `https://raw.githubusercontent.com/vllm-project/vllm/<tag>/vllm/engine/arg_utils.py` | Each flag's default and help at a tag, to read a flag a release renamed, deprecated, or re-defaulted. |
| Supported models | `https://raw.githubusercontent.com/vllm-project/vllm/<tag>/docs/models/supported_models.md` | Whether a candidate's architecture runs at the pin, and with what. |
| ROCm targets | `https://raw.githubusercontent.com/vllm-project/vllm/<tag>/docker/Dockerfile.rocm_base` | The `PYTORCH_ROCM_ARCH` list; gfx1151 must be in it for strix-halo. |
| Tracker | `gh search issues --repo vllm-project/vllm "<model or flag or gfx1151 or GB10>" --sort updated`; `gh search prs` likewise | A regression or a fix for a row's model, flag, or hardware. |

## Models

| What | Read | Notes |
|---|---|---|
| A publisher's newest | `https://huggingface.co/api/models?author=<org>&pipeline_tag=<tag>&sort=lastModified&limit=20` | The pipeline tag by role: `text-generation` for agent, `image-text-to-text` for vision, `automatic-speech-recognition` and `any-to-any` for audio, `feature-extraction` and `sentence-similarity` for embedding. Start from the publishers of the class profiles' rows and of their bases. |
| A model's record | `https://huggingface.co/api/models/<id>?expand[]=cardData&expand[]=safetensors&expand[]=config` | `cardData.base_model` for the base chain, the safetensors parameter count, and the config's architecture. |
| Its files | `https://huggingface.co/api/models/<id>/tree/main?expand=true` | Each file's name, size, and `securityFileStatus`: the artifact integrity gate reads that the weights are safetensors and no pickle loads. |
| Its config | `https://huggingface.co/<id>/raw/main/config.json` | `quantization_config`, the format vLLM loads, for the quantization floor; `auto_map`, which names repository code. |
| Its chat template | `chat_template.jinja`, else `tokenizer_config.json`'s `chat_template`, at the candidate and at its base | Compared for the policy's chat-template rule. |
| Its card | `https://huggingface.co/<id>` | Its evals against the base, its base and distillation sections, and the publisher's own documents it links. |
| A publisher | `https://huggingface.co/api/organizations/<org>/overview`, then the publisher's own domain | Who the publisher is, and where it is based. |
