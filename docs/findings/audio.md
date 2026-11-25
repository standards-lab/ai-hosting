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

## audio-probe

Preliminary. The row alone on `framework` as the profile rendered it at audio-8's settings: cap 8,
queue limit 16, fraction 0.18, context 8,192, on vLLM v0.34.0 in the image
`ai-hosting/vllm-openai-rocm-audio:v0.34.0`. Its start, 2026-11-25T00:11:08Z, read the 0.18 back
as 20.16 GiB of the GPU's 112.0, its weights took 15.22 GiB, and its KV cache held 80,401 tokens,
9.81 requests of 8,192.

Each of the four clips `bench/audio-clips.sh probe` writes went once, from the laptop on the LAN
(`tailscale ping framework` direct, 1 ms), with no other load, at 2026-11-25T15:24:52Z: the
scenarios' transcription prompt, then the clip as a base64 WAV, as GuideLLM orders them, to
`/v1/chat/completions` with `max_tokens` 1,024 and the model's default sampling. A text-only
request with the same prompt took 31 prompt tokens; a clip's audio tokens are its prompt tokens
less those 31. The transcript is scored against the clip's reference `.txt` by difflib's ratio
over lower-cased words, with punctuation and apostrophes dropped and "mr" read as "mister", and by
whether the reference's last five words appear in it.

| Clip | Audio s | Status | Prompt tokens | Audio tokens | Audio tokens / s | Completion tokens | Finish | Latency s | Word ratio | Reaches reference word | Last 5 words |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 10s | 9.90 | 200 | 281 | 250 | 25.25 | 30 | stop | 1.41 | 0.958 | 24 of 24 | yes |
| 30s | 29.40 | 200 | 768 | 737 | 25.07 | 81 | stop | 3.75 | 0.896 | 68 of 68 | yes |
| 60s | 56.60 | 200 | 783 | 752 | 13.29 | 86 | stop | 4.04 | 0.676 | 72 of 134 | no |
| 120s | 115.36 | 200 | 783 | 752 | 6.52 | 85 | stop | 4.18 | 0.430 | 75 of 269 | no |

- **Audio past 30 s is dropped without an error.** The row takes 25 audio tokens a second up to
  30 s, and 752 audio tokens, 30 s, for any longer clip. The 60 s and 120 s clips each answered
  200, finished on `stop` well under `max_tokens`, and transcribed only their first 30 s: the 60 s
  transcript stops at "linell's pictures are a sort of", 72 of the reference's 134 words. The
  failure starts past 29.40 s and by 56.60 s, and a client that needs a longer recording
  transcribed sends it in windows of 30 s or less.
- **Up to 30 s the transcript is whole.** The 10 s and 30 s transcripts reach the reference's last
  word. Their misses are spellings of names and compounds ("linell's", "upguards", "burket",
  "callier"). No reply looped, refused, or answered in another language.

The replies are the session's, outside the repository.
