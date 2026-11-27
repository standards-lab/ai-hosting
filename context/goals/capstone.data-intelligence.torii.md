# goal · capstone.data-intelligence.torii

- **State:** idle
- **Task:** none
- **Branch:** none

## Tasks

1. [x] torii

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
