# framework-2

The descriptor of the second Framework desktop, a Strix Halo host, which a survey and a measure
read to reach the host and judge what they find there ([the upgrade convention](../upgrades.md)).
Every other fact about the host comes from the probe a survey takes.

## SSH short name

`framework-2`

## Alias

`embedding`, from the strix-halo class's profile. The gateway's config is the home of which host
serves which alias ([config.template.yaml](../../compose/agentgateway/config.template.yaml)). The
embedding route has no cloud fallback, so this row is the alias's only backend.

## Load target

The `embedding` row's `[rows.load]` table in the
[strix-halo profile](../../classes/strix-halo/profile.toml).

## Run noise

Not measured on vLLM. A measure that needs it runs the incumbent's peak level again
([the upgrade convention](../upgrades.md#the-verdict)).

## Watch items

- [A gfx1151 MIOpen find database in vLLM's ROCm image](../watch.md#a-gfx1151-miopen-find-database-in-vllms-rocm-image):
  the host runs the same gfx1151 GPU and vLLM ROCm image as `framework`. The embedding row takes
  no MIOpen setting, so the entry bears here on an engine move's ROCm image, not on the row's
  settings.
