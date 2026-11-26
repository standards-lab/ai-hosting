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
| bulk-st | `ai-hosting`, bulk | yes | 137 | 332 | |
| bulk-ns | `ai-hosting`, bulk | no | | 281.9 | 959 |

The probes ran outside the cell runner, from a script that started the cell above in the
background, read the row's gauges, and sent the four probes 120 s in, as run, its scratch
directory dropped from the paths and its progress lines and cleanup left out:

```sh
sample.sh gb10-2:8001 run/samples & samp=$!
AI_GATEWAY_TOKEN=$(<bulk.key) MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-2 --alias vision \
  --scenario bench/vision-dense.yaml --cell gateway-priority-vision --gateway gb10-2 60:240 >run/cell.log 2>&1 & cell=$!
sleep 120
probe.sh interactive.key vision int-st.json int-st run &
probe.sh bulk.key vision bulk-st.json bulk-st run &
probe.sh interactive.key vision int-ns.json int-ns run &
probe.sh bulk.key vision bulk-ns.json bulk-ns run &
wait $cell
```

`probe.sh`, as run, times one request through the gateway, the key read from its file:

```sh
key=$1 alias=$2 body=$3 name=$4 out=$5
start=$(date +%s.%N)
if jq -e '.stream == true' "$body" >/dev/null; then
  printf 'Authorization: Bearer %s\n' "$(<"$key")" | curl -sN -H @- -H 'content-type: application/json' \
    --data-binary @"$body" -D "$out/$name.headers" "http://gb10-2:3000/$alias/v1/chat/completions" |
    while IFS= read -r line; do [[ $line == data:* ]] || continue; [[ -e $out/$name.first ]] || date +%s.%N >"$out/$name.first"; printf '%s\n' "$line"; done >"$out/$name.body"
  end=$(date +%s.%N)
  first=$(cat "$out/$name.first" 2>/dev/null || echo "$end")
  echo "$name start=$(date -ud @${start%.*} +%T) first_token_s=$(awk -v a="$first" -v b="$start" 'BEGIN{printf "%.2f", a-b}') total_s=$(awk -v a="$end" -v b="$start" 'BEGIN{printf "%.2f", a-b}') code=$(head -1 "$out/$name.headers" | cut -d' ' -f2) overflow=$(grep -i x-gateway-overflow "$out/$name.headers" | tr -d '\r' | cut -d' ' -f2)" >>"$out/summary"
else
  w=$(printf 'Authorization: Bearer %s\n' "$(<"$key")" | curl -s -H @- -H 'content-type: application/json' \
    --data-binary @"$body" -D "$out/$name.headers" -o "$out/$name.body" -w '%{http_code} %{time_starttransfer} %{time_total}' \
    "http://gb10-2:3000/$alias/v1/chat/completions")
  read -r code ttfb total <<<"$w"
  echo "$name start=$(date -ud @${start%.*} +%T) code=$code headers_s=$ttfb total_s=$total completion_tokens=$(jq -r '.usage.completion_tokens // "-"' "$out/$name.body" 2>/dev/null) overflow=$(grep -i x-gateway-overflow "$out/$name.headers" | tr -d '\r' | cut -d' ' -f2)" >>"$out/summary"
fi
```

and `sample.sh`, as run, reads the row's gauges every 2 s:

```sh
while :; do
  m=$(curl -s --max-time 2 "http://$1/metrics")
  printf '%s %s\n' "$(date -u +%T)" "$(awk '/^vllm:num_requests_running|^vllm:num_requests_waiting\{|^vllm:num_preemptions_total/{split($1,a,"{"); s[a[1]]+=$NF} END{printf "running=%d waiting=%d preempt=%d", s["vllm:num_requests_running"], s["vllm:num_requests_waiting"], s["vllm:num_preemptions_total"]}' <<<"$m")" >>"$2"
  sleep 2
done
```

The streamed probes' summary lines came out without their times, so their first tokens are read from
their `.first` files, less the send, and their replies from the gateway's request log, whose
`duration_ms` also gives the unstreamed probes' 149.7 and 281.9 s. Each probe's body is docinfer's
request on one dense page of the bench's inputs, rows 430 to 433 of `dense-pages.jsonl`
([bench/README.md](../../bench/README.md)). The command that built them wasn't kept; this one,
reconstructed, builds the same JSON, checked field by field against the bodies as sent:

```sh
body() { # body <row> <stream>: docinfer's request on dense page <row>
  sed -n "$(($1 + 1))p" .state/bench/docinfer/dense-pages.jsonl | jq -c --argjson stream "$2" \
    --rawfile img <(base64 -w0 .state/bench/docinfer/dense-pages/$(printf %05d "$1").png) \
    '{model: "vision", max_tokens: 2048, temperature: 1.0, top_p: 0.95, top_k: 64, stream: $stream,
      messages: [{role: "user", content: [{type: "text", text: .prompt},
        {type: "image_url", image_url: {url: ("data:image/png;base64," + $img)}}]}]}'
}
body 430 false >int-ns.json; body 431 false >bulk-ns.json
body 432 true >int-st.json; body 433 true >bulk-st.json
```

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
waiting at most, not 64. The row refused the excess with 503: 5 refusals reached the gateway as 503
and evicted the row, and the 161 requests GuideLLM sent in the evictions' windows went to Azure,
which refused each with 400 for docinfer's fields (`max_tokens`, `top_p`, `top_k`; see
[gateway-overflow-shapes](#gateway-overflow-shapes)). The other refusals came inside a streamed
reply: its headers read 200, and its one event was the 503 error, so the gateway neither retried nor
counted them. The attempt was stopped by hand at about 11:44Z, and the cell above ran from a restart
with 60 streams, within the 64.

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

The probes ran outside the cell runner, with the same script and `probe.sh` as
[gateway-priority-vision](#gateway-priority-vision)'s, as run, with the same paths and lines left
out:

```sh
sample.sh gb10-1:8000 run/samples & samp=$!
AI_GATEWAY_TOKEN=$(<bulk.key) MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 --alias agent \
  --scenario bench/agent-sessions.yaml --cell gateway-priority-agent --gateway gb10-2 --seconds 240 20 >run/cell.log 2>&1 & cell=$!
sleep 75
probe.sh interactive.key agent int-st.json int-st run &
probe.sh bulk.key agent bulk-st.json bulk-st run &
sleep 60
probe.sh interactive.key agent int-st.json int2-st run &
probe.sh bulk.key agent bulk-st.json bulk2-st run &
wait $cell
```

with `int-st.json` and `bulk-st.json` each:

```json
{"model":"agent","stream":true,"stream_options":{"include_usage":true},"max_tokens":256,"messages":[{"role":"user","content":"Write a short paragraph about lighthouses and their keepers."}]}
```

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

So the overflow cells run scenarios of their own,
[`agent-overflow.yaml`](../../bench/agent-overflow.yaml),
[`vision-overflow.yaml`](../../bench/vision-overflow.yaml) and
[`audio-overflow.yaml`](../../bench/audio-overflow.yaml): each alias's load target and inputs,
unstreamed, without the refused fields, with vision's reply bound as `max_completion_tokens`.
docinfer's vision request, sent unchanged, got 400 on overflow until the gateway rewrote each
request for its deployment ([gateway-overflow-rewrite](#gateway-overflow-rewrite)).

## The overflow stop point

Each overflow cell's load runs until Azure's first 429 or its 300th Azure request, whichever comes
first. GuideLLM can't stop on a reply's status, and its request count takes the stopped row's 503s
with Azure's requests, so each overflow scenario bounds the run by GuideLLM's own count, 300
requests, and by 90 s. The stop point is read from the gateway's request log afterwards, and each
cell's headline figures cover the window from its first request to that point; GuideLLM's figures
for the whole run follow as context.

The stop point is the arrival of Azure's first 429 reply, when a runner could have stopped, or the
send of the 301st Azure request, or else the run's last reply. In the window, an Azure request
counts as sent if it started before the stop point, and as answered if its 200 or 429 came by
then; the throughput is the answered 200s, and their prompt and completion tokens, over the
window's length. A request still in flight at the stop point, or sent after it, is past the stop
point. The request log is gb10-2's `request_logs` table, read on 2026-11-26 after the cells with
each cell's bounds (`from` and `to` in UTC: agent 11:58:00 to 11:58:20, vision 12:00:00 to
12:01:40, audio 12:03:00 to 12:03:40):

```sh
ssh gb10-2 "docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -P pager=off \
  -v from='2026-11-26 11:58:00+00' -v to='2026-11-26 11:58:20+00'" <window.sql
```

where `window.sql` read:

```sql
WITH cell AS (
  SELECT * FROM request_logs
  WHERE agentgateway_user = 'ai-hosting' AND started_at >= :'from' AND started_at < :'to'
), azure AS (
  SELECT * FROM cell WHERE gen_ai_provider_name = 'azure'
), stop AS (
  SELECT (SELECT min(started_at) FROM cell) AS t0,
         least((SELECT min(completed_at) FROM azure WHERE http_status = 429),
               (SELECT started_at FROM azure ORDER BY started_at OFFSET 300 LIMIT 1),
               (SELECT max(completed_at) FROM cell)) AS t1
)
SELECT to_char(t0 AT TIME ZONE 'UTC', 'HH24:MI:SS.MS') AS start,
       to_char(t1 AT TIME ZONE 'UTC', 'HH24:MI:SS.MS') AS stop,
       round(extract(epoch FROM t1 - t0), 2) AS window_s,
       count(*) FILTER (WHERE a.started_at < t1) AS azure_sent,
       count(*) FILTER (WHERE a.started_at < t1 AND a.attributes_json->>'overflow' = 'azure') AS marked,
       count(*) FILTER (WHERE a.http_status = 200 AND a.completed_at <= t1) AS ok,
       count(*) FILTER (WHERE a.http_status = 429 AND a.completed_at <= t1) AS r429,
       round(count(*) FILTER (WHERE a.http_status = 200 AND a.completed_at <= t1)
             / extract(epoch FROM t1 - t0), 3) AS req_s,
       round(sum(a.input_tokens + a.output_tokens) FILTER (WHERE a.http_status = 200 AND a.completed_at <= t1)
             / extract(epoch FROM t1 - t0), 1) AS tok_s,
       round(sum(a.output_tokens) FILTER (WHERE a.http_status = 200 AND a.completed_at <= t1)
             / extract(epoch FROM t1 - t0), 1) AS out_tok_s,
       (SELECT count(*) FROM cell c WHERE c.gen_ai_provider_name <> 'azure' AND c.started_at < t1) AS row_503
FROM azure a, stop GROUP BY t0, t1;

WITH cell AS (
  SELECT * FROM request_logs
  WHERE agentgateway_user = 'ai-hosting' AND started_at >= :'from' AND started_at < :'to'
), azure AS (
  SELECT * FROM cell WHERE gen_ai_provider_name = 'azure'
), stop AS (
  SELECT least((SELECT min(completed_at) FROM azure WHERE http_status = 429),
               (SELECT started_at FROM azure ORDER BY started_at OFFSET 300 LIMIT 1),
               (SELECT max(completed_at) FROM cell)) AS t1
)
SELECT CASE WHEN c.started_at < t1 THEN 'in flight at the stop' ELSE 'sent after the stop' END AS past_stop,
       c.gen_ai_provider_name AS provider, c.http_status AS status, count(*),
       to_char(max(c.completed_at) AT TIME ZONE 'UTC', 'HH24:MI:SS.MS') AS last_reply
FROM cell c, stop WHERE c.completed_at > t1
GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
```

The marker count reads the request log's `overflow` attribute, the access log's field. The access
log on agentgateway's stdout gave the same counts of each status and of the marker over each
cell's bounds.

## gateway-overflow-agent

The agent alias at its target of 4 sessions with the row stopped, `docker stop vllm-agent` on
gb10-1 at 11:57:59Z, after a render that reset the gateway's eviction counts:

```sh
AI_GATEWAY_TOKEN=$(<bulk.key) MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 \
  --alias agent --scenario bench/agent-overflow.yaml --cell gateway-overflow-agent \
  --gateway gb10-2 --row-down 4
```

To [the stop point](#the-overflow-stop-point), Azure's first 429, from the request log:

| Window, UTC | Window s | Azure requests | Marker | Azure 200 | Azure 429 | Azure req/s | Azure tok/s | Azure output tok/s | Row 503s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 11:58:06.850 to 11:58:10.674 | 3.82 | 11 | 11 | 7 | 1 | 1.830 | 16,117.2 | 546.0 | 0 |

The whole run, GuideLLM's figures:

| Sessions | Start, UTC | ok/err/inc | req/s | Latency median s | Latency p90 s | Output tok/s | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 2026-11-26T11:58:06Z | 9/75/0 | 1.570 | 2.05 | 2.30 | 543.03 | 6 |

- **Every Azure reply carried the marker,** in the window and past it: the access log read
  `overflow="azure"` on each of the 12 replies from `agent-azure`, 9 of them 200 and 3 of them 429.
- **Azure's first 429 came 3.8 s in,** after 7 turns had finished: each turn read about 8,300 to
  9,700 prompt tokens, so the 100,000 tokens a minute of capacity 100 ran out in seconds. Azure
  ran a turn in 1.4 to 2.4 s, against the row's 26 s at 4 sessions
  ([agent.md#agent-sessions](agent.md#agent-sessions)).
- **The run went 1.9 s past the stop point.** In flight at it were 2 turns that answered 200 by
  11:58:12.521 and a 429 sent at 11:58:10.617; one more request reached Azure after it, a 429.
  The 429s evicted the Azure group, both groups were then out, and the gateway sent the next 72
  requests to the stopped row, each a 503, all within 1.9 s, to 11:58:12.577. GuideLLM counts a
  failed session's cancelled turns, so its 300 came at 6 s, with 84 requests at the gateway; its
  req/s and output tok/s cover those 503s, where the window's cover Azure alone.
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

To [the stop point](#the-overflow-stop-point), from the request log. No 429 came and Azure had 118
requests, so the stop point is the run's last reply, at its 90 s:

| Window, UTC | Window s | Azure requests | Marker | Azure 200 | Azure 429 | Azure req/s | Images a minute | Azure tok/s | Azure output tok/s | Row 503s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 12:00:05.339 to 12:01:35.415 | 90.08 | 118 | 86 | 86 | 0 | 0.955 | 57.28 | 2,723.7 | 1,810.9 | 12 |

The whole run, GuideLLM's figures:

| Streams | Start, UTC | ok/err/inc | req/s | Images a minute | Latency median s | Latency p90 s | Output tok/s | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 32 | 2026-11-26T12:00:05Z | 86/12/32 | 0.956 | 57.33 | 28.26 | 37.85 | 1,812.39 | 90 |

- **The run is the window:** nothing ran past the stop point. The 32 pages without a marker are
  those in flight at 90 s, which GuideLLM cancelled at its duration, so no reply came for them.
- **Every Azure reply carried the marker**, 86 of 86, and no 429 came, though the 86 pages, about
  956 prompt and 1,897 completion tokens each, reasoning among them, ran past capacity 50's 50
  requests and 50,000 tokens a minute.
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

To [the stop point](#the-overflow-stop-point), Azure's first 429, from the request log:

| Window, UTC | Window s | Azure requests | Marker | Azure 200 | Azure 429 | Azure req/s | Azure tok/s | Azure output tok/s | Row 503s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 12:03:04.235 to 12:03:36.519 | 32.28 | 278 | 278 | 260 | 1 | 8.054 | 3,627.9 | 666.3 | 22 |

The whole run, GuideLLM's figures:

| Streams | Start, UTC | ok/err/inc | req/s | Second-half req/s | Latency median s | Latency p90 s | RTFx median | Duration s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 48 | 2026-11-26T12:03:04Z | 271/29/0 | 8.008 | 9.102 | 5.22 | 6.35 | 5.60 | 34 |

- **Azure's first 429 came 32.3 s in,** its reply held 4.1 s, with `retry-after: 30`: 7 windows
  sent from 28.2 to 29.1 s in got 429, after Azure had taken about 8 windows a second, of about
  368 prompt and 83 completion tokens each, against capacity 30's 30 requests each 10 s.
- **GuideLLM stopped sending first.** Its 300 took the stopped row's 22 503s, so its last request
  went at 29.1 s, 3.2 s before the stop point, with 278 on Azure. Past the stop point only replies
  came, to 12:03:38.074: 11 windows that answered 200 and the other 6 429s.
- **The 29 errors are 22 of the stopped row's and Azure's 7 429s:** 20 windows of the first burst
  went to the row, then one at each of the first two evictions' ends. Every Azure reply carried the
  marker, the 271 and the 7 429s.
- **Back to the row:** `docker start` at 12:03:40Z, healthy at 12:04:40Z, the first request after
  it the row's.

## gateway-tokenize

Embedding's tokenize route under docinfer's load, four workers calling it back to back with a
472-token chunk, `{"model":"embedding","prompt":…,"add_special_tokens":true}`, under go-ai's key:
alone for 30 s from 2026-11-26T12:05:44Z, then for 120 s from 12:06:19Z beside the embedding row
at its load target through the cell runner, directly on the row. The tokenize calls are a probe of
a route that takes no load of its own, not a bench load, so they ran outside the cell runner,
from a script, `load.sh`, as run, its scratch directory dropped from the paths:

```sh
end=$(( $(date +%s) + $1 ))
worker() { while (( $(date +%s) < end )); do printf 'Authorization: Bearer %s\n' "$(<interactive.key)" | curl -s -o /dev/null -H @- -H 'content-type: application/json' --data-binary @body.json -w '%{http_code} %{time_total}\n' http://gb10-2:3000/embedding/v1/tokenize; done; }
for i in 1 2 3 4; do worker >"$2.$i" & done; wait
```

Its two runs, reconstructed from their output files, `alone.1` to `.4` and `beside.1` to `.4`, and
their times, since the lines that started them weren't kept; the embedding side, as run:

```sh
load.sh 30 alone
load.sh 120 beside &
MISE_ENV=bench mise exec -- bench/cell.sh --host framework-2 --alias embedding \
  --scenario bench/embedding-target.yaml --cell gateway-tokenize-embedding --seconds 120 78
```

`body.json` is a fixed chunk of 470 common words, which the row counts as 472 tokens; the command
that wrote it wasn't kept. Each figure is read from the runs' output lines, one per call: the calls
over the run's seconds, and the medians and p90s of `time_total`.

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
came back without the marker. The steps are a script, `check.sh`, as run, its scratch directory
dropped from the paths:

```sh
alias=$1 host=$2 container=$3 port=$4 O=$alias; mkdir -p $O; log=$O/summary
send() { # send <body> <name>
  printf 'Authorization: Bearer %s\n' "$(<interactive.key)" | curl -s -H @- -H 'content-type: application/json' --data-binary @"$1" -D $O/$2.headers -o $O/$2.body -w '%{http_code} %{time_total}' http://gb10-2:3000/$alias/v1/chat/completions
}
small=$O/small.json; jq -nc --arg m $alias '{model:$m,max_tokens:16,messages:[{role:"user",content:"Say hi."}]}' >$small
echo "row up, client request $(date -u +%T): $(send $alias.json rowup) $(grep -i x-gateway-overflow $O/rowup.headers | tr -d '\r')" >>$log
ssh gb10-2 'cd ~/ai-hosting && bin/hosting gateway render >/dev/null 2>&1'; sleep 5
ssh $host "docker stop $container >/dev/null"; echo "row stopped $(date -u +%FT%TZ)" >>$log
echo "warm-up $(date -u +%T): $(send $small warm) $(grep -i x-gateway-overflow $O/warm.headers | tr -d '\r')" >>$log
echo "client request $(date -u +%T): $(send $alias.json azure) $(grep -i x-gateway-overflow $O/azure.headers | tr -d '\r')" >>$log
ssh $host "docker start $container >/dev/null"; echo "row started $(date -u +%FT%TZ)" >>$log
until curl -sf --max-time 3 http://$host:$port/health >/dev/null; do sleep 2; done; echo "row healthy $(date -u +%FT%TZ)" >>$log
for i in $(seq 1 60); do
  r=$(send $small back); m=$(grep -i x-gateway-overflow $O/back.headers | tr -d '\r')
  echo "probe $(date -u +%T): $r $m" >>$log
  [[ -n $m ]] || break; sleep 5
done
echo done >>$log
```

Its three runs, the arguments reconstructed from its usage line, `check <alias> <host> <container>
<port>`, and each run's summary, since the lines that started them weren't kept:

```sh
check.sh agent gb10-1 vllm-agent 8000
check.sh vision gb10-2 vllm-vision 8001
check.sh audio framework vllm-audio 8002
```

The agent's body, `agent.json`, as sent:

```json
{"model": "agent", "max_tokens": 256, "ignore_eos": true, "stop": null, "stream": true, "stream_options": {"include_usage": true, "continuous_usage_stats": true}, "messages": [{"role": "user", "content": "Write a short paragraph about lighthouses."}]}
```

Vision's, `vision.json`, is docinfer's request on row 436 of the bench's `dense-pages.jsonl`, and
audio's, `audio.json`, docinfer's on row 1998 of `windows-30.jsonl`
([bench/README.md](../../bench/README.md)). The commands that built them weren't kept; these,
reconstructed, build the same JSON, checked field by field against the bodies as sent, with
`body` the function of [gateway-priority-vision](#gateway-priority-vision):

```sh
body 436 false | jq -c 'del(.stream)' >vision.json
sed -n 1999p .state/bench/docinfer/windows-30.jsonl | jq -c \
  --rawfile wav <(base64 -w0 .state/bench/docinfer/windows-30/01998.wav) \
  '{model: "audio", max_tokens: 512, temperature: 0, stream: true,
    stream_options: {include_usage: true, continuous_usage_stats: true},
    messages: [{role: "user", content: [{type: "text", text: .prompt},
      {type: "input_audio", input_audio: {data: $wav, format: "wav"}}]}]}' >audio.json
```

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
- **gpt-5-mini spent docinfer's bound on reasoning.** At its default effort it reasoned for all
  2,048 completion tokens on the dense page and returned no text, `finish_reason` `length`, where
  the row transcribed it in 952. [gateway-overflow-minimal](#gateway-overflow-minimal) sets the
  vision provider's `reasoning_effort` to `minimal`.
- The small chat that evicted the audio row got 400 from Azure, which refuses a text-only chat on
  gpt-audio-mini.

## gateway-overflow-minimal

docinfer's dense page of [gateway-overflow-rewrite](#gateway-overflow-rewrite) again, once
`vision-azure` also sets `reasoning_effort` to `minimal`, the same steps under go-ai's interactive
key:

```sh
check.sh vision gb10-2 vllm-vision 8001
```

the [gateway-overflow-rewrite](#gateway-overflow-rewrite) script and body, its arguments
reconstructed the same way.

| Row up | Row stopped | Back to the row |
| --- | --- | --- |
| 200 at 13:25:31Z in 32.9 s, 1,137 prompt and 952 completion tokens, `stop` | 200 at 13:26:13Z in 9.6 s with `x-gateway-overflow: azure`, from `gpt-5-mini-2025-08-07`: 948 prompt and 971 completion tokens, 0 of them reasoning, `stop` | Healthy at 13:27:13Z, the next request the row's |

- **At minimal effort the bound is a bound on text**: Azure's reply is the page's transcription,
  971 tokens against the row's 952 under the same 2,048.
- **The two transcriptions match.** The opening lines read the same word for word, the page's
  running head and section number, then paragraphs (3) and (c) with its items (1) to (5); Azure's
  keeps the page's line breaks, where the row's runs each paragraph on one line.

## client-tiers

The client repositories' live tiers through the gateway, each under its own interactive key from
its own `fnox.toml`, which the repository's task sends as each role's bearer token: go-ai's
`integration` task at `c851963`, its tier and tools/infer's, and docinfer's `test:integration` at
`90ea79d`, on Go 1.27.4, from 2026-11-26T13:35:39Z to 13:38:37Z. The shell set each alias's base
URL, the tokenize route's among them:

```sh
export AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1
export AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1
export AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1
export AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1
export AI_TOKENIZE_BASE_URL=http://gb10-2:3000/embedding/v1
(cd go-ai && mise run integration)
(cd docinfer && mise run test:integration)
```

then docinfer's again with `AI_TOKENIZE_BASE_URL` unset, and go-ai's again under each alias's
profile, `AI_<ROLE>_PROFILE` set to the contents of ai-hosting's
[`go-ai/<alias>.json`](../../go-ai/README.md):

| Run | Package | Pass | Skip | Fail |
| --- | --- | --- | --- | --- |
| go-ai, the spec | `integration` | 106 | 4 | 0 |
| | `tools/infer/integration` | 79 | 5 | 0 |
| go-ai, the alias profiles | `integration` | 106 | 4 | 0 |
| | `tools/infer/integration` | 79 | 5 | 0 |
| docinfer | `integration` | 23 | 1 | 0 |
| | `cmd/docinfer/integration` | 14 | 0 | 0 |
| docinfer, no `AI_TOKENIZE_BASE_URL` | `integration` | 23 | 1 | 0 |
| | `cmd/docinfer/integration` | 14 | 0 | 0 |

Each count takes the tests and subtests together.

- **Every client passes through the gateway with its own key**, on all four aliases, with no
  failure. docinfer's run counted its tokens through the embedding alias's tokenize route, and with
  `AI_TOKENIZE_BASE_URL` unset found the same route from `AI_EMBEDDING_BASE_URL`.
- **The transcription route's scenarios skip:** `AI_TRANSCRIPTION_BASE_URL` was unset, since no
  row serves `/v1/audio/transcriptions`. The audio row transcribes by chat completions, which
  passed in each client. At 2026-11-26T13:43:34Z, under go-ai's key:

  ```sh
  curl -s -w ' %{http_code}\n' -X POST -H "Authorization: Bearer $(fnox get AI_GATEWAY_TOKEN)" \
    --form-string model=audio http://gb10-2:3000/audio/v1/audio/transcriptions
  ```

  answered the row's own `{"detail":"Not Found"}` with 404, and `audio/translations` the same.
- The other skips are go-ai's tests of a declared skip (`TestSkipDeclared_ThroughClient`,
  `TestSkipDeclared`, `TestDeclaredSkip`), whose subject is the skip itself.
