# go-ai profiles

Each `<alias>.json` here is the [go-ai](https://github.com/standards-lab/go-ai) profile of one
alias the gateway serves: the JSON object that go-ai's `AI_<ROLE>_PROFILE` and `infer`'s
`--profile` take. Its members are keyed by go-ai's format names, `completions`, `messages`, and
`responses`, and each holds that format's options under go-ai's own field names
([go-ai's integration tier](https://github.com/standards-lab/go-ai/blob/main/integration/doc.go)).
A profile declares only what the alias's row, its vLLM, refuses, and only what a recording or a run
backs; `{}` is the spec in every format.

`scripts/lint-go-ai-profiles.sh`, in the check, refuses a file that isn't an object of go-ai's
formats, a file naming no class profile's alias, and an alias with no file. The `acceptance` task
is to run go-ai's integration tier with these profiles through `AI_<ROLE>_PROFILE`.

## agent

[`agent.json`](agent.json) describes gpt-oss-120b on vLLM 0.34.0. Each field is backed by a
recording of that row in go-ai's `format/<format>/testdata/vllm-0.34.0`, whose README describes
each recording
([completions](https://github.com/standards-lab/go-ai/tree/main/format/completions/testdata/vllm-0.34.0),
[messages](https://github.com/standards-lab/go-ai/tree/main/format/messages/testdata/vllm-0.34.0),
[responses](https://github.com/standards-lab/go-ai/tree/main/format/responses/testdata/vllm-0.34.0)):

| Format | Field | Recordings |
| --- | --- | --- |
| `completions` | `refused_efforts`: `none`, `minimal`, `xhigh`, `max` | `effort_none.json`, `effort_minimal.json`, `effort_xhigh.json`, and `effort_max.json`, each a 400 |
| `completions` | `no_allowed_tools` | `allowed_tools.json`, a 400 on `tool_choice.function` |
| `responses` | `refused_efforts`: `none`, `xhigh` | `effort_none.json` and `effort_xhigh.json`, each a 400 |
| `responses` | `no_allowed_tools` | `allowed_tools.json`, a 200 that calls a tool outside the allowed set |
| `responses` | `resend_reasoning_text` | `reasoning_text.json`, a reasoning item of text with null `encrypted_content` |
| `messages` | `refused_efforts`: `none`, `xhigh`, `max` | `effort_none.json`, a 200 that reasons with thinking disabled; `effort_xhigh.json` and `effort_max.json`, each a 400 |

spike-model-gateway's rows-up tiers ran go-ai with this profile through the gateway
([answer.md](https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/findings/answer.md),
"Step 2", at `2f2e8c1`).

## vision, audio, and embedding

[`vision.json`](vision.json), [`audio.json`](audio.json), and
[`embedding.json`](embedding.json) are `{}`, the spec. In the same tiers, vision passed reasoning
efforts `none` and `low` in every format with no profile.

## What the profiles leave out

- **Unrecorded gaps.** No refusal of the vision, audio, or embedding row is recorded, so their
  profiles declare none.
- **The Azure deployments' refusals.** A profile never declares what an alias's Azure overflow
  deployment refuses; the [gateway document](../docs/gateway.md#overflow) lists what each alias
  gives up on overflow.
