# Audio findings

The measurements behind the strix-halo profile's audio row, which serves `google/gemma-4-E4B-it`
alone on its host. Each section is one cell: its command, its time in UTC, its figures, and the
tool versions it ran on. The profile's reasons cite the cells by their section; the row's settings
live in [the profile](../../classes/strix-halo/profile.toml).

The row transcribes by chat completions, the clip as input with the transcription instruction, as
every cell here sends it; it serves no `/v1/audio/transcriptions` or `/v1/audio/translations`,
each answering 404 ([client-tiers](gateway.md#client-tiers)).

Each table's Floor and RTFx ≥ 5 columns, and "the floor" below, are `levels.jq`'s audio verdict,
an RTFx median of at least 5. The row's cap follows its throughput peak instead, as the profile's
`cap_reason` says, and the cells report RTFx beside it.

Every cell but [layout](#layout) ran the row alone on its host. The standing layout cell ran it
beside the other rows, on docinfer's windows, and it matched [audio-real-30s](#audio-real-30s)'s
row alone; the LibriSpeech cells, [audio-capacity-short](#audio-capacity-short) and
[audio-capacity-30s](#audio-capacity-30s), no longer set the cap.

## audio-8

The row alone on `framework` at its earlier setting: cap 8 (`--max-num-seqs 8`,
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

The scenarios cycle the same 73 clips, and the row's caches weren't read, so these figures may
hold the cache reuse that [audio-capacity-short](#audio-capacity-short) measured.

- **8 streams meet the floor**: an RTFx median of 5.32, over 5, at 1.74 times the
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
row, so bench cells run from a LAN client. Off the LAN stays out: the gateway serves tailnet peers
on their direct path, with no relay ([gateway decisions](../gateway.md#decisions)).

## audio-probe

The row alone on `framework` at
[audio-8](#audio-8)'s setting: cap 8, queue limit 16, fraction 0.18, context 8,192, on vLLM v0.34.0
in the image `ai-hosting/vllm-openai-rocm-audio:v0.34.0`. Its start, 2026-11-25T00:11:08Z, read the
0.18 back as 20.16 GiB of the GPU's 112.0, its weights took 15.22 GiB, and its KV cache held 80,401
tokens, 9.81 requests of 8,192.

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
  30 s, and 752 audio tokens for any longer clip: 750, the card's 30 s at 40 ms a token
  (`audio_seq_length` 750 in its `processor_config.json`), with the begin and end audio tokens.
  The card says so: "Audio supports a maximum length of 30 seconds"
  ([Gemma 4 E4B's card](https://huggingface.co/google/gemma-4-E4B-it), section 7). vLLM cuts the
  audio to that length and logs it instead of refusing the request: the 60 s clip, sent again at
  2026-11-25T16:13:20Z on the interim row ([audio-capacity-short](#audio-capacity-short)), took the
  same 783 prompt tokens and logged `Audio duration exceeds max: 56.600000 > 30.000000 seconds`.
  The probe's own log went with that container, so it was not read. The 60 s and 120 s clips each
  answered 200, finished on `stop` well under `max_tokens`, and transcribed only their first 30 s:
  the 60 s transcript stops at "linell's pictures are a sort of", 72 of the reference's 134 words.
  The probe places the cut past 29.40 s and by 56.60 s. A client that needs a longer recording
  transcribed sends it in windows of 30 s or less.
- **Up to 30 s the transcript is whole.** The 10 s and 30 s transcripts reach the reference's last
  word. Their misses are spellings of names and compounds ("linell's", "upguards", "burket",
  "callier"). No reply looped, refused, or answered in another language.

The replies are the session's, outside the repository.

## audio-capacity-short

The row alone on `framework` at the setting both sweeps ran at: cap 32
(`--max-num-seqs 32`, `--max-num-queued-reqs 64`), fraction 0.28, context 8,192, on vLLM v0.34.0 in
the image `ai-hosting/vllm-openai-rocm-audio:v0.34.0`. Its start, `hosting engine update audio` at
2026-11-25T15:33:11Z, read the 0.28 back as 31.36 GiB of the GPU's 112.0; its weights took 15.22
GiB, and its KV cache held 372,696 tokens, 45.50 requests of 8,192, against the 262,144 the fraction
was sized for ([audio-probe](#audio-probe)). Sampled every 10 s over ssh through the start, the
host's lowest MemAvailable was 80.79 GiB and its lowest GTT available 81.50 GiB, against the
Framework's floors of 12.5 and 11.2 (spike-model-layout `docs/findings/vllm-layout.md`, "Reading the
figures").

The client is the laptop on the LAN, GuideLLM 0.8.1 in the bench environment with Gemma 4 E4B's
tokenizer; `tailscale ping framework` answered direct, 1 ms, before each run. The requests are the
rows `bench/audio-clips.sh scenarios` writes, each with its own audio
([bench/README.md](../../bench/README.md)).

**The caches in one run.** [`bench/audio-capacity.yaml`](../../bench/audio-capacity.yaml) as
committed, its six levels in one run from 2026-11-25T15:35:59Z, each level reading the rows from
the first: of 4,530 requests' audio, 3,346 hit the multimodal cache, 73.9%, and of 898,753 prompt
tokens, 454,016 hit the prefix cache, 50.5% (`vllm:mm_cache_*_total` and
`vllm:prefix_cache_*_total` from 0 after the start). It reached 12.800 requests a second at 32
streams and an RTFx median of 4.67 at 8. Those are the earlier levels' requests served again from
the caches, so the cell below runs each level on rows no other level sends.

**The cell.** The row restarted at 2026-11-25T15:51:42Z, `docker restart vllm-audio`, which
emptied its caches (both counters at 0 before the first level), then each level on its own, as
[bench/README.md](../../bench/README.md#running-a-cell) gives, writing
`.state/bench/audio-capacity-short-levels-framework-lan-<streams>.json`. Across the six levels,
0 of 3,683 requests' audio hit the multimodal cache and 0 of 728,512 prompt tokens the prefix
cache; the row finished 3,588 requests, all on `stop`, with 0 preemptions.

| Streams | Start, UTC | ok/err/inc | req/s | TTFT median ms | Latency median s | Latency p90 s | Prompt tok/s | RTFx median | RTFx min | RTFx ≥ 5 | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 2026-11-25T15:52:59Z | 277/0/4 | 3.078 | 218 | 1.06 | 2.08 | 611 | 5.26 | 1.21 | 168/277 | 90 | meets |
| 8 | 2026-11-25T15:54:38Z | 466/0/8 | 5.178 | 262 | 1.35 | 2.57 | 1,019 | 4.23 | 2.36 | 118/466 | 90 | misses |
| 12 | 2026-11-25T15:56:15Z | 583/0/11 | 6.467 | 309 | 1.63 | 2.99 | 1,273 | 3.56 | 1.69 | 11/583 | 90 | misses |
| 16 | 2026-11-25T15:57:53Z | 671/0/16 | 7.456 | 341 | 1.98 | 3.40 | 1,468 | 3.08 | 1.40 | 5/671 | 90 | misses |
| 24 | 2026-11-25T15:59:33Z | 769/1/24 | 8.544 | 434 | 2.55 | 4.27 | 1,667 | 2.36 | 0.90 | 0/769 | 90 | misses |
| 32 | 2026-11-25T16:01:12Z | 822/0/32 | 9.133 | 524 | 3.10 | 5.36 | 1,794 | 1.89 | 0.67 | 0/822 | 90 | misses |

The host's lowest MemAvailable over the cell was 78.68 GiB and its lowest GTT available 80.77,
sampled every 10 s. The error at 24 streams is GuideLLM's `ConnectTimeout`, a connection the
client didn't open in time, not an answer from the row.

- **Throughput rises to 32 streams without a plateau**: 9.13 requests a second at 32, 3.0 times
  the 4-stream rate, each step adding less (8.54 to 9.13 from 24 to 32).
- **The RTFx median falls as streams rise**: 5.26 at 4 streams, the only level that meets the
  floor, 4.23 at 8, and 1.89 at 32, as the latency median grows from 1.06 s to 3.10.

## audio-capacity-30s

The row at the same setting and start as
[audio-capacity-short](#audio-capacity-short), right after it with no restart, since no window row's
audio repeats a short row's. Each level ran on its own with
[`bench/audio-capacity-30s.yaml`](../../bench/audio-capacity-30s.yaml), writing
`.state/bench/audio-capacity-30s-levels-framework-lan-<streams>.json`; `tailscale ping framework`
direct, 1 ms. Across the six levels, 0 of 842 requests' audio hit the multimodal cache and 0 of
642,132 prompt tokens the prefix cache; the row finished 752 requests, all on `stop`, with 0
preemptions.

| Streams | Start, UTC | ok/err/inc | req/s | TTFT median ms | Latency median s | Latency p90 s | Prompt tok/s | RTFx median | RTFx min | RTFx ≥ 5 | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 2026-11-25T16:03:08Z | 67/0/4 | 0.744 | 467 | 5.06 | 6.22 | 568 | 5.77 | 4.39 | 56/67 | 90 | meets |
| 8 | 2026-11-25T16:04:46Z | 103/0/7 | 1.144 | 489 | 6.55 | 8.09 | 874 | 4.45 | 2.93 | 12/103 | 90 | misses |
| 12 | 2026-11-25T16:06:26Z | 126/0/12 | 1.400 | 717 | 8.05 | 10.33 | 1,069 | 3.64 | 2.45 | 2/126 | 90 | misses |
| 16 | 2026-11-25T16:08:04Z | 140/0/16 | 1.556 | 751 | 9.51 | 11.70 | 1,188 | 3.02 | 1.98 | 0/140 | 90 | misses |
| 24 | 2026-11-25T16:09:42Z | 154/1/24 | 1.711 | 893 | 12.32 | 15.99 | 1,306 | 2.39 | 1.41 | 0/154 | 90 | misses |
| 32 | 2026-11-25T16:11:20Z | 162/0/30 | 1.778 | 1,109 | 15.59 | 20.58 | 1,374 | 1.87 | 1.11 | 0/162 | 90 | misses |

The host's lowest MemAvailable over the cell was 77.76 GiB and its lowest GTT available 80.78,
sampled every 10 s. The error at 24 streams is again GuideLLM's `ConnectTimeout`.

- **Throughput flattens past 16 streams**: 1.56 requests a second at 16, 1.71 at 24 and 1.78 at
  32, while the latency median grows from 9.51 s to 15.59. In seconds of speech a second, about
  29 times the request rate, the row clears about 22 at 4 streams and about 52 at 32, against
  about 20 and 60 on short clips.
- **The RTFx median falls as streams rise**: 5.77 at 4 streams, the only level that meets the
  floor, to 1.87 at 32.
- No level ran out of window rows.

No sweep ran on clips longer than 30 s: the row keeps only the first 30 s of a longer clip
([audio-probe](#audio-probe)).

## audio-real-30s

The row on docinfer's real windows, [`bench/audio-real-30s.yaml`](../../bench/audio-real-30s.yaml):
every distinct window of 28 to 30 s in the docproc run docinfer read, as docinfer sends them
([bench/README.md](../../bench/README.md#docinfers-inputs)), each row its own audio. The row alone
on `framework` at cap 48, the cell's top level (`--max-num-seqs 48`, `--max-num-queued-reqs 128`),
fraction 0.28, context 8,192, on vLLM v0.34.0 in the image
`ai-hosting/vllm-openai-rocm-audio:v0.34.0` at
`sha256:da0499371911becb1d50c0d96a5cae18cd607b3bdebf02b155cbe44225c319f7`. The cap was raised by
`hosting profile set audio cap=48` in the host's clone, uncommitted, then `hosting engine update
audio` at 2026-11-26T04:10:03Z: its weights took 15.22 GiB, its KV cache held 371,231 tokens, 45.32
requests of 8,192, and the host's MemAvailable fell no lower than 80.70 GiB through the start,
sampled every second. The client is the laptop on the LAN, GuideLLM 0.8.1 with Gemma 4 E4B's
tokenizer through transformers 5.24.1; `tailscale ping framework` answered direct, 0 or 1 ms,
before each cell. Each level ran on its own, from 2026-11-26T04:12:33Z:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host framework --alias audio \
  --scenario bench/audio-real-30s.yaml --cell audio-real-30s-framework \
  8:200 16:300 24:400 32:500 48:600
```

`levels.jq` with `--arg purpose audio`; the second-half rate is the requests that finished in the
level's last 45 s, over 45 s ([bench/README.md](../../bench/README.md#reading-the-results)):

| Streams | Start, UTC | ok/err/inc | req/s | Second-half req/s | TTFT median ms | Latency median s | Latency p90 s | Prompt tok/s | RTFx median | RTFx min | RTFx ≥ 5 | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 8 | 2026-11-26T04:12:39Z | 91/0/7 | 1.011 | 1.111 | 516 | 7.57 | 9.09 | 822 | 3.86 | 2.15 | 6/91 | 90 | misses |
| 16 | 2026-11-26T04:14:17Z | 128/0/16 | 1.422 | 1.489 | 733 | 10.50 | 12.83 | 1,149 | 2.75 | 1.74 | 5/128 | 90 | misses |
| 24 | 2026-11-26T04:15:55Z | 144/0/24 | 1.600 | 1.822 | 992 | 13.79 | 17.59 | 1,296 | 2.13 | 1.16 | 5/144 | 90 | misses |
| 32 | 2026-11-26T04:17:34Z | 148/0/32 | 1.644 | 1.889 | 1,089 | 16.89 | 23.03 | 1,328 | 1.70 | 0.99 | 1/148 | 90 | misses |
| 48 | 2026-11-26T04:19:12Z | 150/0/47 | 1.656 | 2.133 | 1,600 | 24.66 | 35.30 | 1,351 | 1.19 | 0.66 | 9/150 | 90 | misses |

Across the five levels, 0 of 787 requests' audio hit the multimodal cache and 0 of 637,298 prompt
tokens the prefix cache; the row finished 661 requests, all on `stop`, with 0 preemptions. The
host's lowest MemAvailable over the cell was 78.47 GiB, sampled every 10 s. The windows average
29.2 s of audio, and some are silent: a reply of 1 token, a request of under 1 s.

**The repeats.** Requests a second put 48 streams 0.7% over 32, within the run noise that
[audio-noise](#audio-noise) reads, so 24 and 32 streams ran again from a restart at
2026-11-26T04:24:14Z, on the next rows:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host framework --alias audio \
  --scenario bench/audio-real-30s.yaml --cell audio-real-30s-repeat-framework 24:400 32:500
```

| Streams | Start, UTC | ok/err/inc | req/s | Second-half req/s | TTFT median ms | Latency median s | Latency p90 s | Prompt tok/s | RTFx median | RTFx min | RTFx ≥ 5 | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 24 | 2026-11-26T04:25:23Z | 140/0/24 | 1.556 | 1.822 | 905 | 14.09 | 18.28 | 1,264 | 2.09 | 1.23 | 7/140 | 90 | misses |
| 32 | 2026-11-26T04:27:01Z | 146/0/32 | 1.622 | 1.889 | 1,173 | 17.22 | 23.62 | 1,314 | 1.68 | 0.99 | 3/146 | 90 | misses |

The host's lowest MemAvailable over the repeats was 79.43 GiB.

- **Requests a second read low at the higher levels.** A level's streams start together, and with
  a latency median of 17 to 25 s, its first 20 s or so finish few requests, and the 32 to 47
  requests in flight at its end don't count. The second-half rate leaves both out: 1.889 at 32
  streams in both readings, which the 600 s levels of [layout](#layout) match, against requests a
  second of 1.644 and 1.622.
- **Throughput rises to 48 streams, the top level.** On the second-half rate, 48 streams clear
  2.133 and 2.044 requests a second ([audio-noise](#audio-noise)), 8% and 13% over 32 streams'
  1.889, wider than the noise; 24 streams clear 1.822 twice. In seconds of speech, 48 streams clear
  about 61 a second. [audio-real-30s-64](#audio-real-30s-64) finds the rise ends there.
- Real windows run about 11% under the LibriSpeech windows of
  [audio-capacity-30s](#audio-capacity-30s), whose 32-stream level clears 2.133 on the second-half
  rate, on prompts about 6% longer: 808 prompt tokens a request on average against 764.
- The RTFx median falls from 3.86 at 8 streams to 1.19 at 48; no level meets the floor, which
  doesn't set the cap.

## audio-real-30s-64

[audio-real-30s](#audio-real-30s)'s windows one level higher, 64 streams for 90 s, since the rate
still rose at 48. The row at cap 64 and a queue limit of 256, four times the cap, set by `hosting
profile set` in the host's clone, uncommitted, and started by `hosting engine update audio` at
2026-11-26T10:08:34Z, fraction 0.30: its KV cache held 430,276 tokens, 52.52 requests of 8,192, and
MemAvailable fell no lower than 78.24 GiB through the start. `tailscale ping framework` direct.

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host framework --alias audio \
  --scenario bench/audio-real-30s.yaml --cell audio-real-30s-64-framework 64:700
```

| Streams | Start, UTC | ok/err/inc | req/s | Second-half req/s | TTFT median ms | Latency median s | Latency p90 s | Prompt tok/s | RTFx median | RTFx min | RTFx ≥ 5 | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 64 | 2026-11-26T10:11:12Z | 132/1/64 | 1.467 | 2.111 | 4,640 | 35.48 | 50.07 | 1,192 | 0.83 | 0.48 | 7/132 | 90 | misses |

The row finished 132 requests, all on `stop`, with 0 preemptions and no cache hit; the error is
GuideLLM's `ConnectTimeout`, a connection the client didn't open in time. The host's lowest
MemAvailable over the cell was 76.83 GiB. The row then returned to cap 48 by `git checkout` of the
profile and `hosting engine update audio`.

- **Throughput stops rising at 48 streams.** 64 streams clear 2.111 requests a second on the
  second-half rate, within [audio-noise](#audio-noise)'s 4.4% of 48 streams' highest, 2.133, while
  the latency median grows from 24.66 s to 35.48 s. 48 is the lowest level within the run noise of
  the highest figure, so the peak is 48; 32 streams' 1.889 sits 11% under it. No level past 64
  ran.

## audio-noise

The run noise: [audio-real-30s](#audio-real-30s)' top level, 48 streams, run again from a restart
at 2026-11-26T04:21:14Z, as [the verdict](../upgrades.md#the-verdict) asks. Its start read the same
KV cache, and MemAvailable fell no lower than 80.85 GiB through it.

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host framework --alias audio \
  --scenario bench/audio-real-30s.yaml --cell audio-real-30s-noise-framework 48:600
```

| Streams | Start, UTC | ok/err/inc | req/s | Second-half req/s | TTFT median ms | Latency median s | Latency p90 s | Prompt tok/s | RTFx median | RTFx min | RTFx ≥ 5 | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 48 | 2026-11-26T04:22:24Z | 143/0/48 | 1.589 | 2.044 | 1,812 | 25.70 | 36.66 | 1,292 | 1.13 | 0.70 | 6/143 | 90 | misses |

The host's lowest MemAvailable over the cell was 79.48 GiB.

- **48 streams spread 4.4% on the second-half rate**, 2.133 and 2.044 requests a second, and 4.2%
  on requests a second, 1.656 and 1.589. The repeats of [audio-real-30s](#audio-real-30s) at 24
  and 32 streams read the same second-half rate twice. The widest, 4.4%, is the host's run noise.

## audio-start

The row's start at the cap of 48 and fraction 0.30, `hosting engine update audio` at
2026-11-26T05:47:39Z, after [layout](#layout), with the profile's values set in the host's clone:
its weights took 15.22 GiB, its KV cache 17.6 GiB, 431,113 tokens, 52.63 requests of 8,192, and the
host's MemAvailable fell no lower than 78.15 GiB through the start, sampled every second.

- **0.30 holds the cap at the row's context**: 52.63 requests of 8,192 against the cap of 48, where
  0.28 held 371,231 tokens, 45.32 requests ([audio-real-30s](#audio-real-30s)). The cells ran at
  0.28; their requests, about 890 tokens each with the reply, used a small part of either cache.

## layout

The audio row in the standing layout cell ([vision.md#layout](vision.md#layout)): docinfer's
windows at the target of 48 streams, held for 600 s in each of the cell's four rounds beside the
other three rows, each round from a restart, at cap 48 and a queue limit of 192:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host framework --alias audio \
  --scenario bench/audio-real-30s.yaml --cell layout-v2-audio-framework --seconds 600 48:1500
```

The rounds `layout-v4`, `layout-v8` and `layout-v32` ran the same. Against
[audio-real-30s](#audio-real-30s)' and [audio-noise](#audio-noise)'s 48 streams alone, whose levels
ran 90 s:

| Round | Start, UTC | ok/err/inc | req/s | Second-half req/s | TTFT median ms | Latency median s | Latency p90 s | Prompt tok/s | RTFx median | RTFx min | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Alone | 2026-11-26T04:19:12Z | 150/0/47 | 1.656 | 2.133 | 1,600 | 24.66 | 35.30 | 1,351 | 1.19 | 0.66 | 90 |
| Alone, again | 2026-11-26T04:22:24Z | 143/0/48 | 1.589 | 2.044 | 1,812 | 25.70 | 36.66 | 1,292 | 1.13 | 0.70 | 90 |
| Vision at 2 | 2026-11-26T05:02:44Z | 1185/0/48 | 1.975 | 2.040 | 1,156 | 23.86 | 29.09 | 1,599 | 1.23 | 0.68 | 600 |
| Vision at 4 | 2026-11-26T05:14:15Z | 1179/0/45 | 1.960 | 2.027 | 1,174 | 23.95 | 29.26 | 1,591 | 1.22 | 0.66 | 600 |
| Vision at 8 | 2026-11-26T05:25:41Z | 1175/0/48 | 1.958 | 2.013 | 1,241 | 23.98 | 29.25 | 1,586 | 1.21 | 0.67 | 600 |
| Vision at 32 | 2026-11-26T10:58:09Z | 1193/0/48 | 1.988 | 2.057 | 1,151 | 23.63 | 28.78 | 1,610 | 1.24 | 0.69 | 600 |

The first three rounds ran at fraction 0.28: each start read a KV cache of 371,231 tokens, and the
host's lowest MemAvailable was 80.42 GiB through the starts and 78.64 GiB through the rounds. The
round at vision's 32 ran at the present 0.30 ([audio-start](#audio-start)): its start read 431,113
tokens, and MemAvailable fell no lower than 78.41 GiB through it and 76.37 GiB through the round.
Across the rounds 0 requests' audio hit the multimodal cache, and the row finished every request on
`stop` with 0 preemptions.

- **The audio row beside the others matches it alone**: 2.013 to 2.057 requests a second on the
  second-half rate against 2.044 and 2.133, within [audio-noise](#audio-noise)'s 4.4%. Over 600 s
  requests a second read 1.958 to 1.988, near the second-half rate, since the start and the end of
  a level weigh less on it.
- A first round at 2026-11-26T04:48:18Z ran the audio row at 32 streams, the earlier target, before
  the cap moved to 48 (`.state/bench/layout32-v2-audio-framework-32.json`): 1.887 requests a second,
  1.940 on the second-half rate, as [audio-real-30s](#audio-real-30s)' 32 streams read 1.889.
