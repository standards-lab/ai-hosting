# Audio findings

The measurements behind the strix-halo profile's audio row, which serves `google/gemma-4-E4B-it`
alone on its host. Each section is one cell: its command, its time in UTC, its figures, and the
tool versions it ran on. The profile's reasons cite the cells by their section; the row's settings
live in [the profile](../../classes/strix-halo/profile.toml).

## audio-8

The row alone on `framework`, as the profile renders it: cap 8 (`--max-num-seqs 8`,
`--max-num-queued-reqs 16`), fraction 0.18, context 8,192, on vLLM v0.34.0 in the image
`ai-hosting/vllm-openai-rocm-audio:v0.34.0`. The client is the laptop on the LAN, running
GuideLLM 0.8.1 in the bench environment ([bench/README.md](../../bench/README.md)) with Gemma 4
E4B's own tokenizer. `tailscale ping framework`, right before each run, answered direct, 1 ms.

At 8 streams with [`bench/audio-8.yaml`](../../bench/audio-8.yaml), then at 4 with
[`bench/audio.yaml`](../../bench/audio.yaml) writing `.state/bench/audio-4-framework-lan.json`:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/audio-8.yaml \
  --backend kind=openai_http,model=audio \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it \
  --output kind=json,path=.state/bench/audio-8-framework-lan.json
```

`levels.jq` with `--arg purpose audio`:

| Streams | Start, UTC | ok/err/inc | req/s | TTFT median ms | Latency median s | Latency p90 s | Prompt tok/s | RTFx median | RTFx min | RTFx ≥ 5 | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 8 | 2026-11-24T18:55:52Z | 1556/0/7 | 6.479 | 198 | 1.08 | 1.92 | 1,285 | 5.32 | 2.72 | 955/1556 | 240 | meets |
| 4 | 2026-11-24T19:00:07Z | 876/0/0 | 3.728 | 168 | 0.93 | 1.73 | 738 | 6.10 | 3.46 | 727/876 | 235 | meets |

The row's `/metrics` after both runs: 3,130 requests finished, 0 preemptions, and the KV cache
never full.

- **Cap 8 meets audio's floor**: an RTFx median of 5.32, over the floor of 5, at 1.74 times the
  4-stream throughput. Beside granite, the earlier embedding row, the 8-stream cell held 4.94
  (spike-model-layout `docs/findings/vllm-layout.md`, F.5).
- At 4 streams the median is 6.10, so the fourth to eighth streams cost 0.78 of RTFx median and
  30 ms of TTFT median.

### Over the relay

An earlier run, 2026-11-24T16:35:49Z, the same command at 8 streams writing
`.state/bench/audio-8-framework.json`, from the laptop on a hard-NAT network: `tailscale ping`
answered via `DERP(iad)`, 56 to 61 ms, with "direct connection not established". It finished
697/2/7 requests, 2.904 req/s, TTFT median 997 ms, RTFx median 2.82, missing the floor, with no
preemption. Both errors were GuideLLM's `WriteTimeout`: its write timeout is fixed at 5 s
(`FALLBACK_TIMEOUT` in `guidellm/backends/openai/common.py`). That run measured the path, not the
row, so bench cells run from a LAN client; success off the LAN belongs to the `gateway` and
`acceptance` tasks.
