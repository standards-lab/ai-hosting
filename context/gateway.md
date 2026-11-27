# The gateway

This note records where each part of the gateway comes from. The gateway is Torii, the workspace's
agentgateway v1.7.0 deployment: a compose stack running on gb10-2 from ai-hosting's clone, with the
`gateway` group that runs it and the `key` group that issues its consumers' keys. [The gateway
document](../docs/gateway.md) holds the requirements, the reasoning behind each setting and amount,
the key procedure, how the stack is operated, and the open gaps. The [watch
register](../docs/watch.md) holds what agentgateway may change upstream, and [secrets](secrets.md)
holds the gateway's secrets. Spike files are cited from spike-model-gateway at `2f2e8c1`, and
go-web-service's at `2e31ca4`.

## What's built, and its sources

| Part in ai-hosting | Source |
| --- | --- |
| The root `compose.yml`, the project `gateway`, and its `include:` list | `gateway/compose.yml`; go-web-service's `compose.yml` |
| `compose/torii.yml`, and a one-line Dockerfile whose `FROM` is the v1.7.0 pin | `gateway/agentgateway.yml`; the pin from `gateway/agentgateway/deploy.env:6` |
| Torii's config template, `compose/torii/config.template.yaml`, the key list `keys.toml`, and the overflow switches `overflow.toml` | `gateway/agentgateway/config.yaml`; the key-hash form from `scripts/agentgateway-deploy.sh` |
| Postgres | `gateway/postgres.yml`, `gateway/postgres/Dockerfile` |
| The Collector, Tempo, and Grafana | `gateway/otel-collector.yml`, `gateway/tempo.yml`, `gateway/grafana.yml`, and their directories |
| Loki and Mimir, the Collector's `prometheus/self` receiver, and their Grafana datasources | go-web-service's `compose/observability.yml`, `compose/loki/`, `compose/mimir/`, `compose/otel-collector/` |
| The `gateway` group: `lib/gateway.sh`, `lib/gateway.jq`, `bin/hosting-gateway-*` | `scripts/agentgateway-deploy.sh`, `gateway/compose.sh` |
| The `key` group: `lib/key.sh`, `bin/hosting-key-*` | `scripts/agentgateway-deploy.sh`'s key generation |
| Currency's `FROM` rule over every `compose/*/Dockerfile`, with `crane` pinned | `scripts/currency.sh:28-49`, `mise.toml:8-9` |
| The watch register, `docs/watch.md`, and its check, `scripts/watch.sh` (`mise run watch`) | `docs/watch.md`, `scripts/watch.sh` |
| The gateway document, `docs/gateway.md` | `docs/gateway.md`, rewritten |
| Each alias's go-ai profile, `go-ai/<alias>.json`, and its evidence ([go-ai/README.md](../go-ai/README.md)) | |

- The Collector takes go-web-service's `prometheus/self` receiver, not its `tcp_log` or
  `fluentforward` receivers, beside its own `prometheus/agentgateway` scrape of Torii's stats port.
- Each file keeps one header and no source comment; the commit messages cite the spike.

What the spike had and ai-hosting dropped: the six probes and the `rows-down` overlay with its
overlay code (`gateway/agentgateway/probes/`, `scripts/agentgateway-deploy.sh:139-195`), which
`acceptance` didn't need: its overflow cells stop the row's container instead ([gateway
findings](../docs/findings/gateway.md#gateway-overflow-agent)); `docs/findings/*.md` and
`docs/comparison.md`, which the gateway document links at `2f2e8c1`; the laptop's deploy,
`gateway/compose.sh`, and the spike's `gateway:*` and `agentgateway-deploy` mise tasks, replaced by
the `gateway` group; `deploy.env`; `postgres.env` and the rendered config's secrets; the fixed
`container_name`; and the `spike.config-section` label.

Assumes gb10-2's Compose still drops a service's `provenance: false`, as v5.2.0 did in the spike.
