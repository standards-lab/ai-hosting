# ai-hosting

ai-hosting specifies how the organization's workstations host models: the vLLM rows each host
class serves and the one gateway in front of them. The gateway is planned; the working context,
with each planned capability's note, starts at [`context/README.md`](context/README.md).

## The `hosting` suite

`hosting <group> <verb>` installs, updates, and inspects a host's rows, its model store, and its
class's profile; `hosting` with no arguments lists every command. `mise run install` links it into
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
name, encrypted to three recipients: `laptop`, `gb10-2`, and the offline `backup`. No task is
granted one yet. The [development-secrets
principle](https://github.com/standards-lab/architecture/blob/main/principles/development-secrets.md)
gives the convention and every step: supplying your own values, adding a device, rotating, and
restoring.
