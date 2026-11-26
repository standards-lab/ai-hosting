# framework-2

This is the descriptor of the second Framework desktop, a Strix Halo host, which a survey and a
measure read to reach the host and judge what they find there
([the upgrade convention](../upgrades.md)). Every other fact about the host comes from the probe a
survey takes.

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

The embedding row's 4 streams of [`bench/embedding-sweep.yaml`](../../bench/embedding-sweep.yaml),
its throughput peak, on vLLM v0.34.0 and kernel 7.2.15-4-omarchy, on requests a second
([e5-noise](../findings/embedding.md#e5-noise)):

- **Within-session**: 2.66%, 82.833 and 85.033, each run from a restarted row.
- **Across-days**: 3.83%, with [e5-lan-sweep](../findings/embedding.md#e5-lan-sweep)'s and
  [e5-lan-sweep-16](../findings/embedding.md#e5-lan-sweep-16)'s 4-stream levels on 2026-11-24,
  82.167 and 81.900; the kernel those ran on was not recorded.

## Watch items

- [A gfx1151 MIOpen find database in vLLM's ROCm image](../watch.md#a-gfx1151-miopen-find-database-in-vllms-rocm-image):
  the host runs the same gfx1151 GPU and vLLM ROCm image as `framework`. The embedding row takes
  no MIOpen setting, so the entry bears here on an engine move's ROCm image, not on the row's
  settings.
