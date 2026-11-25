# framework

The descriptor of the first Framework desktop, a Strix Halo host, which a survey and a measure
read to reach the host and judge what they find there ([the upgrade convention](../upgrades.md)).
Every other fact about the host comes from the probe a survey takes.

## SSH short name

`framework`

## Alias

`audio`, from the strix-halo class's profile. The gateway's config is the home of which host
serves which alias ([config.template.yaml](../../compose/agentgateway/config.template.yaml)).

## Load target

The `audio` row's `[rows.load]` table in the
[strix-halo profile](../../classes/strix-halo/profile.toml).

## Run noise

Not measured on vLLM. A measure that needs it runs the incumbent's peak level again
([the upgrade convention](../upgrades.md#the-verdict)).

## Watch items

- [A gfx1151 MIOpen find database in vLLM's ROCm image](../watch.md#a-gfx1151-miopen-find-database-in-vllms-rocm-image):
  the audio row's image sets `MIOPEN_FIND_MODE=FAST` until the ROCm image ships a gfx1151 find
  database, and an engine move to a release that does reruns the audio probe without it.
