# <host>

The descriptor of `<host>`, which a survey and a measure read to reach the host and judge what
they find there ([the upgrade convention](../upgrades.md)). It names and links; every figure it
cites lives in the document it links. Every other fact about the host, its hardware, system,
containers, and models, comes from the probe a survey takes.

Copy this file to `docs/hosts/<host>.md` and fill each section.

## SSH short name

`<host>`, as `ssh <host>` reaches it from the client a survey runs on. Never a tailnet name or
address.

## Alias

`<alias>`, the row this host serves, from the `<class>` class's profile. The gateway's config is
the home of which host serves which alias
([config.template.yaml](../../compose/agentgateway/config.template.yaml)).

## Load target

The `<alias>` row's `[rows.load]` table in its class profile, a link to
`../../classes/<class>/profile.toml`. The table holds its `target` and the `source` that measures
it. A descriptor never restates the target, and a survey flags one that does as stale.

## Run noise

The widest relative spread, (highest − lowest) / lowest, between readings of one cell on one
vLLM release and one kernel, each with its readings and its source; or "not measured". The
verdict reads it ([the upgrade convention](../upgrades.md#the-verdict)).

- **Within-session**: <spread>, <cell, release, kernel, readings, source>.
- **Across-days**: <spread>, <cell, release, kernel, readings, source>.

## Watch items

Each [watch register](../watch.md) entry that bears on this host, linked by its heading, with
the reason it bears here; or "none".
