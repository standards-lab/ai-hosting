# Vision findings

The measurements behind the gb10 profile's vision row, which serves
`nvidia/Gemma-4-26B-A4B-NVFP4` alone on gb10-2, and behind its image budget: Gemma 4's
`max_soft_tokens`, the most soft tokens one image may take. Each section is one cell: its command,
its time in UTC, its figures, and the tool versions it ran on. The profile's reasons cite the cells
by their section; the row's settings live in [the profile](../../classes/gb10/profile.toml).

The capacity cells at 280, 560 and 1120, capacity-1120-clean among them, ran the row alone on
synthetic pages with 100-token replies, and no longer set its cap: [dense-1120](#dense-1120) and
the standing layout cell, [layout](#layout), measured it on docinfer's dense pages, alone and beside
the other rows, and the two matched. 560 is an interim budget, measured before 1120. Each table's
Floor column, and "the 10 s floor" below, is `levels.jq`'s vision verdict, a request latency median
of at most 10 s; the row's cap follows its throughput peak instead, as the profile's `cap_reason`
says.

## Tools

Every cell ran on the tools below.

| Tool | Version |
| --- | --- |
| vLLM | v0.34.0, `vllm/vllm-openai:v0.34.0` at `sha256:20fdb089454afbb324efa4110a2c025ff7b27cc1a086e07aa580b18df8ad1ce1` |
| GuideLLM | 0.8.1 with its vision extra, in the bench environment ([bench/README.md](../../bench/README.md)), Pillow 13.0.0 |
| Tokenizer | `google/gemma-4-26B-A4B-it`'s, through transformers 5.24.1 in GuideLLM's environment |
| Checkpoint | `nvidia/Gemma-4-26B-A4B-NVFP4` at `a19cfe00be84568a6867111c9a68c9c44fdcffe6` |

The row ran on gb10-2, the gateway's stack beside it and no other row, at fraction 0.40 and context
8,192. The cells up to [capacity-1120-clean](#capacity-1120-clean) ran at cap 16
(`--max-num-seqs 16`, `--max-num-queued-reqs 32`) with the budget each names; the cells from
[start-1120](#start-1120) on ran at the budget of 1120 and name their cap. The client is the
laptop on the LAN.

## synthetic-data

What GuideLLM 0.8.1's synthetic sources send, read from its code in the bench environment, with
paths under its `guidellm` package. This section is not a cell.

- **Every image is fixed by its source's seed and its row.** `synthetic_image` draws each image
  from `seed=self.config.seed` and `row_index=row_index * self.config.images_per_request + img_idx`
  (`data/deserializers/synthetic_image.py`, lines 85 and 86), through
  `np.random.SeedSequence([int(seed) & 0xFFFFFFFF, int(row_index)])` (`utils/vision.py`, line
  302). The seed is 42 unless the source gives one (`schemas/data/deserializers/synthetic_image.py`,
  lines 62 to 65), and the row starts at `row_index = 0` each time the source is read
  (`data/deserializers/synthetic_image.py`, line 61). The run's `--seed` doesn't reach it.
- **Each level reads the sources again.** Each level iterates the request loader anew
  (`self.requests = iter(requests)`, `scheduler/worker_group.py`, line 120), and each iteration
  raises the loader's epoch (`data/loaders/torch.py`, lines 173 to 176). So each level of a
  one-run sweep sends the first level's images again, in the same order, and every run with the
  scenario's seed sends the same images.
- **The text differs between levels, not between runs.** `synthetic_text` seeds its words with
  `faker.seed_instance(iter_random_seed)`, where `iter_random_seed = self.random_seed +
  self.iteration_count` (`data/deserializers/synthetic.py`, lines 75 and 79), and starts each
  prompt with `f"{self.iteration_count} {samples_count} m{turn_idx} "` (line 288): the level's
  count and the row's. Its `random_seed` comes from the run's `--seed` (`data/entrypoints.py`,
  lines 51 and 65). The text, sent before the image (`backends/openai/request_handlers.py`, line
  1043), differs between rows and levels, so a request's prefix can match another's only in the
  chat template's tokens before it; but the first level of a run repeats the first level of any
  other run of the same seed, text and image alike.

So in [capacity-280](#capacity-280), [capacity-560](#capacity-560) and
[capacity-1120](#capacity-1120) the first level, 4 streams, sent images no earlier request had,
and each later level resent the earlier levels' first images, which the row's multimodal cache
could serve again. capacity-1120's second run, at 1 and 2 streams, sent the first run's requests
again: its 1-stream level the 4-stream level's, text and image, and its 2-stream level the
8-stream level's.

## probe-280

The row at a budget of 280, the one it ran without `--mm-processor-kwargs.max_soft_tokens`, at
2026-11-25T13:33Z, without load. One request to `/v1/chat/completions` with the text
`Transcribe this page.` alone, then one for each of two PNG pages, a 1240×1754 and a 3705×4934,
sent as a base64 data URL before the same text, each with `max_tokens` 1; the figure is the reply's
`usage.prompt_tokens`, and an image's span is that less the text-only request's.

| Request | Prompt tokens | Image span |
| --- | --- | --- |
| Text only | 18 | - |
| 1240×1754 page | 286 | 268 |
| 3705×4934 page | 286 | 268 |

Both pages fill the budget alike: at 280 the larger page's resolution buys no more tokens.

## probe-560

The same requests at 2026-11-25T13:46:23Z, without load, the row restarted with
`--mm-processor-kwargs.max_soft_tokens 560`; its start reported a KV cache of 157,882 tokens,
19.27 requests of 8,192.

| Request | Prompt tokens | Image span |
| --- | --- | --- |
| Text only | 18 | - |
| 1240×1754 page | 552 | 534 |
| 3705×4934 page | 560 | 542 |

- **The image span doubles**: 534 and 542 tokens against 268 at [probe-280](#probe-280).
- The two pages' spans now differ by 8 tokens, so at 560 the span follows the page's shape, not
  only the budget.

## capacity-280

A same-day baseline for [capacity-560](#capacity-560): the row at a budget of 280, three levels of
[`bench/vision-capacity.yaml`](../../bench/vision-capacity.yaml) starting
2026-11-25T13:40:30Z. Each request took 478 or 479 prompt tokens. `tailscale ping gb10-2`, right
before the run, answered direct, 1 ms.

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8001 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/vision-capacity.yaml \
  --backend kind=openai_http,model=vision \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it \
  --output kind=json,path=.state/bench/vision-280-gb10-2-lan.json
```

`levels.jq` with `--arg purpose vision`:

| Streams | Start, UTC | ok/err/inc | req/s | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Latency min s | ≤ 10 s | Prompt tok/s | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 2026-11-25T13:40:30Z | 76/0/4 | 0.844 | 1,162 | 34.13 | 4.54 | 4.56 | 4.49 | 76/76 | 404 | 90 | meets |
| 8 | 2026-11-25T13:42:06Z | 112/0/8 | 1.244 | 2,123 | 41.48 | 6.23 | 6.26 | 5.98 | 112/112 | 596 | 90 | meets |
| 16 | 2026-11-25T13:43:42Z | 144/0/16 | 1.600 | 2,981 | 64.08 | 9.33 | 9.46 | 8.07 | 140/144 | 766 | 90 | meets |

- **Cap 16 meets the 10 s floor at 280**, a request latency median of 9.33 s against 10 s, as the
  spike's cell did on vLLM v0.33.0 beside an idle audio row: 6.11 s at 8 streams and 9.64 s at 16,
  133 of 144 in 10 s, TTFT median 3,049 ms (spike-model-layout `docs/findings/vllm-layout.md`,
  E.5, cell vllm-layout-g2-vision-capacity).

## capacity-560

The row at a budget of 560, the same three levels starting 2026-11-25T13:46:38Z, right after
[probe-560](#probe-560). Each request took 741 or 742 prompt tokens, 263 more than at 280.
`tailscale ping gb10-2`, right before the run, answered direct, 2 ms.

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8001 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/vision-capacity.yaml \
  --backend kind=openai_http,model=vision \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it \
  --output kind=json,path=.state/bench/vision-560-gb10-2-lan.json
```

`levels.jq` with `--arg purpose vision`:

| Streams | Start, UTC | ok/err/inc | req/s | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Latency min s | ≤ 10 s | Prompt tok/s | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 2026-11-25T13:46:38Z | 56/0/4 | 0.622 | 2,758 | 35.30 | 6.25 | 6.29 | 6.21 | 56/56 | 462 | 90 | meets |
| 8 | 2026-11-25T13:48:13Z | 72/0/8 | 0.800 | 3,376 | 63.02 | 9.60 | 10.05 | 7.22 | 64/72 | 594 | 90 | meets |
| 16 | 2026-11-25T13:49:49Z | 80/0/16 | 0.889 | 3,573 | 116.80 | 16.05 | 18.52 | 13.41 | 0/80 | 660 | 90 | misses |

The row's `/metrics` after the run, counting the probes: 211 requests finished, 0 preemptions.

- **Cap 16 misses the 10 s floor at 560**: a request latency median of 16.05 s at 16 streams, no
  request within 10 s. 8 streams meet it, 9.60 s, with 8 of 72 requests over 10 s.
- The cost is out of proportion to the tokens: 55 % more prompt tokens a request bring 0.56 times
  the requests a second at 16 streams, and an ITL median of 116.80 ms against 64.08 ms.

## probe-1120

The same requests at 2026-11-25T14:00:23Z, without load, the row restarted with
`--mm-processor-kwargs.max_soft_tokens 1120`; its start reported a KV cache of 159,645 tokens,
19.49 requests of 8,192.

| Request | Prompt tokens | Image span |
| --- | --- | --- |
| Text only | 18 | - |
| 1240×1754 page | 1,112 | 1,094 |
| 3705×4934 page | 1,122 | 1,104 |

- **The image span doubles again**: 1,094 and 1,104 tokens against 534 and 542 at
  [probe-560](#probe-560).
- The two pages' spans differ by 10 tokens, the larger page again taking the more.

## capacity-1120

The row at a budget of 1120, the same three levels starting 2026-11-25T14:00:40Z, right after
[probe-1120](#probe-1120), then 1 and 2 streams in a further run starting 2026-11-25T14:05:49Z,
since 4 streams missed the 10 s floor. Each request took 1,314 or 1,315 prompt tokens, 573 more
than at 560. `tailscale ping gb10-2`, right before each run, answered direct, 1 ms and 2 ms.

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8001 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/vision-capacity.yaml \
  --backend kind=openai_http,model=vision \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it \
  --output kind=json,path=.state/bench/vision-1120-gb10-2-lan.json
```

The further run used an uncommitted copy of the scenario with `streams: [1, 2]`, written to
`.state/bench/vision-1120-low-gb10-2-lan.json`.

`levels.jq` with `--arg purpose vision`, the two runs' levels in one table:

| Streams | Start, UTC | ok/err/inc | req/s | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Latency min s | ≤ 10 s | Prompt tok/s | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2026-11-25T14:05:49Z | 17/0/1 | 0.189 | 1,843 | 32.45 | 5.06 | 5.06 | 5.05 | 17/17 | 248 | 90 | meets |
| 2 | 2026-11-25T14:07:25Z | 28/0/2 | 0.311 | 3,317 | 30.83 | 6.37 | 6.40 | 6.34 | 28/28 | 409 | 90 | meets |
| 4 | 2026-11-25T14:00:40Z | 32/0/4 | 0.356 | 5,378 | 38.15 | 10.89 | 10.91 | 10.82 | 0/32 | 468 | 90 | misses |
| 8 | 2026-11-25T14:02:15Z | 32/0/8 | 0.356 | 5,452 | 135.55 | 18.87 | 22.34 | 18.81 | 0/32 | 468 | 90 | misses |
| 16 | 2026-11-25T14:03:51Z | 29/0/16 | 0.322 | 7,321 | 293.01 | 36.35 | 52.89 | 34.40 | 0/29 | 424 | 90 | misses |

The row's `/metrics` after both runs, counting the probes: 141 requests finished, 0 preemptions.

- **Throughput peaks at 4 streams**: requests a second stop growing past 4, at 0.356 at 4 and at
  8 and 0.322 at 16, and the prompt throughput holds near 468 tokens a second from 4 streams up.
- 4 streams miss the 10 s floor at 1120, with a request latency median of 10.89 s and no request
  within 10 s. 2 streams meet it, 6.37 s, and 1 stream, 5.06 s.

## capacity-1120-clean

[capacity-1120](#capacity-1120) run again at 4 and 8 streams, on requests no earlier request sent
([synthetic-data](#synthetic-data)). Each level is its own run of
[`bench/vision-capacity.yaml`](../../bench/vision-capacity.yaml) with its streams as both seeds,
as [bench/README.md](../../bench/README.md#running-a-cell) gives, on a row with empty caches. The
row restarted at cap 16 through `hosting engine update vision` at 2026-11-25T16:30:14Z, and its
start reported a KV cache of 158,611 tokens, 19.36 requests of 8,192. Each request took 1,314 or 1,315
prompt tokens, as at capacity-1120. `tailscale ping gb10-2`, right before each run, answered
direct, 1 ms and 2 ms.

```sh
for streams in 4 8; do
  GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8001 \
    MISE_ENV=bench mise exec -- guidellm run -c bench/vision-capacity.yaml \
    --profile kind=concurrent,streams=$streams \
    --data kind=synthetic_text,prompt_tokens=200 \
    --data kind=synthetic_image,resolution=1440p,format=jpeg,output_tokens=100,seed=$streams \
    --seed kind=static,value=$streams \
    --backend kind=openai_http,model=vision \
    --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it \
    --output kind=json,path=.state/bench/vision-1120-clean-gb10-2-lan-$streams.json
done
```

`levels.jq` with `--arg purpose vision`:

| Streams | Start, UTC | ok/err/inc | req/s | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Latency min s | ≤ 10 s | Prompt tok/s | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 2026-11-25T16:31:25Z | 32/0/4 | 0.356 | 5,409 | 38.27 | 10.87 | 10.91 | 10.79 | 0/32 | 468 | 90 | misses |
| 8 | 2026-11-25T16:33:13Z | 32/0/8 | 0.356 | 9,176 | 99.47 | 19.01 | 20.77 | 18.86 | 0/32 | 468 | 90 | misses |

The row's caches, from `/metrics`' `vllm:mm_cache_*_total` and `vllm:prefix_cache_*_total`:

| Read | Multimodal hits/queries | Prefix hits/queries, tokens |
| --- | --- | --- |
| Before 4 streams | 0/0 | 0/0 |
| After 4 streams | 0/36, 0% | 0/47,339, 0% |
| After 8 streams | 0/76, 0% | 0/99,938, 0% |

The row finished 64 requests, all at `max_tokens`, with 0 preemptions.

- **capacity-1120 was not inflated.** Without any cache reuse, 4 and 8 streams give the same
  0.356 requests a second as capacity-1120's one-run sweep, and request latency medians within 1%
  of it: 10.87 s against 10.89 s at 4 streams, 19.01 s against 18.87 s at 8. The latency's split
  differs at 8 streams, a TTFT median of 9,176 ms against 5,452 and an ITL median of 99.47 ms
  against 135.55. 2 and 16 streams were not run again, since 4 and 8 didn't change, and
  capacity-280 and capacity-560 were not run again.
- **Throughput still peaks at 4 streams**: 8 streams add nothing and take 1.7 times the latency.

## Comparison

The table gives each budget's request size in
[`bench/vision-capacity.yaml`](../../bench/vision-capacity.yaml) and its request latency median at
each level against the 10 s floor. A dash marks a level the budget didn't run.

| Budget | Prompt tokens a request | 1 stream | 2 streams | 4 streams | 8 streams | 16 streams |
| --- | --- | --- | --- | --- | --- | --- |
| 280 | 478 to 479 | - | - | 4.54 s, meets | 6.23 s, meets | 9.33 s, meets |
| 560 | 741 to 742 | - | - | 6.25 s, meets | 9.60 s, meets | 16.05 s, misses |
| 1120 | 1,314 to 1,315 | 5.06 s, meets | 6.37 s, meets | 10.89 s, misses | 18.87 s, misses | 36.35 s, misses |

## start-1120

The row's starts on vLLM v0.34.0 at its image budget of 1120, the fraction's cell, read as
spike-model-layout's E.1 read it (`docs/findings/vllm-layout.md`): the KV cache the start
reports, and the host's lowest MemAvailable through the start, sampled every second over ssh until
the row's `/health` answered. Each start replaced or restarted the row on gb10-2, the gateway's
stack running beside it and no other row.

| Start, UTC | How | Settings | KV cache, tokens | Requests of 8,192 | Lowest MemAvailable, GiB |
| --- | --- | --- | --- | --- | --- |
| 2026-11-26T04:13:04Z | `hosting engine update vision` | cap 8, queue limit 32 | 159,158 | 19.43 | 60.65 |
| 2026-11-26T04:14:32Z | `docker restart vllm-vision` | cap 8, queue limit 32 | 159,280 | 19.44 | 66.06 |

The cap of 8 is the top level of [dense-1120](#dense-1120), set by `hosting profile set vision
cap=8` in the host's clone, uncommitted, before the first start. Each start's weights took 18.13
GiB, and its KV cache 26.64 GiB. The starts of [layout](#layout) add their readings at the row's
settings.

- **The fraction holds on v0.34.0**: at 0.40 the KV cache holds 19.4 requests of 8,192, over the
  cap of 8, against 162,699 tokens on v0.33.0 (spike-model-layout E.1), and MemAvailable stays at
  least 48 GiB above the GB10's floor of 12.2.

## probe-1120-committed

[probe-1120](#probe-1120)'s requests at 2026-11-26T04:14:21Z, from the committed probe pages, the
row just started at cap 8 ([start-1120](#start-1120)), without load:

```sh
bench/vision-probe.sh --host gb10-2
```

| Request | Prompt tokens | Image span |
| --- | --- | --- |
| Text only | 18 | - |
| 1240×1754 page | 1,112 | 1,094 |
| 3705×4934 page | 1,122 | 1,104 |

- **The spans match probe-1120's**, 1,094 and 1,104 tokens: the committed pages, a CFR page at
  probe-1120's two sizes but not its content, take the same spans, as Gemma 4's processor fits a
  page by its size ([bench/README.md](../../bench/README.md#the-vision-probe)). There is no
  difference to note.

## dense-1120

The row alone on docinfer's dense pages, [`bench/vision-dense.yaml`](../../bench/vision-dense.yaml):
the 110 pages whose replies ran past `max_tokens` in docinfer's first acceptance run, as docinfer
sends them, each row its own page, with Gemma 4's card sampling and replies of up to 2,048 tokens
([bench/README.md](../../bench/README.md#docinfers-inputs)). The row at cap 8 (`--max-num-seqs 8`,
`--max-num-queued-reqs 32`), fraction 0.40, context 8,192, its budget 1120, restarted at
2026-11-26T04:14:32Z ([start-1120](#start-1120)); `tailscale ping gb10-2` direct, 0 ms. Each level
ran on its own, 10 min a level, from 2026-11-26T04:15:25Z:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-2 --alias vision \
  --scenario bench/vision-dense.yaml --cell vision-dense-gb10-2 2:60 4:100 8:160
```

`levels.jq` with `--arg purpose vision`; images a minute is the second-half rate, the requests
that finished in the level's last 300 s over 300 s, times 60
([bench/README.md](../../bench/README.md#reading-the-results)):

| Streams | Start, UTC | ok/err/inc | req/s | Second-half req/s | Images a minute | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Prompt tok/s | Output tok/s | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2 | 2026-11-26T04:15:30Z | 33/0/2 | 0.055 | 0.057 | 3.40 | 1,940 | 32.42 | 31.91 | 46.21 | 62 | 53.77 | 600 |
| 4 | 2026-11-26T04:25:37Z | 53/0/4 | 0.088 | 0.097 | 5.80 | 1,959 | 42.14 | 39.81 | 52.93 | 100 | 86.83 | 600 |
| 8 | 2026-11-26T04:35:43Z | 75/0/8 | 0.125 | 0.137 | 8.20 | 2,013 | 58.02 | 56.37 | 74.85 | 142 | 123.70 | 600 |

Across the three levels, 0 of 175 requests' pages hit the multimodal cache and 0 of 198,679 prompt
tokens the prefix cache; the row finished 161 requests, 159 on `stop` and 2 at the 2,048-token
bound, with 0 preemptions. Each request took 1,135 prompt tokens on average, and its reply 983
output tokens, from 186 to 2,048. The host's lowest MemAvailable over the cell was 63.62 GiB,
sampled every 10 s. Every level misses the 10 s floor, which doesn't set the cap.

- **Throughput rises to 8 streams, the top level**: 3.40 images a minute at 2 streams, 5.80 at 4
  and 8.20 at 8, 41% over 4. The replies are long, so the row is bound by decoding: output
  throughput rises with the streams, as the ITL median grows from 32 to 58 ms. A level past 8 may
  clear more; the cell's levels end at 8.
- At 4 streams, the earlier cap, the row clears 5.80 images a minute, against docinfer's re-probe's
  5.44 there.
- A page's latency median grows from 32 s at 2 streams to 56 s at 8, its p90 to 75 s: a client's
  timeout for one dense page sits above that.

## dense-noise

The run noise: [dense-1120](#dense-1120)'s throughput peak, 8 streams, run again from a restart at
2026-11-26T05:36:05Z, as [the verdict](../upgrades.md#the-verdict) asks, after [layout](#layout),
at cap 8 and a queue limit of 64. Its start read a KV cache of 160,496 tokens, and MemAvailable fell
no lower than 66.01 GiB through it; `tailscale ping gb10-2` direct, 0 ms.

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-2 --alias vision \
  --scenario bench/vision-dense.yaml --cell vision-dense-noise-gb10-2 8:160
```

| Streams | Start, UTC | ok/err/inc | req/s | Second-half req/s | Images a minute | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Output tok/s | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 8 | 2026-11-26T05:36:58Z | 75/0/8 | 0.125 | 0.137 | 8.20 | 1,986 | 58.82 | 57.04 | 84.00 | 123.97 | 600 |

The row finished 75 requests, 73 on `stop` and 2 at the 2,048-token bound, with 0 preemptions,
and 0 pages hit the multimodal cache; the host's lowest MemAvailable over the cell was 64.17 GiB.
Its rows were the cell's first 160, the pages [dense-1120](#dense-1120)'s 2 and 4 streams sent.

- **The repeat reads the same**: 8.20 images a minute, as dense-1120's 8 streams, on other pages.
  One request more or less in a level's second half moves the rate by about 2.4%, and
  [layout](#layout)'s 8 streams read 8.00, 2.5% under: 2.5% is the host's run noise.

## layout

The standing layout cell: the four rows together, each on its own host, the vision row through
[dense-1120](#dense-1120)'s levels, the agent row at its target of 4 sessions, the audio row at its
target of 48 streams of docinfer's windows, and the embedding row at 78 requests a second with at
most 16 in flight. Each row's figures are read against its row-alone cell here and in its
purpose's findings: [agent](agent.md#layout), [audio](audio.md#layout) and
[embedding](embedding.md#layout).

The cell is three rounds, one a vision level, since each cell starts on a row restarted since its
last ([bench/README.md](../../bench/README.md#running-a-cell)). Each round restarts the four rows
together, `docker restart` of `vllm-agent` on gb10-1, `vllm-vision` on gb10-2, `vllm-audio` on
`framework` and `vllm-embed` on `framework-2`, then starts the four cells at once from the laptop
on the LAN, the other three held for the vision level's 600 s with `--seconds 600`. `tailscale
ping` to each host answered direct, 0 or 1 ms, before each round. The rows ran as the profiles
render them, but vision at cap 8 with a queue limit of 64 and audio at cap 48 with a queue limit
of 192, set by `hosting profile set` in each host's clone, uncommitted, and applied by `hosting
engine update` before the first round: the values the profiles now hold. The round at 2 streams:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-2 --alias vision \
  --scenario bench/vision-dense.yaml --cell layout-v2-vision-gb10-2 2:60 &
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 --alias agent \
  --scenario bench/agent-sessions.yaml --cell layout-v2-agent-gb10-1 --seconds 600 4 &
MISE_ENV=bench mise exec -- bench/cell.sh --host framework --alias audio \
  --scenario bench/audio-real-30s.yaml --cell layout-v2-audio-framework --seconds 600 48:1500 &
MISE_ENV=bench mise exec -- bench/cell.sh --host framework-2 --alias embedding \
  --scenario bench/embedding-target.yaml --cell layout-v2-embedding-framework-2 --seconds 600 78 &
wait
```

The rounds at 4 and 8 streams ran the same with `layout-v4` and `4:100`, and `layout-v8` and
`8:160`. The rounds ran from 2026-11-26T05:02:38Z to 05:12:58Z, 05:14:07Z to 05:24:28Z, and
05:25:34Z to 05:35:55Z.

The vision row, `levels.jq` with `--arg purpose vision`, against [dense-1120](#dense-1120)'s row
alone:

| Streams | Start, UTC | ok/err/inc | Second-half req/s | Images a minute | Alone | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Output tok/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2 | 2026-11-26T05:02:44Z | 33/0/2 | 0.060 | 3.60 | 3.40 | 1,944 | 32.61 | 33.73 | 49.53 | 54.42 |
| 4 | 2026-11-26T05:14:13Z | 53/0/4 | 0.090 | 5.40 | 5.80 | 1,953 | 42.38 | 40.23 | 55.23 | 84.18 |
| 8 | 2026-11-26T05:25:40Z | 75/0/8 | 0.133 | 8.00 | 8.20 | 1,990 | 58.75 | 57.38 | 81.92 | 125.22 |

Each round's start read a KV cache of 160,253, 158,246 and 159,402 tokens, 19.3 to 19.6 requests
of 8,192, and the host's lowest MemAvailable was 66.00 GiB through the starts and 64.39 GiB through
the cells. Across the rounds, 0 of the vision requests' pages hit the multimodal cache, and the
row finished every request with 0 preemptions; at 4 and 8 streams, 1 and 3 replies reached the
2,048-token bound.

- **The vision row beside the others matches it alone**: 8.00 images a minute at 8 streams
  against 8.20, within [dense-noise](#dense-noise)'s 2.5%. At 2 and 4 streams, with fewer requests
  in a level's second half, 3.60 and 5.40 against 3.40 and 5.80, one request apart at 2 streams
  and two at 4. Throughput still peaks at 8 streams, the top level.
- The other rows read the same beside it as alone: the agent's ITL median 49.26 to 49.48 ms at 4
  sessions against 49.94, audio 2.013 to 2.040 requests a second at 48 streams against 2.044 and
  2.133, and embedding 77.11 to 77.87 against 77.96, as their sections give.
