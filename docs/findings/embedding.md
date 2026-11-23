# Embedding findings

The measurements behind the strix-halo profile's embedding row, which serves
`intfloat/multilingual-e5-large` on the Framework. Each section is one cell: its command, its time
in UTC, its figures, and the tool versions it ran on. The profile's reasons cite the cells by their
section; the row's settings live in [the profile](../../classes/strix-halo/profile.toml).

## Tools

Every cell ran on the tools below unless it names others.

| Tool | Version |
| --- | --- |
| vLLM | v0.34.0, `vllm/vllm-openai-rocm:v0.34.0` at `sha256:3cb773d23f063afa86291ef75773cdd486154ddea94c213300f4ed7cc42b7af1` |
| GuideLLM | 0.8.1, in the bench environment ([bench/README.md](../../bench/README.md)) |
| Tokenizer | e5's own, through transformers 5.20.2 in GuideLLM's environment |
| Checkpoint | `intfloat/multilingual-e5-large` at `3d7cfbdacd47fdda877c5cd8a79fbcc4f2a574f3` |

The row ran as the profile renders it: `--max-model-len 512`, `--gpu-memory-utilization 0.03`,
`--runner pooling`, `--max-num-batched-tokens 65536`, and the `--max-num-seqs` each cell names.
The audio row stood beside it, idle, in every cell but the audio cells,
[e5-audio-alone](#e5-audio-alone) and [e5-pair](#e5-pair). Those load the audio row as the
profile renders it, on `ai-hosting/vllm-openai-rocm-audio:v0.34.0` at
`sha256:da0499371911becb1d50c0d96a5cae18cd607b3bdebf02b155cbe44225c319f7`, built on the image
above, with Gemma 4 E4B's own tokenizer in GuideLLM.

## Path

Every cell ran from the laptop, and its figures are client-side over Tailscale's DERP relay
(`iad`), not the LAN: the laptop has no direct path to the Framework. `tailscale ping -c 3
framework`, run right before each audio cell, answered via `DERP(iad)` every time, in 47 to 68 ms,
with "direct connection not established"; the first, at 16:36Z, came after
[e5-audio-alone](#e5-audio-alone). No ping preceded the earlier cells, [e5-probes](#e5-probes),
[e5-sweep-128](#e5-sweep-128), [e5-sweep-32](#e5-sweep-32) and [e5-retrieval](#e5-retrieval);
they ran from the laptop on the same network, so the sweeps and the cap they set were measured
over the same relay. Retrieval's scores don't depend on the path.

Over the relay, audio's RTFx median alone is about 4.4 to 4.6, against 6.54 on the LAN in
spike-model-layout (`docs/findings/vllm-layout.md`, F.4): its inter-token latency median is the
LAN's, 45.6 ms, and the difference is the request's time on the relay. So audio's floor, an RTFx
median of at least 5, is not judged on this path; the standing layout cell judges it. Beside
embedding, audio holds when its RTFx median is at least 0.89 times its median alone, measured right
before on the same path: granite's ratio at 34 requests a second on the LAN, 5.84 over 6.54.

## e5-card

Read 2026-11-23, before the pull, from the [model card](https://huggingface.co/intfloat/multilingual-e5-large)
and its `config.json`, at the checkpoint above.

- Licence MIT. The authors are Microsoft's (Wang, Yang, Huang, Yang, Majumder, Wei).
- 24 XLM-RoBERTa layers, hidden size 1,024, so 1,024 dimensions.
- The card's limitation: long texts are truncated to at most 512 tokens. The config's
  `max_position_embeddings` is 514, XLM-R's 512 plus its two-position offset.
- Each input starts with `query: ` or `passage: `.

## e5-update

`hosting model pull intfloat/multilingual-e5-large`, 2026-11-23T15:57:42Z to 16:02:01Z, then
`hosting engine update embedding`, 16:02:10Z to 16:02:12Z, on the Framework, with cap 128.

- The start log resolves mean pooling from the checkpoint's sentence-transformers config. Model
  loading took 1.08 GiB, graph capture 0.24 GiB, and the engine's start 5.81 s; the row answered
  healthy at 16:05:22Z. vLLM loads the float32 checkpoint as float16.
- The store holds the checkpoint at 9.5 GB: its repository carries ONNX and other exports beside
  the safetensors weights, and `model pull` downloads the whole repository.

## e5-probes

From the laptop, 2026-11-23T16:05:43Z to 16:05:58Z, against `http://framework:8003`, each input's
tokens counted with e5's tokenizer. The long inputs are a repeated English sentence prefixed
`passage: `, cut to the token count.

| Probe | Request | Answer |
| --- | --- | --- |
| Models | `GET /v1/models` | one model, `embedding`, root `intfloat/multilingual-e5-large`, `max_model_len` 512 |
| Short input | `POST /v1/embeddings`, `query: how much protein should a female eat`, 12 tokens with the special tokens | 200; 1,024 components, norm 0.99999999 |
| 510 tokens | 510 tokens, 512 with the two special tokens | 200; 1,024 components, norm 1.00000001, `prompt_tokens` 512 |
| 511 tokens | 511 tokens, 513 with the two special tokens | 400 `BadRequestError`: "This model's maximum context length is 512 tokens. However, your prompt contains at least 513 input tokens" |

At cap 32, 2026-11-23T16:16:10Z to 16:16:16Z, the probes answered the same: the vectors 1,024
components with norms 0.99999999 and 1.00000001, and 511 tokens refused with 400.

The row normalizes its vectors. The long-input probe passed on the stock ROCm image, so the row
takes no MIOpen setting.

## e5-sweep-128

From the laptop, 2026-11-23T16:06:08Z to 16:09:57Z, the row at cap 128:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8003 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/embedding-sweep.yaml \
  --backend kind=openai_http,model=embedding \
  --tokenizer kind=huggingface_auto,model=intfloat/multilingual-e5-large \
  --output kind=json,path=.state/bench/e5/e5-sweep.json
```

`levels.jq` with `--arg purpose embed`; each request 510 tokens, 512 with the special tokens.
GuideLLM concluded no knee for the concurrent profile.

| Streams | ok/err/inc | req/s | Latency median s | Latency p90 s | Prompt tok/s | Floor |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 288/0/0 | 9.567 | 0.10 | 0.12 | 4,889 | meets |
| 4 | 1136/0/3 | 37.833 | 0.10 | 0.13 | 19,333 | meets |
| 16 | 2224/0/16 | 74.133 | 0.21 | 0.26 | 37,882 | meets |
| 32 | 2133/0/32 | 71.100 | 0.44 | 0.49 | 36,332 | meets |
| 64 | 1828/0/64 | 60.933 | 1.04 | 1.07 | 31,137 | meets |
| 128 | 1544/0/128 | 51.467 | 2.47 | 2.97 | 26,299 | meets |

The incomplete requests are the streams in flight when each level's 30 s ended. The row's
`/metrics` after the run: 9,199 requests finished with `stop`, none with `error` or `abort`, and
`vllm:num_preemptions_total` 0.

- The knee is 16 streams: throughput stops rising there, at its peak of 37,882 prompt tok/s.
- The plateau holds to 32 streams, 36,332, 4.1% under the peak. Past it, throughput falls rather
  than flattening: 31,137 at 64 streams, 17.8% under, and 26,299 at 128, 30.6% under.
- Every level meets embedding's floor of 4,300 prompt tok/s, the lowest 4,889 at 1 stream.
- `hosting engine memory`, read every 10 s or so on the Framework through the run, showed the
  embedding row's GTT rising from 1,811 MiB to 3,615 MiB in the run's last reads, over the
  3,441 MiB that fraction 0.03 reserves.

## e5-sweep-32

The row at cap 32, after `hosting engine update embedding` replaced it at 2026-11-23T16:11:18Z
to 16:11:20Z; it answered healthy at 16:11:50Z. From the laptop, 16:11:56Z to 16:15:43Z, the
command of [e5-sweep-128](#e5-sweep-128) writing `.state/bench/e5/e5-sweep-32.json`.

| Streams | Level, UTC | ok/err/inc | req/s | Latency median s | Latency p90 s | Prompt tok/s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 16:12:07 to 16:12:37 | 278/0/1 | 9.267 | 0.10 | 0.11 | 4,735 | meets |
| 4 | 16:12:47 to 16:13:17 | 1111/0/3 | 37.000 | 0.10 | 0.13 | 18,907 | meets |
| 16 | 16:13:24 to 16:13:54 | 1979/0/15 | 65.967 | 0.22 | 0.33 | 33,709 | meets |
| 32 | 16:14:00 to 16:14:30 | 2122/0/31 | 70.733 | 0.44 | 0.59 | 36,145 | meets |
| 64 | 16:14:37 to 16:15:07 | 1843/0/64 | 61.433 | 1.02 | 1.11 | 31,392 | meets |
| 128 | 16:15:13 to 16:15:43 | 1837/0/128 | 61.233 | 2.05 | 2.11 | 31,290 | meets |

The row's `/metrics` after the run: 9,272 requests finished with `stop`, none with `error` or
`abort`, and `vllm:num_preemptions_total` 0.

- The peak is 36,145 prompt tok/s at 32 streams, with 16 streams 6.7% under it. The two sweeps
  put the same level 11% apart at 16 streams, so the plateau is 16 to 32 streams.
- Past 32 streams throughput falls to about 31,300 with the cap or without it: at 64 streams the
  two sweeps differ by 0.8%. At 128 streams the cap holds 31,290, against 26,299 at cap 128.
- Every level meets embedding's floor, the lowest 4,735 at 1 stream.
- `hosting engine memory`, read every 4 s or so on the Framework with its time, showed the
  embedding row's GTT at 1,694 MiB through the 1-stream level, 2,014 MiB by the 16-stream
  level's end, 2,330 MiB in the 32-stream level, and 2,554 MiB from the 64-stream level's start
  to the run's end: within the 3,441 MiB that fraction 0.03 reserves.

## e5-memory

`hosting engine memory` on the Framework, the embedding row at fraction 0.03, both rows idle.

| Read, UTC | Embedding cap | Audio GTT MiB | Embedding GTT MiB | Pool GTT used | GTT free | MemAvailable |
| --- | --- | --- | --- | --- | --- | --- |
| 16:06:03, after the probes | 128 | 19,739 | 1,811 | 21.33 GiB | 90.67 GiB | 85.36 GiB |
| 16:11:50, freshly started | 32 | 19,739 | 1,690 | 21.21 GiB | 90.79 GiB | 85.19 GiB |
| 16:16:05, after [e5-sweep-32](#e5-sweep-32) | 32 | 19,739 | 2,554 | 22.06 GiB | 89.94 GiB | 84.53 GiB |

Of the pool's 112.00 GiB, the fraction 0.03 is 3,441 MiB. e5 starts and serves within it at cap
32, so the fraction stays at 0.03.

## e5-rows

`hosting` on the Framework, its clone on the `embedding` branch, addresses left out.

- 16:05:22Z and 16:05:27Z, at cap 128: `hosting engine status` exits 0 with both rows running
  and healthy; `hosting engine models` shows `embedding` serving root
  `intfloat/multilingual-e5-large` at context 512; `hosting engine update` with no alias reports
  for each row that it already runs its row, "nothing changed"; `hosting model list` shows
  `intfloat/multilingual-e5-large`, 9.5G, served by `embedding`, and granite, 599.7M, by no row;
  `hosting model prune` would remove granite.
- 16:16:19Z, at cap 32, after the probes passed again at 16:16:10Z: `hosting model prune` would
  remove `ibm-granite/granite-embedding-english-r2` (599.7M); `--yes` removed it; `hosting model
  prune` then printed "nothing to prune: every model in /srv/models is served by a row recorded
  on this host".

## e5-retrieval

From the laptop, 2026-11-23T16:19:19Z to 16:28:19Z, a wall time of 9 min 0 s (MTEB's evaluation
time 532 s), the row at cap 32 with nothing else sent to it:

```sh
MISE_ENV=bench mise exec -- bench/retrieval.sh --endpoint framework:8003 \
  --query-prefix 'query: ' --passage-prefix 'passage: ' --output .state/bench/e5/retrieval-e5
```

It ran the default 37 subsets to the end; no passage was over 512 tokens. The result is
`.state/bench/e5/retrieval-e5/results/intfloat__multilingual-e5-large/embedding/BelebeleRetrieval.json`.
It ran on MTEB 2.27.22 under Python 3.14.10, with transformers 5.24.0, torch 2.15.0,
sentence-transformers 6.3.0, datasets 5.2.0 and requests 2.34.2, against the Belebele dataset
`mteb/belebele` at `979a211276faa22f671e69d096634193567cfd05`.

The published scores are
[`results/intfloat__multilingual-e5-large/ab10c1a7f42e74530fe7ae5be82e6d4f11a719eb/BelebeleRetrieval.json`](https://github.com/embeddings-benchmark/results/blob/2aa494226cb43a73ac028d865d569e38cb7151e2/results/intfloat__multilingual-e5-large/ab10c1a7f42e74530fe7ae5be82e6d4f11a719eb/BelebeleRetrieval.json)
in embeddings-benchmark/results at commit `2aa494226cb43a73ac028d865d569e38cb7151e2`, read at
16:20Z; the file last changed in `91a7962cbda383ab59203627c0214e665d058067`. They ran on MTEB
1.38.3 against `facebook/belebele` at `75b399394a9803252cfec289d103de462763db7c`. The two dataset
revisions hold the same data: `mteb/belebele`'s one commit duplicates `facebook/belebele`, and
Hugging Face's tree of each lists the same 123 data files with the same hashes and sizes, only the
README differing.

Each score is nDCG@10, BelebeleRetrieval's main score; the difference is served minus published,
and a subset passes within 0.02.

| Subset | Published | Served | Difference | Verdict |
| --- | --- | --- | --- | --- |
| `eng_Latn-eng_Latn` | 0.96501 | 0.96542 | +0.00041 | pass |
| `bul_Cyrl-bul_Cyrl` | 0.94790 | 0.94788 | -0.00002 | pass |
| `eng_Latn-bul_Cyrl` | 0.90998 | 0.91039 | +0.00041 | pass |
| `bul_Cyrl-eng_Latn` | 0.94082 | 0.94090 | +0.00008 | pass |
| `ell_Grek-ell_Grek` | 0.94507 | 0.94507 | +0.00000 | pass |
| `eng_Latn-ell_Grek` | 0.88037 | 0.88034 | -0.00003 | pass |
| `ell_Grek-eng_Latn` | 0.93635 | 0.93635 | +0.00000 | pass |
| `pol_Latn-pol_Latn` | 0.95278 | 0.95252 | -0.00026 | pass |
| `eng_Latn-pol_Latn` | 0.92291 | 0.92291 | +0.00000 | pass |
| `pol_Latn-eng_Latn` | 0.94916 | 0.94907 | -0.00009 | pass |
| `arb_Arab-arb_Arab` | 0.93480 | 0.93480 | +0.00000 | pass |
| `eng_Latn-arb_Arab` | 0.87164 | 0.87172 | +0.00008 | pass |
| `arb_Arab-eng_Latn` | 0.92082 | 0.92082 | +0.00000 | pass |
| `heb_Hebr-heb_Hebr` | 0.92538 | 0.92543 | +0.00005 | pass |
| `eng_Latn-heb_Hebr` | 0.83819 | 0.83860 | +0.00041 | pass |
| `heb_Hebr-eng_Latn` | 0.92039 | 0.92039 | +0.00000 | pass |
| `jpn_Jpan-jpn_Jpan` | 0.94625 | 0.94630 | +0.00005 | pass |
| `eng_Latn-jpn_Jpan` | 0.89743 | 0.89735 | -0.00008 | pass |
| `jpn_Jpan-eng_Latn` | 0.91834 | 0.91845 | +0.00011 | pass |
| `rus_Cyrl-rus_Cyrl` | 0.95283 | 0.95283 | +0.00000 | pass |
| `eng_Latn-rus_Cyrl` | 0.92340 | 0.92386 | +0.00046 | pass |
| `rus_Cyrl-eng_Latn` | 0.93891 | 0.93883 | -0.00008 | pass |
| `zho_Hans-zho_Hans` | 0.95232 | 0.95236 | +0.00004 | pass |
| `eng_Latn-zho_Hans` | 0.87899 | 0.87908 | +0.00009 | pass |
| `zho_Hans-eng_Latn` | 0.91372 | 0.91367 | -0.00005 | pass |
| `hin_Deva-hin_Deva` | 0.90736 | 0.90734 | -0.00002 | pass |
| `eng_Latn-hin_Deva` | 0.86776 | 0.86774 | -0.00002 | pass |
| `hin_Deva-eng_Latn` | 0.94193 | 0.94152 | -0.00041 | pass |
| `spa_Latn-spa_Latn` | 0.95530 | 0.95530 | +0.00000 | pass |
| `eng_Latn-spa_Latn` | 0.92942 | 0.92927 | -0.00015 | pass |
| `spa_Latn-eng_Latn` | 0.95349 | 0.95349 | +0.00000 | pass |
| `fra_Latn-fra_Latn` | 0.95512 | 0.95512 | +0.00000 | pass |
| `eng_Latn-fra_Latn` | 0.93646 | 0.93698 | +0.00052 | pass |
| `fra_Latn-eng_Latn` | 0.95479 | 0.95479 | +0.00000 | pass |
| `kor_Hang-kor_Hang` | 0.94499 | 0.94499 | +0.00000 | pass |
| `eng_Latn-kor_Hang` | 0.86452 | 0.86460 | +0.00008 | pass |
| `kor_Hang-eng_Latn` | 0.92031 | 0.92031 | +0.00000 | pass |

- Every subset passes. The largest difference is +0.00052, `eng_Latn-fra_Latn`; the largest below
  published is -0.00041, `hin_Deva-eng_Latn`. Thirteen subsets match to the fifth decimal.
- Prefixes, truncation, pooling and normalization need no diagnosis: no subset misses, the
  runner sent `query: ` and `passage: ` and never asked the row to truncate, and the row's mean
  pooling and unit vectors are [e5-update](#e5-update)'s and [e5-probes](#e5-probes)'.

## e5-audio-alone

From the laptop, 2026-11-23T16:31:44Z to 16:35:44Z, the audio row at 4 streams with the
embedding row idle (its finished requests stayed at 60,630):

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/audio.yaml \
  --backend kind=openai_http,model=audio \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it \
  --output kind=json,path=.state/bench/e5/audio-alone.json
```

`levels.jq` with `--arg purpose audio`: 642/0/3 requests, 2.675 req/s, request latency median
1.30 s and p90 2.22 s, time to first token median 530 ms, inter-token latency median 45.60 ms,
**RTFx median 4.43**, minimum 1.51, 152 of 642 at 5 or more, 240 s. The median sat at 4.3 to 4.6
in every 30 s window after the first, so it is no warm-up. The row's `/metrics` after it: 642
requests finished, no preemption. This cell is the record of audio alone; each pair in
[e5-pair](#e5-pair) is judged against the alone run right before it.

## e5-pair

From the laptop, 2026-11-23T16:50:37Z to 17:42:09Z: at each rate, `tailscale ping`, audio alone
for 240 s, `tailscale ping`, then the pair: audio at 4 streams and embedding at the rate, two
GuideLLM processes started together in the background of one shell and waited on, each for
240 s. Nothing else loaded either row. For rate `<r>`, the alone run is the command of
[e5-audio-alone](#e5-audio-alone) writing `.state/bench/e5/alone-r<r>.json`
(`audio-alone-2.json` at 34), and the pair:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/audio.yaml \
  --backend kind=openai_http,model=audio \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it \
  --output kind=json,path=.state/bench/e5/pair-a4r<r>-audio.json &
GUIDELLM__SPEC__PROFILE__RATE=<r> GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8003 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/embedding-rate.yaml \
  --backend kind=openai_http,model=embedding \
  --tokenizer kind=huggingface_auto,model=intfloat/multilingual-e5-large \
  --output kind=json,path=.state/bench/e5/pair-a4r<r>-embed.json &
wait
```

Audio holds when its pair median is at least 0.89 times the alone median ([Path](#path)).
Embedding keeps its rate when it errs on no request and its achieved rate is within 2% of the
target. Descending from 34 requests a second in steps of 4, the first rate that holds ends the
cells. Figures are `levels.jq`'s, with each RTFx median to two places and the ratio from the
unrounded medians.

| Rate req/s | Alone, UTC | Alone RTFx median | Pair, UTC | Audio ok/err/inc | Audio RTFx median | Ratio | Audio ITL median ms | Embedding ok/err/inc | Embedding req/s | Prompt tok/s | Holds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 34 | 16:50:37 to 16:54:37 | 4.57 | 16:54:51 to 16:58:54 | 503/0/4 | 3.52 | 0.769 | 61.46 | 8155/0/6 | 33.975 | 17,361 | no |
| 30 | 16:59:38 to 17:03:38 | 4.41 | 17:03:51 to 17:07:54 | 525/0/3 | 3.71 | 0.840 | 59.24 | 7197/0/4 | 29.987 | 15,324 | no |
| 26 | 17:08:11 to 17:12:11 | 4.45 | 17:12:25 to 17:16:28 | 534/0/2 | 3.81 | 0.856 | 57.26 | 6237/0/4 | 25.987 | 13,280 | no |
| 22 | 17:16:46 to 17:20:46 | 4.45 | 17:20:59 to 17:25:02 | 558/0/2 | 3.88 | 0.872 | 54.98 | 5278/0/3 | 21.987 | 11,236 | no |
| 18 | 17:25:19 to 17:29:19 | 4.43 | 17:29:32 to 17:33:35 | 549/0/4 | 3.82 | 0.864 | 52.59 | 4319/0/2 | 17.992 | 9,194 | no |
| 14 | 17:33:52 to 17:37:52 | 4.37 | 17:38:05 to 17:42:09 | 586/0/4 | 4.09 | 0.937 | 50.80 | 3358/0/3 | 13.992 | 7,150 | yes |

Every ping before these cells answered via `DERP(iad)`, 47 to 68 ms. The alone runs' inter-token
latency medians were 45.31 to 45.62 ms.

- **14 requests a second holds**: audio's RTFx median 4.09 against 4.37 alone, a drop of 0.28,
  ratio 0.937; embedding achieved 13.992 req/s, 99.94% of the target, with 3,358 requests and no
  error, at 7,150 prompt tok/s, 1.66 times its floor of 4,300.
- At 34, the rate the gateway admitted for granite, audio drops 1.06 from 4.57, ratio 0.769, and
  its inter-token latency median rises from 45.59 ms to 61.46 ms. From 30 to 18 the ratio stays
  0.84 to 0.87, under 0.89.
- Embedding kept its rate with no error at every rate, at least 99.93% of the target, with its
  request latency median 0.12 to 0.18 s.
- No audio run met the floor of 5, alone or beside, which this path doesn't judge ([Path](#path)).
- After the cells ended at 17:42Z, both rows' `/metrics` read no preemption.

## e5-runes

On the laptop, 2026-11-23T17:50:30Z to 17:51:29Z, with e5's tokenizer (`XLMRobertaTokenizer`, from
the checkpoint above) through transformers 5.20.2, in GuideLLM's Python 3.14.10 in the bench
environment. For docinfer, whose chunks are counted in
runes: the tokens per rune e5 gives each language in `~/docs`, and the runes that fit the row's
512 tokens.

The method, a one-off script not kept:

- **Text.** EN, BG, EL and PL: the EU act's XHTML twins,
  `pdf/multilang/eurlex-32011D0833/decision-2011-833-<lang>.html`, their text through Python's
  `html.parser` without `<head>`, `<script>` or `<style>`. HE, JA and RU: the Tears of Steel
  subtitles, `video/tears-of-steel/tos-{he,jp,ru}.srt`, cue text without numbers or times; JA and
  RU add FLEURS' transcripts. AR, ZH and HI: FLEURS' transcripts,
  `audio/short/fleurs-*/*.truth.json`, the `text` of each item, ZH's spaces between characters
  removed as the pool's README says. ES, FR and KO: MInDS-14's transcripts,
  `audio/short/minds14-*/*.truth.json`. `office/multilang/multilang-rtl.truth.json` adds nothing:
  its AR, HE, JA and RU paragraphs are lines of these same sources. Each text joins its parts with
  a space and collapses every run of whitespace to one space.
- **Runes** are Unicode code points, Python's `len` of the decoded string, which is Go's
  `utf8.RuneCountInString` on valid UTF-8.
- **Tokens** are `len(tok(text, add_special_tokens=False)["input_ids"])` over the whole text.
  Tokens per rune is their ratio, summed over a language's sources.
- **Rune bound** = floor((512 − 2 special tokens − 2 tokens of `passage: `) / tokens per rune) =
  floor(508 / tokens per rune). `passage: ` tokenizes as `▁passage`, `:`.
- **Windows.** Where a text runs past twice the bound, the four EU acts, every window of the bound's
  length starting at each 25th rune was tokenized as `passage: ` plus the window, with the special
  tokens; the window bound is the largest length, in steps of 5 runes, at which every such window
  fits 512.

| Language | Source | Runes | Tokens | Tokens per rune | Rune bound | Largest window at the bound, tokens | Window bound |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EN | EU act | 16,112 | 3,347 | 0.208 | 2,445 | 553 | 2,240 |
| BG | EU act | 17,292 | 3,811 | 0.220 | 2,304 | 550 | 2,099 |
| EL | EU act | 18,009 | 4,549 | 0.253 | 2,011 | 570 | 1,801 |
| PL | EU act | 18,606 | 4,156 | 0.223 | 2,274 | 566 | 2,019 |
| AR | FLEURS | 406 | 122 | 0.300 | 1,690 | | |
| HE | subtitles | 1,844 | 744 | 0.403 | 1,259 | | |
| JA | subtitles, FLEURS | 1,047 | 640 | 0.611 | 831 | | |
| RU | subtitles, FLEURS | 2,111 | 620 | 0.294 | 1,729 | | |
| ZH | FLEURS | 105 | 72 | 0.686 | 740 | | |
| HI | FLEURS | 436 | 130 | 0.298 | 1,703 | | |
| ES | MInDS-14 | 391 | 73 | 0.187 | 2,720 | | |
| FR | MInDS-14 | 194 | 39 | 0.201 | 2,526 | | |
| KO | MInDS-14 | 116 | 51 | 0.440 | 1,155 | | |

- The bound from a whole text's rate doesn't hold for every chunk: in each EU act some window of
  the bound's length runs 38 to 58 tokens over 512, since the rate varies along a text. The window
  bounds sit 8 to 11% under the rate's bounds.
- A chunk of 2,000 runes, docinfer's current start, fits every window checked in the EN, BG and PL
  acts, and not every one in the EL act, whose window bound is 1,801. By the rate alone it
  overflows in every language over 0.254 tokens a rune: AR, HE, JA, RU, ZH, HI and KO.
- The smallest bound is ZH's, 740 runes, then JA's, 831. Every sample but the EU acts and the
  subtitles is a few hundred runes or fewer, ZH's 105, so those rates are a sample's, not a
  language's.
