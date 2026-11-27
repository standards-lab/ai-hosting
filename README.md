# ai-hosting

ai-hosting specifies how the organization's workstations host models: the vLLM rows each host
class serves, and the one gateway in front of them, Torii, on gb10-2.
[`docs/gateway.md`](docs/gateway.md) holds the gateway's requirements, reasoning, key procedure,
and operation. The working context starts at [`context/README.md`](context/README.md).

## Torii

Torii is the workspace's deployment of [agentgateway](https://agentgateway.dev), v1.7.0, and the
one path from a consumer to a model. A torii (鳥居) is the gate that marks where a shrine's sacred
ground begins. Torii marks the boundary every model call passes through. Its name comes from the
same Shinto set as the capstone's services: Bunrei processes, Mikoshi holds the knowledge people
work in, and Kannushi is the planned harness service. Each reaches the models through Torii, or
will, with a key of its own. The set is recorded in the coordinator's [naming
note](https://github.com/standards-lab/org/blob/main/context/naming.md).

agentgateway is the product, and the image, its config schema, and its behavior keep that name.
Torii is this repository's configuration and operation of it, on gb10-2:

- **One address per alias:** each alias is at `http://gb10-2:3000/<alias>/v1`, routed to the row
  that serves it.
- **Keys:** a key for each consumer, in the interactive or bulk class, with the class's priority
  and request buckets.
- **Overflow:** a fallback to Azure AI Foundry for agent, vision, and audio while their row is
  out.
- **A request log:** in Postgres, one row for each request it forwards.
- **Telemetry:** traces, metrics, and logs, collected for Grafana.

It runs as the compose service `torii`, container `gateway-torii-1`, in the stack whose compose
project is `gateway`. Its config lives in [`compose/torii/`](compose/torii/), and the `hosting
gateway` and `hosting key` commands run it.

## The `hosting` suite

`hosting <group> <verb>` installs, updates, and inspects a host's rows, its model store, and its
class's profile, runs the gateway's stack, and issues the gateway's keys; `hosting` with no
arguments lists every command. `mise run install` links it into
`~/.local/bin`, and `mise run uninstall` removes the link. Each host class has a directory under
`classes/` holding its profile, whose schema is [`classes/README.md`](classes/README.md), and its
runbook: [gb10](classes/gb10/runbook.md) and [strix-halo](classes/strix-halo/runbook.md). A runbook
gives the root steps a host needs first, the suite's install, and each row's commands.

`mise run check` runs the shell tests under `tests/` and validates every class profile, among its
other checks.

## The bench

The rows are measured from the laptop with GuideLLM and MTEB, in a mise environment of their own
that the check never installs: [`bench/README.md`](bench/README.md).

## Secrets

`fnox.toml` holds ai-hosting's development-time secrets, the Azure AI Foundry account's key and
name and ai-hosting's own bulk gateway key, encrypted to three recipients: `laptop`, `gb10-2`, and
the offline `backup`. No task is granted one yet. The [development-secrets
principle](https://github.com/standards-lab/architecture/blob/main/principles/development-secrets.md)
gives the convention and every step: supplying your own values, adding a device, rotating, and
restoring.
