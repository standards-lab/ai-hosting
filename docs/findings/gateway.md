# Gateway findings

The measurements behind the gateway's per-key settings, its overflow to Azure AI Foundry, and its
route timeouts, each taken through the gateway on gb10-2 with the keys it issues. Each section is
one cell: its command, its time in UTC, its figures, and the tool versions it ran on.
[The gateway document](../gateway.md) holds the settings' reasoning and cites the cells by their
section; the settings live in agentgateway's config template,
[`compose/agentgateway/config.template.yaml`](../../compose/agentgateway/config.template.yaml).

Two keys ran the cells: ai-hosting's own, consumer `ai-hosting` in the bulk class, from
ai-hosting's `fnox.toml`, and go-ai's, consumer `go-ai` in the interactive class, from go-ai's
`fnox.toml`, which [the gateway document](../gateway.md#keys) names. No key is printed here. Each
key was read once with `fnox get AI_GATEWAY_TOKEN`, in its repository, into a file of mode 0600 in
a scratch directory, `bulk.key` and `interactive.key`, which the commands read.

## Tools

| Tool | Version |
| --- | --- |
| agentgateway | v1.7.0, `cr.agentgateway.dev/agentgateway`, the stack's pin |
| vLLM | v0.34.0, each row as its class profile renders it |
| GuideLLM | 0.8.1, in the bench environment ([bench/README.md](../../bench/README.md)) |
| curl | 8.23.0, the laptop's |

The client is the laptop on the LAN, `tailscale ping gb10-2` direct.

## gateway-buckets

Each key's request bucket on the chat routes, 600 a minute for bulk and 1,200 for any other key,
from 2026-11-26T11:27:33Z. `GET /<alias>/v1/models` draws on the route's bucket like any request,
and the gateway answers it itself, so the cell spends no row's time. Each run sent its requests 32
at a time with `xargs -P 32`, within the same second:

```sh
seq 610 | xargs -P 32 -I{} curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $(<bulk.key)" http://gb10-2:3000/vision/v1/models | sort | uniq -c
```

after 3 single requests with the same key, then 1,210 with `interactive.key` on the same route,
then 610 with `bulk.key` on `agent`:

| Key, class | Route | Sent | 200 | 429 |
| --- | --- | --- | --- | --- |
| `ai-hosting`, bulk | vision | 3 + 610 | 600 | 13 |
| `go-ai`, interactive | vision | 1,210 | 1,200 | 10 |
| `ai-hosting`, bulk | agent | 610 | 600 | 10 |

- **Each bucket binds at its size.** Bulk got 429 past its 600th request on a route and the
  interactive key past its 1,200th. The first reply read `x-ratelimit-limit: 600`,
  `x-ratelimit-remaining: 597` and `x-ratelimit-reset: 59`; the 429 on `agent` read
  `retry-after: 39` and `x-ratelimit-remaining: 0`.
- **Each key and each route draws on its own bucket.** The bulk key, spent on vision, had its full
  600 on agent, and go-ai's key got 200 on agent while bulk's agent bucket was spent.

## gateway-priority-vision

Bulk's priority on the vision row, from a restart of `vllm-vision` at 2026-11-26T11:45:23Z (KV
cache 273,330 tokens at the row's settings: cap 32, queue limit 64, fraction 0.55): 60 streams of
[`bench/vision-dense.yaml`](../../bench/vision-dense.yaml)'s pages under the bulk key through the
gateway, 600 s, and 120 s in, at 11:48:23Z, four single dense pages sent at once from the rows the
cell doesn't reach, a streamed and an unstreamed one under each key, each with docinfer's request
(`max_tokens` 2,048, `temperature` 1.0, `top_p` 0.95, `top_k` 64). The row's running and waiting
gauges and its preemption counter were read every 2 s.

```sh
AI_GATEWAY_TOKEN=$(<bulk.key) MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-2 \
  --alias vision --scenario bench/vision-dense.yaml --cell gateway-priority-vision \
  --gateway gb10-2 60:240
```

The bulk load, `levels.jq` with `--arg purpose vision`:

| Streams | Start, UTC | ok/err/inc | Second-half req/s | Images a minute | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Latency max s | Output tok/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 60 | 2026-11-26T11:46:29Z | 111/0/60 | 0.217 | 13.00 | 138,804 | 141.25 | 265.24 | 323.29 | 440.03 | 177.67 |

The probes, timed from their send to their first token (the stream's first data line) and to their
reply's end, the streamed ones to the whole second:

| Probe | Key, class | Streamed | First token s | Reply s | Completion tokens |
| --- | --- | --- | --- | --- | --- |
| int-st | `go-ai`, interactive | yes | 20 | 142 | |
| int-ns | `go-ai`, interactive | no | | 149.7 | 887 |
| bulk-st | `ai-hosting`, bulk | yes | 137 | 198 | |
| bulk-ns | `ai-hosting`, bulk | no | | 281.9 | 959 |

The row ran at most 32 requests and held at most 32 waiting, with 0 preemptions over the cell.

- **Interactive waits behind no bulk request.** The interactive page's first token came 20 s after
  it was sent, the bulk page's sent at the same moment 137 s after, as long as the bulk load's own
  TTFT median of 139 s: bulk waited behind the 28 or so bulk requests ahead of it, interactive
  behind none.
- **Priority orders the queue; it doesn't preempt.** The interactive pages started only as running
  bulk requests finished: the row never ran more than 32 and its preemption counter stayed 0. Once
  running, a page decodes at the batch's pace, so the interactive page took 142 s to its last
  token beside 31 bulk ones, against its 20 s to the first.
- **Through the gateway the row holds its rate**: 13.00 images a minute, against 13.40 alone at 32
  streams and 13.00 in the layout ([vision.md#dense-1120-high](vision.md#dense-1120-high),
  [vision.md#layout](vision.md#layout)).

### The queue limit counts running requests

A first attempt, at 11:40:45Z, ran 94 streams, sized for 32 running and 62 waiting. vLLM v0.34.0's
`--max-num-queued-reqs` caps the row's unfinished requests, running and waiting together
(`check_admission` in `vllm/v1/engine/async_llm.py`), so the vision row holds 64 in flight, 32
waiting at most, not 64. The row refused the excess with 503: 5 refusals reached the gateway as
503 and evicted the row, and the 161 requests GuideLLM sent in the evictions' windows went to
Azure, which refused each with 400 for docinfer's fields (`max_tokens`, `top_p`, `top_k`; see
[gateway-overflow-shapes](#gateway-overflow-shapes)). The other refusals came inside a streamed
reply: its headers read 200, and its one event was the 503 error, so the gateway neither retried
nor counted them. The attempt was stopped by hand at about 11:44Z, and the cell above ran from a restart with
60 streams, within the 64.

## gateway-dense-page

The unstreamed bulk page of [gateway-priority-vision](#gateway-priority-vision), sent behind about
28 waiting pages, completed through the gateway in 281.9 s, its 959 completion tokens with it,
under the vision route's `requestTimeout` of 9 min. Its headers came with its reply, 281.9 s after
it was sent, where each streamed probe's headers came at once. The bulk load's slowest page took
440 s, at the row's full 64 in flight.

## gateway-priority-agent

Bulk's priority on the agent row, from a restart of `vllm-agent` at 2026-11-26T11:52:04Z: 20
sessions of [`bench/agent-sessions.yaml`](../../bench/agent-sessions.yaml) under the bulk key
through the gateway, 240 s, filling the row's 12 and leaving 8 waiting, within its 24 in flight.
75 s in, at 11:54:25Z, one streamed chat under each key at once, `max_tokens` 256, and another pair
60 s later.

```sh
AI_GATEWAY_TOKEN=$(<bulk.key) MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 \
  --alias agent --scenario bench/agent-sessions.yaml --cell gateway-priority-agent \
  --gateway gb10-2 --seconds 240 20
```

| Sessions | Start, UTC | ok/err/inc | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Output tok/s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 20 | 2026-11-26T11:53:18Z | 47/0/20 | 33,204 | 91.68 | 83.34 | 126.89 | 100.27 |

| Probe | Sent, UTC | Key, class | First token s | Reply s |
| --- | --- | --- | --- | --- |
| int-st | 11:54:25 | `go-ai`, interactive | 2.53 | 28.95 |
| bulk-st | 11:54:25 | `ai-hosting`, bulk | 16.55 | 34.70 |
| int2-st | 11:55:25 | `go-ai`, interactive | 0.50 | 12.16 |
| bulk2-st | 11:55:25 | `ai-hosting`, bulk | 21.90 | 40.89 |

The row ran at most 12 and held at most 18 waiting, with 0 preemptions.

- **Interactive goes first here too**: its first token in 0.5 and 2.5 s, bulk's in 16.6 and 21.9 s
  beside it, and the bulk load's TTFT median 33.2 s. As on vision, no running turn was preempted.
- A run before it, from 11:47:44Z, sent one pair whose probe timed only the whole reply, 26.9 s
  interactive against 28.8 s bulk; it is not counted.

## gateway-overflow-shapes

What Azure's deployments refuse of the bench's and docinfer's requests, read directly from each
deployment on 2026-11-26 before the overflow cells, each a 400:

| Deployment | Refuses | From |
| --- | --- | --- |
| `gpt-oss-120b` | `ignore_eos` | GuideLLM, on a scenario with fixed output tokens |
| `gpt-5-mini` | `max_tokens`, `top_p`, `top_k` | docinfer's request, and `vision-dense.yaml` |
| `gpt-audio-mini` | `stream_options.continuous_usage_stats` | GuideLLM, on every streamed request |

So the overflow cells run scenarios of their own, [`agent-overflow.yaml`](../../bench/agent-overflow.yaml),
[`vision-overflow.yaml`](../../bench/vision-overflow.yaml) and
[`audio-overflow.yaml`](../../bench/audio-overflow.yaml): each alias's load target and inputs,
unstreamed, without the refused fields, with vision's reply bound as `max_completion_tokens`.
docinfer's vision request as it stood got 400 on overflow; the gateway now rewrites each request for
its deployment ([gateway-overflow-rewrite](#gateway-overflow-rewrite)).

## gateway-overflow-agent

The agent alias at its target of 4 sessions with the row stopped, `docker stop vllm-agent` on
gb10-1 at 11:57:59Z, after a render that reset the gateway's eviction counts:

```sh
AI_GATEWAY_TOKEN=$(<bulk.key) MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 \
  --alias agent --scenario bench/agent-overflow.yaml --cell gateway-overflow-agent \
  --gateway gb10-2 --row-down 4
```

| Sessions | Start, UTC | ok/err/inc | req/s | Latency median s | Latency p90 s | Output tok/s | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 2026-11-26T11:58:06Z | 9/75/0 | 1.570 | 2.05 | 2.30 | 543.03 | 6 |

- **Every Azure reply carried the marker.** The access log read `overflow="azure"` on each of the
  12 replies from `agent-azure`, 9 of them 200 and 3 of them 429.
- **Azure's first 429 came 3.8 s in,** after 7 turns had finished: each turn read about 8,300 to
  9,700 prompt tokens, so the 100,000 tokens a minute of capacity 100 ran out in seconds. Azure
  ran a turn in 1.4 to 2.4 s, against the row's 26 s at 4 sessions
  ([agent.md#agent-sessions](agent.md#agent-sessions)).
- **Past it, the cell stopped on its count.** Two 429s evicted the Azure group, both groups were
  then out, and the gateway sent the next 72 requests to the stopped row, each a 503 within 2 s.
  GuideLLM counts a failed session's cancelled turns, so its 300 came at 6 s, with 84 requests at
  the gateway.
- **Back to the row:** `docker start vllm-agent` at 11:58:14Z, healthy at 11:59:16Z, and the
  first request after it, at 11:59:17Z, was the row's, with no marker.

## gateway-overflow-vision

The vision alias at its cap of 32 with the row stopped, `docker stop vllm-vision` at 11:59:59Z,
after a render:

```sh
AI_GATEWAY_TOKEN=$(<bulk.key) MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-2 \
  --alias vision --scenario bench/vision-overflow.yaml --cell gateway-overflow-vision \
  --gateway gb10-2 --row-down 32:300
```

| Streams | Start, UTC | ok/err/inc | req/s | Images a minute | Latency median s | Latency p90 s | Output tok/s | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 32 | 2026-11-26T12:00:05Z | 86/12/32 | 0.956 | 57.33 | 28.26 | 37.85 | 1,812.39 | 90 |

- **Every Azure reply carried the marker**, 86 of 86, and the cell ended on its 90 s: no 429 came,
  though the 86 pages, about 956 prompt and 1,897 completion tokens each, reasoning among them,
  ran past capacity 50's 50 requests and 50,000 tokens a minute.
- **The 12 errors are the stopped row's.** A page's body is over 64 KiB, so the gateway doesn't
  retry it: 7 pages of the first burst reached the row before its eviction landed, and each time an
  eviction ended, at 10.7, 22.3, 37.8, 60.1 and 85.4 s, one page went to the row again and got 503,
  each eviction 5 s longer than the last.
- **Azure runs a page far faster than the row:** 57.3 images a minute at 32 streams against the
  row's 13.40.
- **Back to the row:** `docker start` at 12:01:37Z, healthy at 12:02:27Z, the first request after
  it the row's.

## gateway-overflow-audio

The audio alias at its cap of 48 with the row stopped, `docker stop vllm-audio` on `framework` at
12:02:58Z, after a render:

```sh
AI_GATEWAY_TOKEN=$(<bulk.key) MISE_ENV=bench mise exec -- bench/cell.sh --host framework \
  --alias audio --scenario bench/audio-overflow.yaml --cell gateway-overflow-audio \
  --gateway gb10-2 --row-down 48:300
```

| Streams | Start, UTC | ok/err/inc | req/s | Second-half req/s | Latency median s | Latency p90 s | RTFx median | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 48 | 2026-11-26T12:03:04Z | 271/29/0 | 8.008 | 9.102 | 5.22 | 6.35 | 5.60 | 34 |

- **The cell stopped at its 300 requests,** 34 s in, with no 429: 271 windows on Azure, about 368
  prompt and 83 completion tokens each, 8 a second against capacity 30's 30 requests each 10 s.
  Every Azure reply carried the marker, the 271 and the 7 GuideLLM cancelled at its count.
- **22 of the 29 errors are the stopped row's:** 20 windows of the first burst, then one at each of
  the first two evictions' ends. The other 7 are the requests GuideLLM cancelled at its count.
- **Back to the row:** `docker start` at 12:03:40Z, healthy at 12:04:40Z, the first request after
  it the row's.

## gateway-tokenize

Embedding's tokenize route under docinfer's load, four workers calling it back to back with a
472-token chunk, `{"model":"embedding","prompt":…,"add_special_tokens":true}`, under go-ai's key:
alone for 30 s from 2026-11-26T12:05:44Z, then for 120 s from 12:06:19Z beside the embedding row
at its load target through the cell runner, directly on the row:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host framework-2 --alias embedding \
  --scenario bench/embedding-target.yaml --cell gateway-tokenize-embedding --seconds 120 78
```

| Run | Tokenize calls a second | Tokenize median s | Tokenize p90 s | Embedding req/s | Embedding latency median s |
| --- | --- | --- | --- | --- | --- |
| Alone | 300.1 | 0.008 | 0.010 | | |
| Beside the target | 253.2 | 0.010 | 0.014 | 77.975 | 0.04 |

Every call answered 200. **Tokenize needs no bucket:** at 253 calls a second, over three times
docinfer's need at the embedding rate's 78 chunks a second, the embedding row held 77.975 requests
a second, against 77.963 alone ([embedding.md#e5-target](embedding.md#e5-target)).

## gateway-overflow-rewrite

Each client's own request through the gateway with its row stopped, once the Azure providers drop
what their deployments refuse (agentgateway's config template, the `ai` transformations on
`agent-azure`, `vision-azure` and `audio-azure`). Each ran under go-ai's interactive key: first
with the row up, then, after a render that reset the evictions and `docker stop` of the row, a
small chat to evict the row, the client's request, and after `docker start` small chats until one
came back without the marker.

| Alias | The client's request | Row up | Row stopped | Back to the row |
| --- | --- | --- | --- | --- |
| agent | Streamed chat, `max_tokens` 256, `ignore_eos`, `stop` null, `stream_options` with `continuous_usage_stats` | 200 at 12:49:41Z, 256 completion tokens | 200 at 12:49:58Z with `x-gateway-overflow: azure`, from `gpt-oss-120b`, 182 completion tokens | Healthy at 12:51:04Z, the next request the row's |
| vision | docinfer's: a dense page, unstreamed, `max_tokens` 2,048, `temperature` 1.0, `top_p` 0.95, `top_k` 64 | 200 at 12:51:10Z in 32.8 s, 952 completion tokens, `stop` | 200 at 12:51:51Z in 16.9 s with the marker, from `gpt-5-mini-2025-08-07`, 2,048 completion tokens, all reasoning, `length` | Healthy at 12:52:57Z, the next request the row's |
| audio | A 30 s window, streamed, `max_tokens` 512, `temperature` 0, `stream_options` with `continuous_usage_stats` | 200 at 12:53:02Z, 84 completion tokens | 200 at 12:53:16Z with the marker, 91 completion tokens of transcript | Healthy at 12:54:21Z, the next request the row's |

- **Each deployment takes the client's request.** Before the rewrite each of the three got 400
  ([gateway-overflow-shapes](#gateway-overflow-shapes)). The agent's reply stopped at 182 tokens,
  under its 256, so `ignore_eos` no longer reached Azure; vision's stopped at exactly 2,048, so
  `max_tokens` reached gpt-5-mini as `max_completion_tokens`.
- **The row's request is untouched:** the rewrite is on the Azure providers alone, and with the
  row up the agent's request generated its full 256 tokens under `ignore_eos`.
- **gpt-5-mini spends docinfer's bound on reasoning.** At its default effort it reasoned for all
  2,048 completion tokens on the dense page and returned no text, `finish_reason` `length`, where
  the row transcribed it in 952. A page that overflows needs a larger bound or a lower effort to
  come back transcribed.
- The small chat that evicted the audio row got 400 from Azure, which refuses a text-only chat on
  gpt-audio-mini.
