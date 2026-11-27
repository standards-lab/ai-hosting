# goal · capstone.data-intelligence.torii

- **State:** brief ready
- **Task:** torii
- **Branch:** torii

## Tasks

1. [ ] torii

## Task brief · torii

**Problem**

The workspace calls its agentgateway deployment Torii, and the capstone's services and its
presentation use that name too. ai-hosting still names the deployment after the product in five
places: the compose service, the service's config directory, its compose file, its container, and
its docs and host pages. Its docs and tests also still use "Cerebro", the capstone's retired
service name. The capstone's acceptance run waits for this goal to sync, so gb10-2 has to be
running the deployment under its new name, with that proven, before the run can start.

**Behaviors**
1. The stack's gateway service is named `torii`. Its compose file and its config directory carry
   the same name, and the stack keeps one compose file and one directory per service.
2. Every command that reaches the service or its directory uses the new name and otherwise
   behaves exactly as before. That covers these commands:
   - rendering and validating the config
   - writing the per-host override
   - issuing, listing and revoking keys
   - reporting the stack's status and flagging a stranded gateway container
   - currency's `FROM` rule, which reads each service's Dockerfile
3. The Collector scrapes the gateway's stats port under the service's new name. The scrape job
   keeps its old name, so the metric series continue.
4. The names that refer to the product stay as they are:
   - the image and its pin
   - the config attribute that records each key's consumer, and the request-log column it fills
   - the Postgres credential and database
   - every watch-register entry
5. The compose project stays `gateway`. The gateway's container is `gateway-torii-1`, the other
   containers keep their names, and the five volumes, including the request log, carry over.
6. The docs, notes and host pages call our deployment Torii and the product agentgateway. Every
   link to the config template, the key list, the overflow switches and the Dockerfile resolves
   to the new directory.
7. "Cerebro" no longer appears anywhere:
   - The bulk-concurrency line in the gateway document and in the watch register says Bunrei's
     plan sets the number.
   - The tests' sample interactive consumer is `mikoshi`, and the lowercase refusal is tested
     with `Mikoshi`.
8. Consumers reach Torii at the same base URL, `http://gb10-2:3000/<alias>/v1`, with the same
   keys.
9. gb10-2 runs the renamed stack from its clone:
   - `gateway-torii-1` and the other six containers are up
   - no `gateway-agentgateway-1` remains
   - the clone holds no leftover old config directory
10. A stack-check smoke passes on gb10-2. It is recorded as a findings section that gives its
    commands, its time and its results, and it checks four things:
    - `hosting gateway status` reports every container running and nothing stranded
    - each alias's `/v1/models` answers 200 under ai-hosting's bulk key and lists that alias
    - those requests appear in the Postgres request log under ai-hosting's consumer
    - Mimir holds the Collector's scrape of the gateway's stats port under its new target

**Test seams**
- The suite's shell tests, with Docker stubbed, run under `mise run check`. They cover the config
  render, the stack's render-in-place, `up` and `status`, the key group, and currency's `FROM`
  rule. The check also resolves every relative Markdown link.
- The live stack on gb10-2 is tested only for the redeploy, through the `hosting gateway` verbs
  and the smoke's requests.

**Slices**
1. **Upgrade.** Move huggingface_hub to 2.5.0 and mteb to 2.27.25. Python 3.15 stays held, with
   its reason beside the pin. Done when `mise run currency` reports only the held item and the
   check passes.
2. **The rename.**
   - Test first: change the existing render, stack, key and currency tests to expect the `torii`
     service, its directory and `gateway-torii-1`, and to use `mikoshi`/`Mikoshi` in place of
     `cerebro`/`Cerebro`. Watch them fail.
   - Then rename the service, its compose file and its config directory. Point the library, the
     commands' headers, the Collector's scrape target and the ignore rule for the rendered config
     at the new name.
   - Behavior 4's product names stay.
   - Done when the check passes.
3. **Docs, notes and host pages.**
   - Name the deployment Torii in every page that names it: the gateway document, the watch
     register's Cerebro line, the policy, the host pages and their template, the file links in
     the findings, the README, and the context notes (the capability map, the gateway's sources
     note, the suite note and the secrets note).
   - Replace the two Cerebro lines with Bunrei. Dated commands recorded in the findings stay as
     they were run.
   - Done when the check passes and a read finds the product and the deployment each under its
     own name.
4. **Redeploy and smoke.** Runs on gb10-2 from the pushed task branch, so the session brief
   reports a proven deployment.
   - On gb10-2, run `hosting gateway down` from the clone's current commit, keeping the volumes.
   - Fetch the task branch, check it out, and remove the leftover untracked old config directory.
   - Run `hosting gateway render`, then `hosting gateway up`.
   - Run Behavior 10's smoke, record it as a new findings section beside the gateway's other
     cells, and link it from the gateway document's operating section.
   - Done when the smoke passes and its section is committed.
   - After SHIP merges, the clone switches back to main, which holds the same tree.

**Out of scope**
- Renaming the compose project, its network or its volumes. The project stays `gateway`.
- Renaming the `hosting gateway` command group, its library, its state directory, or
  `GATEWAY_ADDRESS`.
- Changing Torii's address or giving it a tailnet name. It stays at gb10-2:3000.
- Adding `--remove-orphans` to `up`. The redeploy removes the old container once.
- Rerunning go-ai's and docinfer's live client tiers.
- Changing the product names: the image and its pin, the consumer attribute and its request-log
  column, the Postgres credential and database, the Collector's scrape job name, and the
  watch-register entries.
- Editing docinfer, docs-corpus, standards-lab or the capstone repos.

**Door**

Two-way, except for the gb10-2 redeploy. The repository changes revert by commit. The redeploy
renames the running stack's gateway container, and only redeploying the previous commit with the
same down, checkout, render, up sequence undoes it. The volumes are kept, so the request log and
telemetry survive either way. No release.

## Progress

slices 4/4 committed · standards ✓ (5e9e3b1) · spec ✓ (1 gap closed) · editor ✓
- redirect, brief: give the README a fuller introduction to Torii as the agentgateway deployment (the name's meaning, the Shinto set). Done: a `## Torii` section.
- slice 4: gb10-2 took the branch as a git bundle (nothing pushed before the brief); `/models` is barely logged, so the smoke added one minimal request per alias to prove the request log.

## Decisions

- capstone: Torii names the workspace's agentgateway deployment; agentgateway keeps its name as the
  product, and ai-hosting keeps its repository name.
- torii: the `hosting gateway` command group, its library, its state directory and
  `GATEWAY_ADDRESS` keep "gateway", which names the role Torii plays.
- torii: `up` doesn't remove orphans. A service rename's redeploy removes the old container once,
  with `hosting gateway down` from the commit before the rename.

## Pending edits

- coordinator · context/ai-hosting.md, "The gateway": name the deployment Torii (agentgateway
  v1.7.0), with its container `gateway-torii-1` and its address unchanged at gb10-2:3000.
- coordinator · roadmap: a backlog goal for a Torii tailnet name (a Tailscale Service or a second
  node). It would move the clients' default base URL in docinfer, docs-corpus, the bench and the
  capstone services.
- coordinator · roadmap: a backlog goal, repos ai-hosting, for a seam test of the service name.
  `torii` must match in `compose/torii.yml`, the override's `services.torii` in `lib/gateway.sh`,
  and `status`'s `ps --quiet torii`, and no test ties them while Docker is stubbed. A test that
  runs `docker compose config` unstubbed on the rendered stack would.
