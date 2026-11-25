# Sources

Where a run reads each fact, and how it tiers what it reads. Every source is read fresh in the run
that cites it, and cited with its URL or command and its read time in UTC.

## Reading a source

- **`curl -s <url> | jq`** reads JSON and raw files: the Hugging Face API, raw files from
  `raw.githubusercontent.com`, Docker Hub's tags API, the distributions' package records, and a feed
  or file CAISSI's or UK AISI's site serves. It takes fields by name and figures verbatim, where a
  summary would paraphrase them. The URL follows `-s` unquoted, and a query goes after it as
  `-G --data-urlencode <name>=<value>` arguments, so
  [the setup rules](setup.md#the-permission-check) match the command.
- **WebFetch** reads pages: model cards, the publishers' documents, and the distributions' notes.
  Ask it for figures verbatim.
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
| Releases | `gh release list --repo vllm-project/vllm --limit 30`; `gh release view <tag> --repo vllm-project/vllm` | The latest release is the newest listed; the pin is `VLLM_RELEASE` in [`lib/vllm.env`](../../../lib/vllm.env). Read every release after a row's `measured_vllm` through the latest. Notes group changes by area, ROCm and CUDA among them, each citing its pull request. |
| Images | `curl -s https://hub.docker.com/v2/repositories/<repository>/tags/<tag> \| jq '{digest, last_updated, images: [.images[].architecture]}'` | The repository per class is in [`lib/vllm.env`](../../../lib/vllm.env); `mise run currency` reports the digests the built images rest on, and a stock row's digest is compared with `.digest` ([survey.md](survey.md#3-the-items)). A release with no image for a class is no candidate on that class. |
| Engine arguments | `https://raw.githubusercontent.com/vllm-project/vllm/<tag>/vllm/engine/arg_utils.py` | Each flag's default and help at a tag, to read a flag a release renamed, deprecated, or re-defaulted. |
| Supported models | `https://raw.githubusercontent.com/vllm-project/vllm/<tag>/docs/models/supported_models.md`; for embedding, `https://raw.githubusercontent.com/vllm-project/vllm/<tag>/docs/models/pooling_models/embed.md` | Whether a candidate's architecture runs at the pin, and with what. Support a page doesn't list yet can show in a release's notes or a merged pull request, which the tracker finds. |
| ROCm targets | `https://raw.githubusercontent.com/vllm-project/vllm/<tag>/docker/Dockerfile.rocm_base` | The `PYTORCH_ROCM_ARCH` list; gfx1151 must be in it for strix-halo. |
| Tracker | `gh search issues --repo vllm-project/vllm "<model or flag or gfx1151 or GB10>" --sort updated`; `gh search prs` likewise | A regression or a fix for a row's model, flag, or hardware. |

## Models

| What | Read | Notes |
|---|---|---|
| A publisher's newest | `curl -s https://huggingface.co/api/models -G --data-urlencode author=<org> --data-urlencode sort=createdAt --data-urlencode direction=-1 --data-urlencode limit=50 \| jq -r '.[] \| [.id, .pipeline_tag // "untagged", .createdAt] \| @tsv'` | No `pipeline_tag` filter, so untagged repositories list too; then classify each by its tag: `text-generation` for agent, `image-text-to-text` and `any-to-any` for vision, `automatic-speech-recognition` and `any-to-any` for audio, `feature-extraction` and `sentence-similarity` for embedding, and an untagged one by its config's architecture. Start from the publishers of the class profiles' rows and of their bases. |
| A model's record | `https://huggingface.co/api/models/<id>?expand[]=cardData&expand[]=safetensors&expand[]=config` | `cardData.base_model` for the base chain, the safetensors parameter count, and the config's architecture. |
| Its files | Sizes: `curl -s https://huggingface.co/api/models/<id>/tree/main -G --data-urlencode recursive=true \| jq '.[] \| {path, size}'`, every file in one call. Scan status: the same with `--data-urlencode expand=true` added, which gives each file's `securityFileStatus.status` but pages 50 files a call; with `-D <scratch>/headers`, the `Link` header's `rel="next"` URL is the next page. | Every file in every directory: the artifact integrity gate reads that the weights are safetensors and no pickle loads. |
| Its config | `https://huggingface.co/<id>/raw/main/config.json` | `quantization_config`, the format vLLM loads, for vLLM's support; `auto_map`, which names repository code. |
| Its chat template | `chat_template.jinja`, else `tokenizer_config.json`'s `chat_template`, at the candidate and at its base | Compared for the policy's chat-template rule. |
| Its card | `https://huggingface.co/<id>` | Its evals, which rank candidates for a screen and whether it reports a gain over the incumbent; its base and distillation sections; and the publisher's own documents it links. |
| A publisher | `https://huggingface.co/api/organizations/<org>/overview`, then the publisher's own domain | Who the publisher is, and where it is based. |

## Roles

The interface a candidate serves its role through, which the vLLM support gate reads: vLLM must
serve the candidate's architecture through it at the pin.

| Role | Interface |
|---|---|
| agent | chat completions with tools |
| vision | chat completions with images |
| audio | chat completions with audio input, as [audio-probe](../../../docs/findings/audio.md#audio-probe) sends it; a transcription-only or realtime-only model fails |
| embedding | `/v1/embeddings` |

## Model security

What survey's model security item reads, and where a candidate of Chinese origin's clearance is
sought ([the policy](../../../docs/policy.md#clearance)). Both are primary for what the agency
published.

| What | Read | Notes |
|---|---|---|
| NIST CAISSI | `https://www.nist.gov/caissi`, and the publications and news it links; `/caisi` only redirects there, which `curl -s` doesn't follow | The Center for Advancing Innovation and Standards for Super Intelligence, formerly the Center for AI Standards and Innovation (CAISI): its evaluations of models, and its guidance and standards work. |
| UK AISI | `https://www.aisi.gov.uk/`, and the research and work it links | The AI Security Institute's evaluations and research. |
| Detection methods | WebSearch for backdoor, sleeper-agent, and covert-behavior detection in model weights since the last report, each found page read with WebFetch | A paper or a standard is a lead until an agency or the publisher's own evaluation applies it. |

## Distribution packages

The notes for a host's pending packages. Packages may be read and cited by repository and by
security status, a group to a line, rather than one by one.

| Distribution | Read | Notes |
|---|---|---|
| Ubuntu (the gb10 hosts' DGX OS) | `https://changelogs.ubuntu.com/changelogs/pool/<component>/<prefix>/<source>/<source>_<version>/changelog`; `curl -s https://ubuntu.com/security/notices.json -G --data-urlencode details=<source> --data-urlencode limit=5 \| jq '.notices[] \| {id, title, published}'` | A package's changelog, and the security notices (USNs) that name it, both by the source package the probe prints beside each update, never the binary package's name. `apt list --upgradable` gives the repository, `-security` among them. |
| Arch (the strix-halo hosts' Omarchy) | `curl -s https://archlinux.org/packages/search/json/ -G --data-urlencode name=<package> \| jq '.results[] \| {repo, pkgver, pkgrel, last_update}'`; `https://archlinux.org/packages/<repo>/<arch>/<package>/` | A package's version and repository, and its page's upstream link and changes. |
