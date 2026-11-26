# The gateway

agentgateway v1.7.0 fronts the four vLLM rows from one compose stack on gb10-2, run from that
host's clone of ai-hosting by the `hosting gateway` group. Each alias has its own base URL,
`http://gb10-2:3000/<alias>/v1`, behind a key the `hosting key` group issues. This document holds
the gateway's requirements, the reasoning behind each setting and amount, how to issue keys and
operate the stack, and the gaps it leaves open. The files are the settings' one home:

- the stack: [`compose.yml`](../compose.yml), one [`compose/<service>.yml`](../compose) per
  service, and each service's `compose/<service>/Dockerfile`, whose `FROM` line is its pin;
- agentgateway's config:
  [`compose/agentgateway/config.template.yaml`](../compose/agentgateway/config.template.yaml), the
  key list [`keys.toml`](../compose/agentgateway/keys.toml), and the overflow switches
  [`overflow.toml`](../compose/agentgateway/overflow.toml), which `hosting gateway render` turns
  into `compose/agentgateway/config.yaml` with each row's port and model from the
  [class profiles](../classes/README.md);
- the commands: [`lib/gateway.sh`](../lib/gateway.sh), [`lib/gateway.jq`](../lib/gateway.jq), and
  [`lib/key.sh`](../lib/key.sh), behind `bin/hosting-gateway-*` and `bin/hosting-key-*`.

The gateway is built from spike-model-gateway at `2f2e8c1`, whose evidence this document cites
rather than copies: the findings [agentgateway.md][f-agentgateway], [routing.md][f-routing],
[priority.md][f-priority], and [answer.md][f-answer], and the candidate comparison
[comparison.md][comparison]. What agentgateway may change upstream that bears on this gateway is in
the [watch register](watch.md).

## Requirements

The requirements come from the coordinator's AI hosting note (standards-lab
`context/ai-hosting.md`, "The gateway" and "Overflow to Azure AI Foundry") and the gateway task:

1. **One base URL per alias.** `/<alias>/v1` on one consumer port for `agent`, `vision`, `audio`,
   and `embedding`, each sent to its alias's row ([Routes](#routes)).
2. **Gateway-issued keys.** A missing, unknown, or revoked key gets 401 on every path, before
   routing ([Keys](#keys)).
3. **Serving endpoints only.** Only the eight serving paths reach a row, and a path holding a dot
   segment is refused ([Routes](#routes)).
4. **Priority and buckets per key.** Each key gives its requests a vLLM priority and draws on its
   own request bucket; embedding is held to 78 requests a second. The gateway charges no token
   budget ([Limits and priority](#limits-and-priority)).
5. **Overflow to Azure AI Foundry** for agent, vision, and audio while the row is down or
   refusing, each reply marked `x-gateway-overflow: azure`; embedding has no cloud fallback, and
   nothing overflows under IL6 ([Overflow](#overflow)). Cloud spend is governed in Azure, by each
   deployment's capacity and a Cost Management budget
   ([Capacity and cloud spend](#capacity-and-cloud-spend)).
6. **Telemetry with no content.** Traces, metrics, and logs in the stack's own stores, and a
   request log in Postgres holding metadata only ([Telemetry](#telemetry)).
7. **No secret in the clone's rendered files.** The Foundry key and account come from ai-hosting's
   fnox when the stack starts ([Secrets and Postgres](#secrets-and-postgres)).
8. **No tailnet identifier committed.** Hosts go by short name; their addresses are looked up on
   gb10-2 at render ([Operating the stack on gb10-2](#operating-the-stack-on-gb10-2)).

Access control doesn't rest on the tailnet: production has none, and its routing service reaches
the stack another way. In development the rows stay reachable directly on the tailnet; making the
gateway the only network path to them is for production's networking and platform teams.

## The stack

One compose project, `gateway`, laid out as go-web-service's is at `2e31ca4`: the root
`compose.yml` names the project and includes one file per service, and each service builds from
its own directory, which carries its config. Every service is always on; no compose profile gates
the observability services.

| Service | Image | Publishes | Holds |
| --- | --- | --- | --- |
| agentgateway | `cr.agentgateway.dev/agentgateway` v1.7.0 | the consumer port, 3000, on gb10-2's tailnet address; the UI, 3001, on gb10-2's loopback | nothing; reads its config from the mounted directory |
| Postgres | `postgres` 19.0-alpine | nothing | the request log |
| OpenTelemetry Collector | `otel/opentelemetry-collector-contrib` | nothing | nothing |
| Tempo | `grafana/tempo` | nothing | traces, 24 h |
| Mimir | `grafana/mimir` | nothing | metrics |
| Loki | `grafana/loki` | nothing | logs |
| Grafana | `grafana/grafana` | 3002 on gb10-2's loopback | its own state |

agentgateway's admin API stays on the container's own loopback (`adminAddr: localhost:15000`), so
no published port reaches it, and its stats port, 15020, is reached only by the Collector on the
compose network. The UI listener is its own gateway, `ui`; the consumer gateway is named
`consumer`, not `default`, because the UI attaches itself to a gateway named `default` when
`ui.gateways` is unset.

agentgateway's config directory, `compose/agentgateway/`, is bind-mounted read-only, not baked
into an image: the render writes it on gb10-2, and agentgateway reloads it in place. The directory
is mounted, not the file, so the rename that moves a rendered copy into place reaches the
container. Its `storage` is `readOnly`, so the UI reads the config and a save from it answers 403:
no key or route is created outside git.

## Routes

One route per alias on the `consumer` gateway, and embedding's tokenize route
([Tokenize](#tokenize)). Each alias's route matches `/<alias>/v1` and below, rewrites the
prefix to `/v1`, and sends the request to one `ai` backend whose first priority group is the
alias's row: a custom provider at the row's host and port, over plain HTTP on the tailnet, listing
Chat Completions, Messages, Responses, and embeddings. The provider keeps the client's model, the
alias, which each row serves as its only model name. Nothing fails over between hosts: an alias's
backend holds its row and at most its own Azure deployment.

The map from alias to host has one home, the template's `hostOverride` on each row provider
(`gb10-1`, `gb10-2`, `framework`, `framework-2`); the render appends each row's port from the class
profiles, which name no host. A plain host backend names its alias instead of a host (`host:
embedding`), and the render gives it that alias's rendered row host and port.

### Route `ai`, not the `llm` section

agentgateway serves models two ways: an inline `ai` backend on a route, or the top-level `llm`
section. The gateway uses route `ai`. At v1.7.0 the `llm` section takes one path prefix for every
gateway it is attached to, so serving four aliases from it takes one port per alias, with each
model authorized on its own listener; the spike trialled that form and it passed
([routing.md][f-routing], "The trial", "Final verdict", and "Realignment on route `ai`").
agentgateway's docs recommend routing-based configuration for path-based LLM routing, and route
`ai` keeps the route's retries and priority groups. The UI labels an inline `ai` backend
"legacy", and the [watch register](watch.md#agentgateway-route-ai-backends-deprecated) tracks what
would move the gateway to `llm`.

### Serving paths and `/models`

Route policies run in a fixed order, the URL rewrite before the direct response, so the
allow-list sees `/v1/...`. The first conditional direct response whose condition holds answers:

- **`/v1/models`** is answered by the gateway itself, whether or not the row is up, in OpenAI's
  list shape: one model, `{"id":"<alias>","object":"model","owned_by":"gateway","root":"<model>"}`,
  the alias alone with `root` set to its row's model from the class profile. A client that takes
  the one listed model (go-ai's tier, the `infer` CLI) gets the alias during an overflow too, and
  go-ai's `Model.Native` carries the served model. `/v1/models/<id>` is left out: no client reads
  one model.
- **Any path off the allow-list** gets 404. The allow-list is the eight serving paths:
  `/v1/models`, `chat/completions`, `completions`, `messages`, `responses`, `embeddings`,
  `audio/transcriptions`, and `audio/translations`. vLLM's root routes (`/metrics`, `/health`,
  `/tokenize`, `/docs`) are among those refused, so no consumer key manages a model; embedding's
  tokenize route alone reaches one, `POST /tokenize` ([Tokenize](#tokenize)). A path under no
  alias is unrouted, and gets 404 too.

Chat Completions, embeddings, Messages, and Responses are typed request formats (`ai.routes`), so
the gateway sets each provider's model in the body and its path, which `detect` does for neither
on a JSON body, and adds `stream_options.include_usage` to every Chat Completions stream, so a
stream's usage is read whether or not the client asks. The keys are path suffixes, matched longest
first with `"*"` last; the rest stay `detect` ([agentgateway.md][f-agentgateway], "Behavior 3";
[priority.md][f-priority], "Answer for this task").

### Dot segments

agentgateway v1.7.0 matches the raw path and doesn't normalize dot segments: in the spike,
`/agent/v1/../../metrics`, `/agent/v1/%2e%2e/%2e%2e/metrics`, and `/agent/v1/..%2f..%2fmetrics`
each matched the agent route and reached gb10-1, where vLLM's own 404 protected its root routes
([agentgateway.md][f-agentgateway], "The paper inventory"). The consumer gateway's authorization
rule denies a path containing `..` or matching `%2e` or `%2f` in either case, before routing. It
refuses any `%2e` or `%2f`, a superset of the encoded dot segment, since no serving path holds
either. A network rule can't do this, since the requests come from the gateway itself.
agentgateway's path normalization (#4253) merged after v1.7.0
([watch register](watch.md#agentgateway-path-normalization)).

### Tokenize

`POST /embedding/v1/tokenize` reaches the embedding row's `/tokenize`, which vLLM serves at the
row's root, not under `/v1`. docinfer chunks documents by e5 token counts through go-ai's
`Tokenize`, which appends `tokenize` to the alias's base URL. The request is
`{"model":"embedding","prompt":"…","add_special_tokens":true}`, and the row's reply,
`{"count":N,"max_model_len":512,"tokens":[…]}`, passes through unchanged.

- **Its own route.** `embedding-tokenize` matches the exact path and POST alone, and rewrites the
  whole path to `/tokenize`. agentgateway ranks an exact path above any prefix, so the request never
  reaches the embedding route's allow-list; a GET, `/embedding/v1/detokenize`, and every other path
  still fall to the embedding route and its 404. No other alias has one.
- **A plain host backend,** the embedding row's host and port, with no `ai` backend: the reply is
  vLLM's own shape, not a model format, and there is no Azure group to fall back on.
- **The same key check.** The key and the dot-segment rule sit on the `consumer` gateway, so a
  missing or unknown key gets 401 here as on every route.
- **No bucket.** It is outside embedding's two buckets and has none of its own: a tokenize call is
  cheap, and a chunking run makes far more of them than it makes embeddings, so drawing on
  embedding's buckets would spend them on counting. A bulk consumer bounds its own concurrency.
  Acceptance measured no need for one: four callers back to back, docinfer's concurrency, made 253
  tokenize calls a second beside the embedding row at its load target, which held 77.98 requests a
  second against 77.96 alone ([gateway-tokenize](findings/gateway.md#gateway-tokenize)).

## Keys

Every request on the consumer port needs a gateway-issued key, sent as `Authorization: Bearer
<key>`, checked before any route is chosen (`apiKey.mode: strict`): a missing, unknown, or
revoked key gets 401, on alias routes and unrouted paths alike. The key is removed before the
request is forwarded, so no row or deployment sees it.

A key is 32 random bytes written as 64 lowercase hex digits. The key list,
[`compose/agentgateway/keys.toml`](../compose/agentgateway/keys.toml), holds one `[[keys]]` entry
per consumer: its name, its class (`interactive` or `bulk`), and the key's SHA-256 in lowercase
hex, which is how agentgateway hashes a presented key, over its exact characters with no newline
([agentgateway.md][f-agentgateway], "Keys"). The render expands each entry from its class's
template key, with the hash as `keyHash` and the consumer and class in its metadata, which every
per-key policy reads. The key itself lives only in the consumer repository's own age-encrypted
`fnox.toml`, as `AI_GATEWAY_TOKEN`, encrypted to that file's recipients.

The key procedure runs on the architect's laptop, beside the consumers' checkouts; the `key` verbs
run on any host and commit nothing.

1. **Issue.** `hosting key issue <consumer> <class> <repository>` validates the name, the class,
   the consumer's `fnox.toml` (exactly one age provider), and the key list, refusing a consumer
   the list already holds. It generates the key, writes it with `fnox set`, by stdin, into
   `<repository>/fnox.toml` as `AI_GATEWAY_TOKEN`, with a description if the variable has none,
   and only then writes the hash and class into the key list. No key is printed or put on a
   command line.
2. **Rotate.** `hosting key issue <consumer> <class> <repository> --rotate` replaces a held key:
   a new key in the consumer's `fnox.toml`, and the consumer's entry in the key list with its
   hash and class. The old key works until gb10-2 renders.
3. **Revoke.** `hosting key revoke <consumer>` deletes the consumer's entry, its hash, from the key
   list. It leaves the consumer's `fnox.toml` as it is; the key there stops working once gb10-2
   renders.
4. **List.** `hosting key list` prints each consumer the key list holds, with its class.
5. **Commit.** After an issue or a rotate, commit the consumer repository's `fnox.toml` there, and
   ai-hosting's `compose/agentgateway/keys.toml` here; after a revoke, the key list alone. Push
   both.
6. **Apply.** On gb10-2, pull ai-hosting's clone and run `hosting gateway render`. agentgateway
   reloads the keys in place, with no restart: a new key is admitted, and a removed one gets 401
   on its next request while requests already running finish.

go-ai and docinfer hold interactive keys. ai-hosting holds a bulk key, as consumer `ai-hosting` in
its own `fnox.toml`, kept for the bulk class's priority and bucket checks and for upgrade measures
through the gateway. Every other consumer gets its key from `hosting key issue` in the task that
builds it.

## Limits and priority

Each key's class, in its metadata as `apiKey.class`, sets its priority and its request bucket.

| Key class | Priority (agent, vision) | Request bucket, each chat route |
| --- | --- | --- |
| `interactive` | 0 | 1,200 a minute |
| `bulk` | 10 | 600 a minute |

No key has a token budget. The rows' own capacity bounds self-hosted work, and cloud spend is
governed in Azure ([Capacity and cloud spend](#capacity-and-cloud-spend)), so the gateway charges
no key for its tokens. Postgres keeps the request log, which records each request's usage.

### Priority

On the agent and vision rows' providers, `ai.transformations` sets each request's vLLM `priority`
from the key's class: 0 for interactive, 10 for bulk. Those two rows run `--scheduling-policy
priority` (their class profile), where a lower value is served first, so interactive work is taken
ahead of bulk's waiting requests. Every typed request to the two rows carries it, Messages too.

- The transformation sits on the row's provider, not the route, so a request Azure answers never
  carries it: each attempt of a retry starts again from the client's body, and the Azure provider
  has no transformation.
- The provider's policies are registered once the provider is chosen, before the request's
  snapshot, so `apiKey.class` is in the expression's context; the provider's `ai` policy merges
  field by field with the route's, so the route's typed formats still apply. An expression that
  fails, such as one with no key, leaves the field out.

In the spike, against a capturing mock row, bulk's chat reached the row with `"priority":10`, an
interactive key's with `0`, the audio row's with none, and bulk's chat sent while the row was
unreachable reached Azure with none ([priority.md][f-priority], "Answer for this task").

Live, with the rows full of bulk work through the gateway, an interactive request waited behind no
bulk one: on vision its first token came in 20 s where a bulk page sent with it waited 137 s, and
on agent in 0.5 and 2.5 s where bulk's waited 16.6 and 21.9 s. Priority orders vLLM's waiting
queue and doesn't preempt: the interactive request started only as a running bulk one finished,
and neither row preempted a request
([gateway-priority-vision](findings/gateway.md#gateway-priority-vision),
[gateway-priority-agent](findings/gateway.md#gateway-priority-agent)).

### Request buckets

On agent, vision, and audio, each key draws on a bucket of its own (`localRateLimit` keyed by
`apiKey.name`), so one key's refusals leave another's untouched. The first conditional entry whose
condition holds is the request's: bulk's 600 a minute, then every other key's 1,200. Each holds a
full minute's worth at once and is refilled each minute. Neither binds in normal use: the
heaviest bulk load the spike ran, vision at 20 concurrent, is about 1.9 requests a second, some 116
a minute, and an interactive key's, the audio overhead cell, 64 requests in about 20 s
([agentgateway.md][f-agentgateway], "The cap cells" and "Slice 2 · overhead"). In the spike, bulk
was refused by its own bucket while another key kept answering on the same alias
([priority.md][f-priority], "bulk's bucket (behavior 14)"). Live, ai-hosting's bulk key got 429
past its 600th request on a route and go-ai's interactive key past its 1,200th, each key and each
route drawing on its own bucket ([gateway-buckets](findings/gateway.md#gateway-buckets)).

Embedding has two rules: a global bucket of 78 a second, with no key, which every caller shares,
and a bucket of 156 a second per key. 78 is the most the embedding row keeps with no error on
framework-2, measured with the row alone, with no margin
([e5-rate-sweep](findings/embedding.md#e5-rate-sweep)). The per-key bucket is twice the global, so
the global binds first for any one key; a request either rule refuses counts against neither.
Embedding's clients send many small requests a second, so its buckets refill each second, where
the chat routes' refill each minute. Embedding's tokenize route draws on neither bucket
([Tokenize](#tokenize)).

A bucket counts each client request once, before the retry. Past it the gateway answers 429 with
`Retry-After` and `x-ratelimit-*` itself: the row never sees the request, so a bucket's 429 evicts
nothing and sends nothing to Azure. Buckets are local to the agentgateway process, and a reload
that changes a rule starts it full. The `Retry-After` reads as the whole seconds to the refill,
rounded down, so a client that waits exactly that long can be refused once more; a client's retry
policy allows one attempt more than the arithmetic gives ([answer.md][f-answer], "Step 5 · the
retry proof (behaviors 6–8)").

### Row refusals, retry, and health

Each row's vLLM answers 503 once its queue limit is full. The row's
[class profile](../classes/README.md#a-rows-keys) sets the limit, twice the row's cap unless the
profile gives a reason. At v0.34.0 the limit, `--max-num-queued-reqs`, counts the row's unfinished
requests, running and waiting together, so a row holds its queue limit in flight and its queue
limit less its cap waiting ([The queue limit counts running
requests](findings/gateway.md#the-queue-limit-counts-running-requests)). The gateway acts on that
refusal:

- **Retry.** Each route retries a 503 or a failed connection, `attempts: 2`, so a request is sent
  at most three times, each retry after a 20 ms backoff. The provider is chosen again on each
  attempt, and an eviction reaches the load balancer through a spawned task, so a retry sent at
  once can still find the row; the backoff lets the eviction land, so the refused request itself
  is carried to Azure. Against a mock row in the spike, with no backoff the request whose two 503s
  evicted the row got its third 503 from the row, and with 20 ms it went to Azure; benchmark
  C-agent showed it live, 18 of 18 ([priority.md][f-priority], "Benchmark C-agent (behavior 9)").
- **Row health.** A reply is unhealthy on 503 or a failed connection, which has no reply and so no
  `response.code`. Two in a row evict the row for 5 s, and each later eviction lasts 5 s times the
  evictions so far.
- **Azure health** is the row's with 429 added: Azure throttles a spent deployment with 429, and in
  benchmark C-agent an Azure group that stayed in rotation while it throttled took the alias's
  whole load during each row eviction. agentgateway's default for an `ai` backend of several groups
  would evict it on one 5xx or failed connection, for 3 s.

### Route timeouts

agentgateway v1.7.0 sets no request timeout unless a route's `timeout` policy gives one: its
`requestTimeout` runs from the request's arrival to the reply's headers, and doesn't bound a
streamed reply's body. A streamed reply's headers come as soon as the row takes the request, so
the timeout bounds a reply that isn't streamed, as docinfer's pages aren't
([gateway-dense-page](findings/gateway.md#gateway-dense-page)). Each route is checked against a
request at its row's limits: the last place of a full queue, which at v0.34.0 holds the queue limit
less the cap ([Row refusals, retry, and health](#row-refusals-retry-and-health)).

| Route | Before | After | A request at the row's limits |
| --- | --- | --- | --- |
| vision | none | `requestTimeout: 9m` | The last of 32 waiting pages waits about 143 s at the 13.40 images a minute of 32 streams, then runs up to 198 s, the latency p90 there, about 341 s ([dense-1120-high](findings/vision.md#dense-1120-high)); through the gateway at the full 64 in flight, the slowest page took 440 s ([gateway-priority-vision](findings/gateway.md#gateway-priority-vision)). 9 min covers it, and sits inside docinfer's 600 s header timeout, so the gateway ends a page held past it before the client does |
| audio | none | none | The last of 144 waiting windows waits about 71 s at 2.04 requests a second, then runs up to 35 s, the latency p90 at 48 streams, about 106 s ([audio-real-30s](findings/audio.md#audio-real-30s)); no timeout cuts it short |
| agent | none | none | A turn at 12 sessions runs about 67 s, and 12 waiting add about one such round ahead of it ([agent-sessions](findings/agent.md#agent-sessions)); 8 prompts of 65,536 tokens at once took 214 s ([agent-capacity](findings/agent.md#agent-capacity)), so a queue of long sessions has no bound a timeout could be sized to, and none cuts it short |
| embedding, `embedding-tokenize` | none | none | A request takes milliseconds |

Only vision's is set, the one route whose clients send long unstreamed requests at a known bound;
with no timeout, no other route cuts a queued request short.

## Overflow

Each of agent, vision, and audio has a second priority group, its own Azure AI Foundry deployment.
A request goes to the first group with a provider not evicted, so Azure answers only while the row
is out, and the alias returns to its row once the eviction ends ([priority.md][f-priority], "A row
down (behaviors 7, 8)").

| Alias | Deployment | Capacity | Processed | Formats |
| --- | --- | --- | --- | --- |
| agent | `gpt-oss-120b`, DataZoneStandard | 133 | within the data zone | Chat Completions; Messages translated to it |
| vision | `gpt-5-mini` 2025-08-07, GlobalStandard | 41 | globally | Chat Completions and Responses; Messages translated to Responses |
| audio | `gpt-audio-mini` 2025-12-15, GlobalStandard | 30 | globally | Chat Completions, only with audio in or out |
| embedding | none | | | |

- **Embedding has no cloud fallback.** A cloud model's vectors are in another space, so nothing
  the row indexed may be searched with them. The route has no Azure group and routes only to the
  row, and the account holds no embedding deployment
  ([Capacity and cloud spend](#capacity-and-cloud-spend)).
- **Never under IL6.** An IL6 deployment keeps only each alias's row group, and a down row answers
  with its failure ([comparison.md][comparison], "IL6").
- **The overflow switches.** [`overflow.toml`](../compose/agentgateway/overflow.toml) holds one
  switch per alias with an Azure group; `false` drops that alias's group at the next render.
- **The rewrite.** Each Azure provider's `ai` transformations drop what its deployment refuses, so
  a client sends the alias the same request whether the row or Azure answers: `agent-azure`
  removes vLLM's `ignore_eos`; `vision-azure` moves `max_tokens` to `max_completion_tokens`, keeping
  a client's own `max_completion_tokens`, and removes `top_p` and `top_k`; `audio-azure` keeps only
  `include_usage` in `stream_options`, dropping vLLM's `continuous_usage_stats`. An expression that
  fails removes its field, which `fail("remove")` does on purpose. They sit on the Azure providers,
  so a row's request is never rewritten
  ([gateway-overflow-rewrite](findings/gateway.md#gateway-overflow-rewrite)).
- **The marker.** Every reply from an Azure provider carries `x-gateway-overflow: azure`, set by
  its response header policy; a row's reply never does. In the overflow cells, every Azure reply
  carried it, 429s too, and the first request after each row's restart was the row's, without it
  ([gateway-overflow-agent](findings/gateway.md#gateway-overflow-agent) and the cells after it). Each Azure provider sets
  `providerOverride: azure`, so the access log's `gen_ai.provider.name` reads `azure` there and
  `custom` on a row's.

Each Azure provider is a custom, OpenAI-compatible provider at
`<account>.services.ai.azure.com:443` with the path prefix `/openai/v1`, the endpoint each
deployment was verified on. agentgateway's own `azure` provider reaches neither that host nor that
path: its `foundry` resource type builds a Foundry project's path, which the account has none of,
and `openAI` builds `<account>.openai.azure.com`. A host override drops the provider's default
TLS, so `backendTLS: {}` restores it, with SNI and Host from the host. The account's key goes in
the `api-key` header on these providers alone, so no row sees it.

What a workload gives up on overflow ([priority.md][f-priority], "Per alias: the cloud model and
its parity (behavior 12)"; [answer.md][f-answer], "The revalidation (behaviors 4, 5)"):

- **agent:** a tool-calling request that needs `tool_choice: required` or a named function breaks
  on Azure, and a Messages request at low effort gives no reasoning item; a fixed output under
  `ignore_eos` isn't held, since the rewrite drops it.
- **vision:** its content leaves the data zone; it refuses reasoning effort `none`, and the rewrite
  drops a client's `top_p` and `top_k`. At its default effort gpt-5-mini spent docinfer's whole
  2,048-token bound reasoning on a dense page and returned no text
  ([gateway-overflow-rewrite](findings/gateway.md#gateway-overflow-rewrite)).
- **audio:** its content leaves the data zone; it refuses a text-only chat, and the gateway's own
  typed parser refuses audio inside a Responses request on overflow (400, "failed to parse
  Responses request").
- **The gateway's translation:** a Responses reply cut off at its limit reports
  `incomplete_details.reason` `max_tokens`, where the API says `max_output_tokens`; an unknown
  model name succeeds, since the provider sets the deployment as the model.

Each alias's [go-ai profile](../go-ai/README.md) declares only the row's refusals, not Azure's.

### Capacity and cloud spend

Cloud spend is governed in Azure, not by the gateway: each deployment's capacity is the rate
ceiling on its overflow, and a Cost Management budget alerts on the month's spend. The commands
below ran from the laptop's `az` (2.90.0) on 2026-11-25, with `<account>` the Foundry account
(`AZURE_FOUNDRY_ACCOUNT` in fnox) and `<group>` its resource group.

**Capacity.** A unit of capacity is 1,000 tokens a minute, with a request limit that grows with
it; Azure answers 429 past either, which the Azure health policy turns into an eviction
([Row refusals, retry, and health](#row-refusals-retry-and-health)). Each deployment is sized to
its row's peak, capped by the region's quota. The first values, about 100 for agent, 50 for
vision, and 30 for audio, ran first; the final ones follow the overflow cells and the rows' peaks
below.

```sh
az cognitiveservices account deployment create --name <account> --resource-group <group> \
  --deployment-name gpt-oss-120b --model-format OpenAI-OSS --model-name gpt-oss-120b \
  --model-version 1 --sku-name DataZoneStandard --sku-capacity 100
az cognitiveservices account deployment create --name <account> --resource-group <group> \
  --deployment-name gpt-5-mini --model-format OpenAI --model-name gpt-5-mini \
  --model-version 2025-08-07 --sku-name GlobalStandard --sku-capacity 50
az cognitiveservices account deployment create --name <account> --resource-group <group> \
  --deployment-name gpt-audio-mini --model-format OpenAI --model-name gpt-audio-mini \
  --model-version 2025-12-15 --sku-name GlobalStandard --sku-capacity 30
```

Each answered `provisioningState` `Succeeded`, at capacity 100, 50, and 30 (from 50, 10, and 10),
with token limits of 100,000, 50,000, and 30,000 a minute, and request limits of 100 and 50 a
minute for agent and vision and 30 each 10 s for audio. `az cognitiveservices usage list
--location eastus2` read the quotas as 5,000 for `gpt-oss-120b` DataZoneStandard, 3,000 for
`gpt-5-mini` GlobalStandard, and 30 for `gpt-audio-mini` GlobalStandard.

**The budget.** `gateway-overflow`, $50 a month on the Foundry account's resource group, alerts
the subscription's owners and the architect's address at 80% and 100% of actual spend and at 100%
of forecast spend. `az consumption budget create-with-rg` takes no forecast threshold, so the
budget is put through the Consumption API with `az rest`:

```sh
az rest --method put \
  --url "https://management.azure.com/subscriptions/<subscription>/resourceGroups/<group>/providers/Microsoft.Consumption/budgets/gateway-overflow?api-version=2023-11-01" \
  --body @budget.json
```

with `budget.json`:

```json
{"properties": {"category": "Cost", "amount": 50, "timeGrain": "Monthly",
  "timePeriod": {"startDate": "2026-11-01T00:00:00Z", "endDate": "2036-10-31T00:00:00Z"},
  "notifications": {
    "actual-80": {"enabled": true, "operator": "GreaterThanOrEqualTo", "threshold": 80,
      "thresholdType": "Actual", "contactEmails": ["<email>"], "contactRoles": ["Owner"]},
    "actual-100": {"enabled": true, "operator": "GreaterThanOrEqualTo", "threshold": 100,
      "thresholdType": "Actual", "contactEmails": ["<email>"], "contactRoles": ["Owner"]},
    "forecast-100": {"enabled": true, "operator": "GreaterThanOrEqualTo", "threshold": 100,
      "thresholdType": "Forecasted", "contactEmails": ["<email>"], "contactRoles": ["Owner"]}}}}
```

It answered the budget `gateway-overflow`, amount 50, `Monthly`, with the three notifications.

**The final capacities.** Each deployment carries its row's throughput peak in Azure's tokens a
minute: the row's requests a minute at its peak, times a request's tokens on Azure as its overflow
cell read them, the prompt plus the reply's bound, which Azure counts against the minute as it
admits the request. Azure's request limit, one a minute per unit for agent and vision and 1 each
10 s for audio, sits above each row's request rate.

| Alias | Row's peak | Tokens a request on Azure | Tokens a minute | Capacity |
| --- | --- | --- | --- | --- |
| agent | 12.89 turns a minute at 12 sessions, 110.03 output tokens a second of 512-token turns ([agent-noise](findings/agent.md#agent-noise)) | 9,728 prompt on average over a session's four turns, 8,192 to 11,264, plus 512 ([gateway-overflow-agent](findings/gateway.md#gateway-overflow-agent)) | 132,035 | 133 |
| vision | 13.40 pages a minute at 32 streams ([dense-1120-high](findings/vision.md#dense-1120-high)) | about 956 prompt plus 2,048 ([gateway-overflow-vision](findings/gateway.md#gateway-overflow-vision)) | 40,254 | 41 |
| audio | 2.133 windows a second, 128 a minute, at 48 streams ([audio-real-30s](findings/audio.md#audio-real-30s)) | about 368 prompt plus 512 ([gateway-overflow-audio](findings/gateway.md#gateway-overflow-audio)) | 112,600 | 30, the region's quota |

The commands, on 2026-11-26 from the same `az`:

```sh
az cognitiveservices account deployment create --name <account> --resource-group <group> \
  --deployment-name gpt-oss-120b --model-format OpenAI-OSS --model-name gpt-oss-120b \
  --model-version 1 --sku-name DataZoneStandard --sku-capacity 133
az cognitiveservices account deployment create --name <account> --resource-group <group> \
  --deployment-name gpt-5-mini --model-format OpenAI --model-name gpt-5-mini \
  --model-version 2025-08-07 --sku-name GlobalStandard --sku-capacity 41
```

Each answered `provisioningState` `Succeeded`, at capacity 133 and 41, with token limits of
133,000 and 41,000 a minute and request limits of 133 and 41 a minute. Audio's deployment stays at
30, its quota, with no command. In the cells Azure enforced its limits loosely: vision's ran about
57 pages and 160,000 tokens a minute at capacity 50, and audio's 8 windows a second at capacity
30, with no 429; agent's, whose turns read 8,300 to 9,700 prompt tokens, got its first 429 3.8 s
in ([gateway-overflow-agent](findings/gateway.md#gateway-overflow-agent)).

**The embedding deployment, deleted.** The account's `text-embedding-3-small` deployment,
DataZoneStandard at capacity 10, was never routed: no route's Azure group named it, in the
template or in gb10-2's rendered config. It was deleted:

```sh
az cognitiveservices account deployment delete --name <account> --resource-group <group> \
  --deployment-name text-embedding-3-small
```

The command printed nothing and exited 0; `az cognitiveservices account deployment list` then
listed `gpt-oss-120b`, `gpt-5-mini`, and `gpt-audio-mini` alone.

## Secrets and Postgres

The rendered config holds no secret, and neither does any file the render writes.

- **The Foundry key** reaches agentgateway as a Compose secret, read by `file:` at
  `/run/secrets/azure-foundry-key`. `hosting gateway up` reads it from ai-hosting's `fnox.toml` and
  writes it to `.state/gateway/azure-foundry-key`. Compose outside swarm ignores a secret's uid and
  mode, so the file is 0644, readable by the image's uid 65532, inside the 0700 `.state/gateway/`.
- **The Foundry account name** reaches agentgateway through its environment,
  `${AZURE_FOUNDRY_ACCOUNT}` in each Azure provider's `hostOverride`, because `hostOverride` has
  no file form. `up` reads it from fnox and passes it to compose; with it unset, agentgateway
  refuses the config at start.
- **The consumer port's address**, `GATEWAY_ADDRESS`, defaults to `127.0.0.1` in
  `compose/agentgateway.yml`, so a compose run without the render's env file binds the loopback
  only, never every interface.
- **Postgres** uses a committed development credential, `agentgateway`, in its Dockerfile and the
  config's database URL. It publishes no port, so only the stack reaches it, and it holds request
  metadata, no content. The [development-secrets
  principle](https://github.com/standards-lab/architecture/blob/main/principles/development-secrets.md)
  lets such a published credential stay committed.

## Telemetry

The Collector is the stack's one telemetry ingress, on the compose network only; it publishes no
port. agentgateway sends it spans and the access log over OTLP gRPC at `otel-collector:4317`,
under `frontendPolicies.tracing` and `frontendPolicies.accessLog.otlp`; v1.7.0 deprecates the
`config.tracing` form, which carries the same settings. The Collector also scrapes agentgateway's
stats port, and its own metrics with go-web-service's `prometheus/self` receiver at `2e31ca4`. It
sends traces to Tempo, metrics to Mimir, and logs to Loki, and Grafana has a datasource for each.
The Collector is a compose service, so its host isn't a row host and the render looks up no tailnet
address for it.

- **Traces.** agentgateway starts a span for every request that arrives without a trace
  (`randomSampling: "true"`, every request), traces under a sampled `traceparent` that arrives,
  and sends the `traceparent` on to the row. No span holds prompt or completion content:
  agentgateway sends none by default, and the config adds no tracing field. A span may hold the
  caller's address and the endpoint, and an overflow's the Azure account's host. Since the
  Collector takes OTLP only on the compose network, no row's spans reach it; the spike's
  unauthenticated OTLP port on the tailnet is gone ([answer.md][f-answer], "Slice 2 · traces" and
  "For production").
- **The access log** adds three fields to every request's line: `retry_after`, the reply's
  `Retry-After`, the one place a client's 429 or 503 shows it; `overflow`, the reply's overflow
  marker; and `key_name`, the admitting key's consumer, absent on a 401. Each line goes to
  agentgateway's stdout and, as an OTLP log record with the same fields, to Loki, where Grafana's
  Loki datasource queries it. No line holds prompt or completion content: agentgateway logs none
  by default, and none of the three fields reads the body.
- **The request log.** Every request also writes one row of `request_logs` in Postgres, which the
  UI's Logs and Analytics pages read. `llm: metadata` stores the request's metadata, usage,
  timing, and cost, and no prompt or completion content. `agentgateway.user` is set to the key's
  consumer, so it fills the indexed column the UI filters and groups by. A row also holds the
  caller's address and the endpoint.

### The UI and Grafana

agentgateway's UI, read-only, is on gb10-2's loopback at port 3001, and Grafana at 3002, each
reached through an SSH tunnel to gb10-2. On route `ai` with no `llm` section the UI's sidebar
doesn't link Logs and Analytics, which load by URL at `/ui/llm/logs` and `/ui/llm/analytics`
([watch register](watch.md#agentgateway-ui-links-logs-and-analytics-only-with-an-llm-section)).

## Operating the stack on gb10-2

The `gateway` verbs run on gb10-2, from its clone, `~/ai-hosting`, and refuse a host whose class
isn't `gb10` before touching Docker.

| Command | What it does |
| --- | --- |
| `hosting gateway render` | Renders agentgateway's config from the template, the class profiles, the key list, and the switches, validating each input first; validates a copy with the pinned image; writes the compose override and env file; and only then renames the copy to `compose/agentgateway/config.yaml` |
| `hosting gateway validate` | Validates the rendered config with the pinned image on no network, changing nothing |
| `hosting gateway up` | Refuses until the render has written the config, the override, and the env file; reads the Foundry key and account from fnox; builds and starts the stack, waiting for it |
| `hosting gateway down` | Stops the stack and removes its containers and network, keeping its volumes: the request log and the telemetry stores |
| `hosting gateway reset` | Stops the stack and drops its volumes |
| `hosting gateway status` | Each container's state and status, and agentgateway flagged when it is stranded, with the command that recovers it |

**What render derives, and why.** A container on gb10-2 can't resolve a tailnet short name: the
host resolves through systemd-resolved's stub, which a container can't reach, and Docker's
resolver doesn't know the tailnet's names. So the render reads each row host from the rendered
config's routes, their `hostOverride`s and host backends, looks up its tailnet address
(`tailscale ip -4`; gb10-2's own from the host), and writes `.state/gateway/compose.override.yml`,
which gives agentgateway an `extra_hosts` entry per row host. It also writes
`.state/gateway/compose.env`, setting `GATEWAY_ADDRESS` to gb10-2's tailnet address, where the
consumer port is published. Deriving the hosts from the config
keeps the alias-to-host map in one home, and the addresses stay in gitignored files, so no tailnet
identifier is committed. Every `gateway` verb runs compose with both files when they are present.

**Reloads.** agentgateway watches its config and reloads routes, keys, buckets, and switches in
place, so a render is all a change to them needs; a reload builds the backends
again, which clears the rows' eviction counts. Fields under the config's `config` section (the
database, the admin address, storage) are read once, at start, so a change there takes
`hosting gateway down`, then `up`.

**The attestation workaround.** `up` runs compose with `BUILDX_NO_DEFAULT_ATTESTATIONS=1`. Compose
drops a service's `provenance: false` when it writes the bake definition for buildx (v5.2.0, on
gb10-2 in the spike), so buildx adds its default provenance attestation, whose manifest records the
build's times. On Docker's containerd image store the image ID is the digest of the index that
lists it, so every `up --build` gave an unchanged Dockerfile a new image ID, and compose recreated
its container on every `up`. The variable turns buildx's default attestation off, and no service
sets `provenance:` ([priority.md][f-priority], "Why Postgres was recreated", under "Slice 2 ·
overflow").

**Status.** `status` checks agentgateway alone for a stranded container, since it is the one
container bound to gb10-2's tailnet address; the Collector publishes no port.

## Open gaps

What the gateway leaves open at v1.7.0, each by decision.

### Admission on `/metrics`

Nothing in agentgateway reads a row's `/metrics`, and nothing queues at the gateway: vLLM queues
behind it, up to its queue limit, then refuses with the 503 the gateway acts on. What could fill
it, an authored `extProc` or `extAuthz` service reading each row's gauges, is ruled out by the
[minimal-footprint
principle](https://github.com/standards-lab/architecture/blob/main/principles/minimal-footprint.md):
a service of ai-hosting's own to build, run, and keep current beside the gateway.
The embedding row's running and waiting gauges also read 0 under load, so an admission rule on
them would see an idle row ([agentgateway.md][f-agentgateway], "The paper inventory";
[comparison.md][comparison], "Scoring").

### Bulk concurrency

Priority orders only vLLM's waiting queue: interactive vision beside a saturating bulk key jumped
the queue, then shared the batch with bulk's 20 streams and decoded at their pace, missing 10 s by
0.47 s with priority, against 1.87 s without ([priority.md][f-priority], "Benchmark D: priority on
vision (evidence 6)"). Live on the vision row's dense pages, an interactive page beside 60 bulk
streams had its first token in 20 s, then took 142 s to its last beside 31 bulk pages, with no
preemption ([gateway-priority-vision](findings/gateway.md#gateway-priority-vision)). Holding interactive latency under bulk load needs a cap on bulk's
concurrency. v1.7.0's only in-flight cap, `maxConcurrentRequests`, counts every request on a port,
whatever its key, so the bulk consumer bounds its own concurrency, and Cerebro's plan sets the
number ([watch register](watch.md#agentgateway-concurrency-cap-per-key)).

## Other limits of v1.7.0

### Eviction and overflow under load

- **Under saturation, eviction sends nearly the whole load to Azure, and its growth has no cap.**
  Every request in an eviction's window goes to Azure: in benchmark C-agent, 2,944 requests reached
  Azure in 60 s while the row answered 89. Each eviction lasts 5 s times the evictions so far, with
  no cap until a config reload builds the backends again, so after a long outage or overload a
  row can stay out for minutes after it is back; `hosting gateway down`, then `up`, returns it at
  once ([watch register](watch.md#agentgateway-eviction-growth-without-a-cap)).
- **With both groups evicted,** the load balancer still picks an evicted provider rather than
  none, so a request can reach a row that is still out. When Azure's 429s evicted its group while
  the agent row was stopped, the next 72 requests went to the row, each a 503 within 2 s
  ([gateway-overflow-agent](findings/gateway.md#gateway-overflow-agent)).
- **A body over 64 KiB isn't retried,** since the gateway buffers 64 KiB for a retry: vision images
  and audio clips get the row's 503 until two failures evict it. With a Strix Halo host powered
  down, each of those attempts waited out a connect timeout of about 11 s
  ([priority.md][f-priority], "A row down (behaviors 7, 8)").
- **The queue limit counts every key alike.** vLLM's `--max-num-queued-reqs` doesn't know a key,
  so a bulk flood also refuses interactive requests, which then overflow.
- **A streamed request's refusal doesn't reach the gateway.** vLLM can refuse a streamed request
  inside its stream: the reply's headers read 200, and its one event is the 503 error. The gateway
  sees a 200, so it neither retries, evicts, nor overflows; the client reads the error from the
  stream ([The queue limit counts running
  requests](findings/gateway.md#the-queue-limit-counts-running-requests)).

## Decisions

What the gateway task settled, beyond what the sections above give:

- **Route `ai` over the `llm` section,** since `llm` would need one port per alias
  ([Route `ai`, not the `llm` section](#route-ai-not-the-llm-section)).
- **`/models` carries `root`** from the class profile, so a client sees the served model through
  the gateway.
- **Issued keys live in each consumer's own `fnox.toml`,** and ai-hosting commits only their
  SHA-256 hashes. ai-hosting is public, so the consumer names in the key list are public. Rejected:
  holding the hashes in ai-hosting's `fnox.toml`.
- **Postgres uses a committed development credential:** it publishes no port and holds metadata,
  no content.
- **No off-LAN path.** The gateway serves tailnet peers on their direct path: no peer relay, no
  client timeouts sized for a relayed path.
- **Embedding has no cloud fallback** ([Overflow](#overflow)); its unrouted Azure deployment is
  deleted.
- **Cloud spend is governed in Azure, not by the gateway:** each deployment's capacity is the rate
  ceiling and a Cost Management budget alerts on spend, so no key has a token budget. Rejected: the
  per-key token budgets the gateway first charged, among them the bulk class's 1,000,000-token
  Block ([Capacity and cloud spend](#capacity-and-cloud-spend)).
- **Tracing samples every request,** as the spike did.

[f-agentgateway]: https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/findings/agentgateway.md
[f-routing]: https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/findings/routing.md
[f-priority]: https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/findings/priority.md
[f-answer]: https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/findings/answer.md
[comparison]: https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/comparison.md
