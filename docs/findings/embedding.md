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
The audio row stood beside it, idle, in every cell.

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
