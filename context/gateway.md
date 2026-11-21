# The gateway

agentgateway's compose stack on gb10-2, run from ai-hosting's clone, and the `gateway` and `key`
groups that run it; the `gateway` task builds them. Spike files are cited from
spike-model-gateway at `2f2e8c1`. The requirements follow `standards-lab/context/ai-hosting.md`,
with overflow on all four aliases; the embedding route's overflow is
[Foundry managed compute](foundry-overflow.md), and its secrets are in [secrets](secrets.md).

## Layout

The stack is layered as go-web-service's is: a root `compose.yml` names the project and
`include:`s one `compose/<service>.yml` per service, and each service builds from
`compose/<service>/Dockerfile`, whose `FROM` line is its one pin and which carries its config.

| Part in ai-hosting | Source | Task |
| --- | --- | --- |
| The root `compose.yml`: the project's name and its `include:` list | `gateway/compose.yml`; go-web-service's `compose.yml` at `2e31ca4` | gateway |
| agentgateway's service, `compose/agentgateway.yml`, and a one-line Dockerfile whose `FROM` is the v1.7.0 pin | `gateway/agentgateway.yml`; the pin from `gateway/agentgateway/deploy.env:6` | gateway |
| agentgateway's config: four routes, the serving-path allow-list, typed formats, retry, row health, the priority transformation, overflow, `storage: readOnly` | `gateway/agentgateway/config.yaml` | gateway |
| Postgres, holding the budgets and the request log | `gateway/postgres.yml`, `gateway/postgres/Dockerfile` | gateway |
| The Collector, Tempo, and Grafana | `gateway/otel-collector.yml`, `gateway/tempo.yml`, `gateway/grafana.yml`, and their directories | gateway |
| Loki and Mimir, the Collector's `prometheus` and `fluentforward` receivers, and their Grafana datasources | go-web-service's observability profile, `compose/observability.yml`, `compose/loki/`, `compose/mimir/` at `2e31ca4` | gateway |
| The `gateway` group's verbs | `scripts/agentgateway-deploy.sh`, `gateway/compose.sh` | gateway |
| Currency's `FROM` rule, over every `compose/*/Dockerfile`, with `crane` pinned in `mise.toml`; its tag pattern accepts a `v` prefix | `scripts/currency.sh:28-49`, `mise.toml:8-9` | gateway |
| The watch register, `docs/watch.md` and `scripts/watch.sh` | `docs/watch.md`, `scripts/watch.sh` | gateway; whether `upgrades`' skill runs its check is upgrades' |
| ai-hosting's gateway document: the requirements, and the reasoning the files' comments lose | `docs/gateway.md`, rewritten | gateway |
| `rows-down.yaml`, without its caps paragraph, and the overlay code: only if acceptance's overflow cells or the per-alias overflow switch use them | `gateway/agentgateway/probes/rows-down.yaml`, `scripts/agentgateway-deploy.sh:139-195` | acceptance; gateway |

agentgateway's config changes on the way in:

- the keys, budgets, and rate buckets are set for the named consumers, with each amount's reason
  in the gateway document; the per-key policies read a class field in the key's metadata in place
  of comparing the name with `"bulk"`, if v1.7.0 accepts one;
- each alias's Azure group gets a switch; the embedding route has no Azure group until
  acceptance's vector-parity cell passes, then names the `embedding` task's model, without the
  `dimensions` override;
- `..`, `%2e%2e`, and `%2f` are refused before routing, proven with the three requests;
- embedding's rate buckets keep their form and take the `embedding` task's figure, measured on
  the Framework beside the audio model;
- priority on Messages carries as is, and `acceptance` proves it;
- tracing stays at 100%.

Each file keeps one header and a provenance line naming spike-model-gateway at `2f2e8c1`; a
comment that explains points to the document or principle that governs it. The map from each
alias to its tailnet host has one home, the gateway's config; each alias's port derives from the
[host-class profiles](host-classes.md), which name no host, and one lookup of gb10-2's address
serves every use. The fixed `container_name` drops unless a `gateway` verb needs it, and the
`spike.config-section` label is renamed. gb10-2's Compose version is read again, and one form of
the attestation workaround stays, its reason in the gateway document.

These drop:

- six probes: `priority-flat`, `key-header`, `bulk-budget-low`, `bulk-rate-low`,
  `rate-limit-agent`, and `in-flight-1`;
- `docs/findings/*.md` and `docs/comparison.md`, which the gateway document links at `2f2e8c1`;
- the laptop's deploy, `scripts/agentgateway-deploy.sh`, `gateway/compose.sh`, and the spike's
  `gateway:*` and `agentgateway-deploy` mise tasks, replaced by the `hosting gateway` group;
- `deploy.env`'s image pin, which moves to the Dockerfile, and the deploy's removal of the
  pre-compose container;
- `postgres.env`, the rendered config's secrets, and the 0600/0700 rule.

## The `gateway` group

The group runs on gb10-2, against the stack in ai-hosting's clone, and covers what the spike's
laptop deploy and `gateway/compose.sh` did.

| Command | What it does |
| --- | --- |
| `gateway render` | Renders agentgateway's config with each key's hash and no secret, validates the copy, and renames it into place only when it passes |
| `gateway validate` | Validates the config with the pinned agentgateway image, changing nothing |
| `gateway up` | Refuses when no rendered config exists; otherwise builds and starts the stack |
| `gateway down` | Stops the stack, keeping its volumes |
| `gateway reset` | Stops the stack and drops its volumes |
| `gateway status` | The stack's state, and `hosts`' stranded-container check for agentgateway and the Collector, the two containers bound to gb10-2's tailnet address |

**Handover.** gb10-2's old `gateway` project comes down before the new stack binds the same
ports, and the new stack starts on a fresh Postgres volume; the old one held only the spike's
benchmark traffic. [Cleanup](cleanup.md) removes what the old project leaves.

## The `key` group

| Command | What it does |
| --- | --- |
| `key issue <consumer>` | Generates a consumer's key, stores it in the `secrets` store under the consumer's name, and gives the gateway only its hash |
| `key revoke <consumer>` | Deletes the stored key and its hash |
| `key list` | The consumers that hold an issued key |

## Open at the gateway plan

1. **The `/models` root.** Each alias's `/models` is the gateway's own answer, so go-ai's
   `Model.Native` carries no served model; pass the row's `root` through, or keep it hidden.
   Source: `docs/gateway.md:50-56`, `gateway/agentgateway/config.yaml:298-304`.
2. **Route `ai` or `llm`.** The inline route `ai` backends are labeled legacy; the `llm` form
   serves one alias per port. Stay on `ai` under the watch register, or move. Source:
   `docs/gateway.md:20-23`, `233-239`; `docs/watch.md:60-154`;
   `gateway/agentgateway/config.yaml:9-18`.
3. **Admission on `/metrics`.** agentgateway reads no row's `/metrics` and queues nothing; leave
   the gap, or author an `extAuthz` or `extProc` service. Source: `docs/gateway.md:187-197`.
4. **A cap on bulk concurrency.** Priority orders only vLLM's waiting queue, and a bulk flood
   pushed interactive vision past its floor; cap bulk, and where. Source:
   `docs/gateway.md:209-216`; `docs/findings/priority.md`, "Benchmark D".
5. **A sliding budget window.** v1.7.0's `rolling: 1h` is a fixed clock hour, so a key can spend
   twice its budget across the boundary. Source: `docs/gateway.md:204-208`;
   `gateway/agentgateway/config.yaml:132-134`; `docs/watch.md:217-237`.
6. **Authenticated OTLP.** The Collector takes spans from any tailnet peer, unauthenticated;
   authenticate it, bind it more narrowly, or leave it to production. Source:
   `docs/gateway.md:137-141`; `gateway/otel-collector.yml:7-8`, `19`.

The plan also settles:

- the stats port's loopback publish, once the Collector scrapes agentgateway on the compose
  network, and Tempo's retention;
- the key set, Cerebro, Athena, Pi, and Claude Code, with the budget and bucket amounts, and the
  class field in the key's metadata if v1.7.0 accepts one;
- whether agentgateway v1.7.0 reads each secret from a file or the environment, and what to do
  with any it can't;
- the new stack's Postgres password: its source and whether the store holds it; the spike's
  `postgres.env` isn't carried, and the volume is fresh;
- the tracing ratio, with open point 6;
- the compose project's name;
- the gateway document's path;
- the per-alias overflow switch's form;
- whether a compose profile gates the observability services.
