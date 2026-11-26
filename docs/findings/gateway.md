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
