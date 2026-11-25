# Watch register

What this project watches upstream: any dependency's anticipated capability, deprecation, or other
change that would affect the infrastructure it maintains, one entry each. Version gaps are
`mise run currency`'s; this register holds what a version bump alone doesn't show, such as a form
the project relies on heading for removal, or a capability it is waiting for. It is written so that
other repositories can keep one the same way.

**The check.** `mise run watch` ([`scripts/watch.sh`](../scripts/watch.sh)) reads every entry's
upstream and watched lines, below, and prints each beside its recorded value, with `differs` where
the two part, exiting nonzero if any do. It reads the network through `gh` and writes nothing. It
runs separately from `mise run currency`. Its output is read by hand: each entry whose line differs
is updated in place, its recorded value, its state, and its other fields as the change warrants,
and every entry checked gets its last-checked line from the run. Git keeps the old text.

**An entry's fields:**

- **Kind:** deprecation, capability, or other.
- **Dependency:** the project, its repository, and where this project pins it.
- **Relies on** (a deprecation) or **wants** (a capability or other): the behavior at stake.
- **Evidence:** what shows the change is coming, or what the want is measured against, with its
  sources.
- **Upstream:** the issues and pull requests, one line each, `upstream <owner/repo>#<n> =
  <state>`, the state open, closed, or merged.
- **Watched:** the release fields that would show the change, read at the dependency's latest
  release tag, one line each in one of the forms below.
- **Trigger** (a deprecation) or **parity** (a capability): what, seen upstream, moves the entry
  on.
- **Fallback** (a deprecation) or **action** (a capability or other): what the project does then.
- **State**, by kind, in order:
  - Deprecation: **watching** → **deprecated in a release** → **removed**, or **withdrawn** if
    upstream backs out.
  - Capability: **watching** → **available in a release** → **adopted**, or **declined** if the
    project weighs it and stays.
  - Other: **watching** → **resolved**.
- **Last checked:** the check's `checked` time, and what it read.

**The machine-readable lines.** Each is a list item whose text starts with one backticked span,
which the check parses; prose may follow the span. A recorded value is what the line read when the
entry was last updated.

```text
upstream <owner/repo>#<n> = open|closed|merged
json <owner/repo> <path> <jq expression> = <value, as jq -c prints it>
text <owner/repo> <path> <fixed string> = present|absent
release-contains <owner/repo> <commit> = present|absent
```

`json` runs the jq expression on the file at the latest release tag; `text` looks for the string
in it; `release-contains` asks whether the tag's history holds the commit (`gh api
repos/<owner/repo>/compare/<commit>...<tag>`: ahead or identical is present). The latest release
is `gh release view`'s. A line that can't be read, a file moved or a path gone, prints as
`unreadable` and differs.

An entry is deleted once its state is final (removed, withdrawn, adopted, declined, or resolved)
and the project has acted on it; the document or decision that acted keeps the record.

The spike findings cited below are spike-model-gateway's at `2f2e8c1`:
[agentgateway.md](https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/findings/agentgateway.md),
[priority.md](https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/findings/priority.md),
and
[routing.md](https://github.com/JaimeStill/spike-model-gateway/blob/2f2e8c1/docs/findings/routing.md).

## agentgateway route `ai` backends deprecated

- **Kind:** deprecation.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, the image pinned in
  [`compose/agentgateway/Dockerfile`](../compose/agentgateway/Dockerfile) (v1.7.0).
- **Relies on:** the gateway's four routes, `/<alias>/v1` on the `consumer` port, each with an
  inline `ai` backend
  ([`compose/agentgateway/config.template.yaml`](../compose/agentgateway/config.template.yaml);
  [the gateway document](gateway.md#route-ai-not-the-llm-section)). The spike's task `routing`
  trialled the `llm` section and shipped it, then realigned on route `ai`, the form agentgateway's
  docs recommend for path-based routing (routing.md, "Realignment on route `ai`"). The entry
  watches whether route `ai` is deprecated after all, and whether it goes the way `binds` went:
  deprecated before the replacement could express everything it did.
- **Evidence**, at v1.7.0. For route `ai` staying a supported form:
  - The current docs recommend routing-based configuration for path-based LLM routing. The
    decision table in `content/docs/standalone/latest/documentation/llm/configuration-modes.md`
    (agentgateway/website, last edited 2026-11-10, `d35d036`) has the row "Do you need custom,
    path-based routing (e.g., `/openai`, `/anthropic`)? | Yes | Routing-based configuration", and
    the page's title is "Routing-based configuration for LLMs".
  - The UI's "legacy" label may mean "inline backend on a route", not deprecation. The MCP docs
    (`mcp/configuration-modes.md`, same edit) state that the top-level `mcp` section "is a
    simplified form of the same MCP backend that `routes[].backends[].mcp` configures. It is not a
    different feature", while the UI labels an inline route `mcp` backend "legacy MCP backend" as
    well as an inline `ai` one "legacy LLM backend" (`ui/src/traffic.ts`).
  - The schema doesn't mark route `ai`: the route backend's `ai` variant carries no description
    (`schema/config.json`, `$defs.LocalRouteBackend`), where `binds`' says "Deprecated".

  On the other side:
  - agentgateway's UI labels an inline `ai` backend "legacy LLM backend" (`ui/src/traffic.ts`).
  - The client docs moved from route `ai` to the `llm` section: website#1091 rewrote the Claude
    Code and Claude Desktop client pages from `routes[].backends[].ai` to `llm:`, closing
    agentgateway#3655, "Docs result in legacy backend configuration".
  - `binds` was deprecated in favour of `gateways` and `routes` before `gateways` could express
    `tunnelProtocol: connect` or `mode: internal` (#3204, open), so upstream has deprecated a form
    without parity before.
  - agentgateway has no deprecation policy: #2767, "Define a project deprecation policy", was
    closed as premature.
  - On Kubernetes the model form is already the recommended one: agentgateway#4307 opens "Since
    1.7, `AgentgatewayModel` is the recommended way to expose LLMs", `AgentgatewayModel` being the
    Kubernetes counterpart of the `llm` section's models.
- **Upstream:**
  - `upstream agentgateway/agentgateway#4307 = open` per-model rate limits on `AgentgatewayModel`,
    whose opening names it the recommended form since 1.7.
  - `upstream agentgateway/agentgateway#3204 = open` `binds` deprecated without parity.
  - `upstream agentgateway/agentgateway#2767 = closed` the deprecation policy, closed as premature.
  - `upstream agentgateway/agentgateway#3655 = closed` the docs' legacy backend configuration.
  - `upstream agentgateway/website#1091 = merged` the client docs moved to `llm`.
- **Watched:**
  - `json agentgateway/agentgateway schema/config.json [.["$defs"].LocalRouteBackend.oneOf[] | select(.properties.ai) | .description // "" | test("deprecated"; "i")] = [false]`
    whether the route backend's `ai` variant's description says "Deprecated", as `binds`' does:
    `[true]` is its deprecation, and `[]` its removal from the schema.
  - `text agentgateway/agentgateway ui/src/traffic.ts legacy LLM backend = present` the UI's
    label.
- **Trigger:** the `ai` variant's description says deprecated, or the UI's label changes, or a
  release note deprecates route `ai`: the state moves to deprecated in a release. Its removal from
  the schema moves it to removed.
- **Fallback:** the `llm` form the spike trialled (routing.md, "The trial"): one alias per port,
  each model authorized on its own port by `proxy.listener.name`. On a trigger, check what this
  project still needs from route `ai`, such as route retries or `ai.groups` (agentgateway.md, "The
  paper inventory"), and record what `llm` must gain for parity.
- **State:** watching.
- **Last checked:** 2026-11-24T23:16Z, `mise run watch`: every line as recorded, at v1.7.0, the
  latest release.

## agentgateway `llm` serving several base URLs on one port

- **Kind:** capability.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** the `llm` section serving each alias at its own base URL on one port, through several
  path prefixes or a model list per prefix, so that the gateway could serve its
  `http://gb10-2:3000/<alias>/v1` base URLs from `llm` rather than from route `ai`. This is the
  migration trigger: the gateway stays on route `ai`, the documented form for path-based routing,
  until `llm` can express the same base URLs.
- **Evidence:** the spike's task `routing` (routing.md, "The trial"): at v1.7.0, `llm.pathPrefix`
  is one string, the one prefix for every gateway the section is attached to, so the trial told
  the four aliases apart by port, each model authorized on its own listener.
- **Upstream:** Kubernetes has it: agentgateway#2973 lets an HTTPRoute with a path-prefix rule
  instantiate a further model router on the same listener, which `AgentgatewayModel`s bind to. No
  issue asks for it in the standalone `llm` section (survey of every issue and pull request,
  2026-11-16); the facts for one are in routing.md, "For an upstream feature request", for the
  architect to file.
  - `upstream agentgateway/agentgateway#2973 = merged` model routers scoped to an HTTPRoute,
    Kubernetes only.
- **Watched:**
  - `json agentgateway/agentgateway schema/config.json .["$defs"].LocalLLMConfig.properties.pathPrefix.type = "string"`
    one prefix; an array, or an object, would be the change.
- **Parity:** a release whose `llm` section lists only a prefix's own models on that prefix's
  `/models`, and refuses another prefix's, as each port did in the trial.
- **Action:** when standalone `llm` serves several prefixes (Kubernetes has it, #2973), weigh
  moving the gateway to it: the same `/<alias>/v1` base URLs, served by the `llm` section, against
  re-checking its body handling (the always-passthrough entry below).
- **State:** watching.
- **Last checked:** 2026-11-24T23:16Z, `mise run watch`: as recorded, at v1.7.0.

## agentgateway always-passthrough for `llm` models

- **Kind:** capability.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** a release with #4185, "(breaking) llm: fix passthrough to proper override known
  types", merged 2026-10-27 at `2a7c2ec`, after v1.7.0's tag. At v1.7.0 a model's `passthrough`
  decides only how unknown paths are handled: the `llm` section parses chat completions, messages,
  responses, and embeddings as typed requests, refuses a format its provider doesn't list with 400,
  and adds `stream_options.include_usage` to streams (routing.md, "Behavior 2: the pass-through
  matrix"). #4185 restores `passthrough` to its documented meaning, always pass through, and is
  marked breaking.
- **Evidence:** the pull request's description; v1.7.0's tag is behind its merge commit. The
  typed parsing has a cost on route `ai` too. On overflow, the gateway refuses audio in a
  Responses request itself, with 400 "failed to parse Responses request: data did not match any
  variant of untagged enum InputParam": translating the request for the Azure provider's Chat
  Completions parses an input part the typed form lacks. With the rows up, the row's provider
  lists `responses`, and the request passes through (priority.md, "The tiers on Azure (behavior
  10)").
- **Upstream:**
  - `upstream agentgateway/agentgateway#4185 = merged` always-passthrough restored.
- **Watched:**
  - `release-contains agentgateway/agentgateway 2a7c2ec473a221c643ff5c3adab77351bac65e71 = absent`
    the latest release carries the merge.
- **Parity:** the release carrying it, read in its notes for what `passthrough: detect` now does.
- **Action:** this applies to the typed route types the gateway's `ai.routes` name (Chat
  Completions, Messages, Responses, and embeddings), and to the `llm` form if the gateway moves to
  it. On the release carrying it, re-check the gateway's body handling on every alias: the formats
  each provider lists, whether streams still gain `include_usage`, and whether usage is still read
  for the access log and for the budgets; then decide `passthrough` per model.
- **State:** watching.
- **Last checked:** 2026-11-24T23:16Z, `mise run watch`: as recorded; v1.7.0, the latest
  release, doesn't carry the merge.

## agentgateway UI links Logs and Analytics only with an `llm` section

- **Kind:** capability.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** the UI's sidebar linking its Logs and Analytics pages whenever the request log is kept
  (`frontendPolicies.accessLog.database`), whatever form the routes take. On this config, route
  `ai` backends and no `llm` section, both pages work but the sidebar doesn't link them, so they
  load only by URL, at `/ui/llm/logs` and `/ui/llm/analytics`.
- **Evidence:** at v1.7.0 the sidebar shows its LLM pages only when `hasLlm`, which is
  `Boolean(config.data.llm)`, true only when the config has an `llm` section
  (`ui/src/components/Shell.tsx`, 102). The spike's priority walkthrough, step 5, found no link and
  loaded both pages by URL (priority.md, "Results" under "Slice 4 · walkthrough").
- **Upstream:** agentgateway#3860 reports the same symptom in Kubernetes mode (the pages reachable
  by URL, missing from the navigation), with a maintainer's comment that logging and analytics were
  designed for standalone. Nothing upstream names standalone route `ai`; the facts above are for
  the architect to add there, or to file, in their own words.
  - `upstream agentgateway/agentgateway#3860 = open` Logs and Analytics missing from the
    navigation, Kubernetes mode.
- **Watched:**
  - `text agentgateway/agentgateway ui/src/components/Shell.tsx Boolean(config.data.llm) = present`
    the sidebar's condition at the latest release; its absence is the change to read.
- **Parity:** a release whose sidebar links Logs and Analytics on a config with a request log and
  no `llm` section.
- **Action:** on that release, drop the by-URL note from the gateway document
  ([`gateway.md`](gateway.md#the-ui-and-grafana)).
- **State:** watching.
- **Last checked:** 2026-11-24T23:16Z, `mise run watch`: as recorded, at v1.7.0.

## agentgateway budgets over a sliding window

- **Kind:** capability.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** a token budget over a sliding window, so a key's spend is counted over the last hour
  whenever it is read. At v1.7.0 `rolling: 1h` is a fixed window, aligned to the Unix epoch, so
  each UTC clock hour: a count starts again at each hour, a key can spend twice its budget across
  an hour's boundary, and a Block's `Retry-After` is the time to the next hour
  ([`gateway.md`](gateway.md#the-fixed-budget-window)).
- **Evidence:** the spike's budget probes: bulk's Block answered `retry-after: 2609`, the seconds
  left in the clock hour, and the walkthrough's step 4 found bulk's count started again at the
  hour (priority.md, "bulk's budget Block (behavior 15)" and "Results"). The architect decided at
  the spike's review that a sliding window is a want, and this goal kept the fixed UTC hour,
  rejecting shorter fixed windows.
- **Upstream:** no upstream item. A search of agentgateway's issues and pull requests at the
  spike's review found none asking for a sliding budget window; #3970 (merged) added budgets that
  never refresh, a different change.
- **Parity:** a release whose budget takes a sliding window, read in its schema and notes.
- **Action:** weigh moving the budgets to it, and update [`gateway.md`](gateway.md).
- **State:** watching.
- **Last checked:** 2026-11-24T23:16Z, `mise run watch`: the entry listed, with no line to read.

## agentgateway eviction growth without a cap

- **Kind:** other.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** an upper bound on how long a repeatedly evicted endpoint stays out. At v1.7.0 each
  eviction lasts its `duration` times the number of evictions so far, 5 s, 10 s, 15 s on, with no
  cap, until a config reload builds the backends again and clears the count (`http/health.rs`,
  read in the source). The eviction fields at v1.7.0 are `duration`, `restoreHealth`,
  `consecutiveFailures`, and `healthThreshold` (`schema/config.md`); none bounds the growth.
- **Evidence:** the row and Azure health policies in
  [`compose/agentgateway/config.template.yaml`](../compose/agentgateway/config.template.yaml)
  (`&row-health`, `&azure-policies`); the spike's finding, priority.md, "Benchmark C-agent
  (behavior 9)": a row under saturation is evicted again and again, so after a long outage or a
  long overload it can stay out for minutes after it is back, sending its alias to Azure.
- **Upstream:** no upstream item. A search at the spike's review found only fixes to the count
  (#1912, merged: an ejection is counted only when a new window starts), and no issue asking for a
  bound.
- **Action:** if a release bounds it, set the bound on every row and Azure provider; until then, a
  config reload, or `hosting gateway down` then `up`, is how a row is returned at once, and
  [`gateway.md`](gateway.md#eviction-and-overflow-under-load) records the gap.
- **State:** watching.
- **Last checked:** 2026-11-24T23:16Z, `mise run watch`: the entry listed, with no line to read.

## agentgateway path normalization

- **Kind:** capability.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** a release with #4253, "feat(http): add normalization", merged 2026-11-02 at
  `d7e9f0d`, after v1.7.0's tag. It adds `frontendPolicies.http.normalize`, path normalization
  rules applied before route matching (`mergeSlash`, `dotSegment`, `decodeUnreserved`,
  `rejectEscapedSlash`, `unescapeSlash`), whose normalized path is used for routing, policies, and
  the upstream request.
- **Evidence:** at v1.7.0 agentgateway matches the raw path and doesn't normalize dot segments:
  the spike's `/agent/v1/../../metrics`, `/agent/v1/%2e%2e/%2e%2e/metrics`, and
  `/agent/v1/..%2f..%2fmetrics` matched the agent route and reached gb10-1 (agentgateway.md,
  "The paper inventory"). The gateway refuses them with its own authorization rule
  ([`gateway.md`](gateway.md#dot-segments)), which refuses any `%2e` or `%2f`, a superset.
- **Upstream:**
  - `upstream agentgateway/agentgateway#4253 = merged` path normalization, closing #1023.
- **Watched:**
  - `release-contains agentgateway/agentgateway d7e9f0d1f14d6e0b59bca4f0a46a96a856ad03e6 = absent`
    the latest release carries the merge.
  - `text agentgateway/agentgateway schema/config.json dotSegment = absent` the `normalize`
    field's `dotSegment` value in the latest release's schema.
- **Parity:** a release whose `normalize` takes `dotSegment` and `rejectEscapedSlash`, read in its
  schema and notes.
- **Action:** weigh setting `normalize` on the consumer gateway beside or in place of the
  authorization rule, and prove it with the spike's three requests; update
  [`gateway.md`](gateway.md#dot-segments).
- **State:** watching.
- **Last checked:** 2026-11-24T23:16Z, `mise run watch`: as recorded; v1.7.0, the latest
  release, doesn't carry the merge.

## agentgateway concurrency cap per key

- **Kind:** capability.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** a cap on the requests one key has in flight at once, so a bulk key can't fill a row's
  batch beside the interactive keys. At v1.7.0 the only in-flight cap is
  `frontendPolicies.http.maxConcurrentRequests`, one count per bind, across every key
  ([`gateway.md`](gateway.md#bulk-concurrency)).
- **Evidence:** the spike's benchmark D: priority took interactive vision ahead of bulk's waiting
  requests but then shared the batch with bulk's 20 streams, and its median missed 10 s by 0.47 s
  (priority.md, "Benchmark D: priority on vision (evidence 6)"). This goal leaves the bound to the
  bulk consumer; Cerebro's plan sets the number.
- **Upstream:** #3350 adds a `concurrencyLimit` policy, in-flight requests per CEL key, accepted on
  routes, gateways, and `llm.policies`.
  - `upstream agentgateway/agentgateway#3350 = open` in-flight requests per CEL key.
- **Watched:**
  - `text agentgateway/agentgateway schema/config.json concurrencyLimit = absent` the policy in the
    latest release's schema.
- **Parity:** a release whose schema has `concurrencyLimit` on a route or gateway, keyed by
  `apiKey.class` or `apiKey.name`.
- **Action:** weigh a bulk cap at the gateway on the agent and vision routes against the bulk
  consumer's own bound, and update [`gateway.md`](gateway.md#bulk-concurrency).
- **State:** watching.
- **Last checked:** 2026-11-24T23:16Z, `mise run watch`: as recorded; v1.7.0, the latest
  release, has no `concurrencyLimit`.

## A gfx1151 MIOpen find database in vLLM's ROCm image

- **Kind:** capability.
- **Dependency:** vLLM's ROCm image, `vllm-project/vllm`, built from `docker/Dockerfile.rocm_base`
  on the ROCm SDK its `ROCM_SDK_VERSION` names, whose MIOpen comes from `ROCm/rocm-libraries`; the
  audio image's base, pinned in
  [`images/vllm-openai-rocm-audio/Dockerfile`](../images/vllm-openai-rocm-audio/Dockerfile) at the
  release in [`lib/vllm.env`](../lib/vllm.env) (v0.34.0).
- **Wants:** a packaged gfx1151 find database in the image, so that MIOpen resolves the audio
  encoder's convolutions from it rather than by live solver timing, which fails on the Framework's
  gfx1151, and the audio image can drop `MIOPEN_FIND_MODE=FAST`
  ([engines](../context/engines.md#the-audio-image)).
- **Evidence:** rocm-libraries#10050, merged 2026-08-26 at `6ff142b`, adds MIOpen's gfx1151 system
  databases, `projects/miopen/src/kernels/gfx115128.HIP.fdb.txt.bz2` (find) and
  `gfx115128.db.txt.bz2` (perf), named for the 40-CU part the Framework carries. TheRock's
  `therock-10.0` tag doesn't hold the merge (its compare is diverged); `therock-10.1` and
  `therock-10.2` do. vLLM v0.34.0 builds its ROCm image on `ROCM_SDK_VERSION=10.0.0`, so the pinned
  image predates the databases. Upstream, the gfx1151 database still reports 658 find-database
  workspace mismatches once its DBSync test runs (rocm-libraries#16420), and #15618 would refresh
  the shipped gfx1151 databases with newer measurements. vllm#37472 reported vLLM hanging on
  gfx1151 for want of a solver database, and was closed after a maintainer served a nightly image
  there.
- **Upstream:**
  - `upstream ROCm/rocm-libraries#10050 = merged` the gfx1151 and gfx1200 system databases.
  - `upstream ROCm/rocm-libraries#16420 = open` gfx1151's find-database workspace mismatches.
  - `upstream ROCm/rocm-libraries#15618 = open` newer measurements layered over the shipped
    databases, gfx1151's among them.
  - `upstream vllm-project/vllm#37472 = closed` vLLM on gfx1151 without MIOpen's solver database.
- **Watched:**
  - `text vllm-project/vllm docker/Dockerfile.rocm_base ARG ROCM_SDK_VERSION=10.0.0 = present`
    the ROCm SDK vLLM's latest release builds its ROCm image on; its absence, a newer SDK, is the
    change to read.
  - `release-contains ROCm/rocm-libraries 6ff142b359893aff2ff040fcd9456eb2befb6bf1 = present`
    the latest TheRock tag carries the gfx1151 databases.
- **Parity:** a vLLM release whose ROCm image is built on a ROCm SDK carrying the merge, 10.1 or
  later, with `gfx115128.HIP.fdb.txt` readable under its MIOpen's `share/miopen/db`.
- **Action:** on the pin's move to that release, build the audio image without
  `MIOPEN_FIND_MODE=FAST` and rerun the audio row's probe on audio of 10 s or more; if it passes,
  drop the setting from the image and from [engines](../context/engines.md#the-audio-image).
- **State:** watching.
- **Last checked:** 2026-11-25T18:50Z, `mise run watch`: as recorded; vLLM v0.34.0, the latest
  release, builds on `ROCM_SDK_VERSION=10.0.0`, and `therock-10.2`, the latest TheRock tag,
  carries the databases.
