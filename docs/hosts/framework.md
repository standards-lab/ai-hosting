# framework

This is the descriptor of the first Framework desktop, a Strix Halo host, which a survey and a
measure read to reach the host and judge what they find there
([the upgrade convention](../upgrades.md)). Every other fact about the host comes from the probe a
survey takes.

## SSH short name

`framework`

## Alias

`audio`, from the strix-halo class's profile. The gateway's config is the home of which host
serves which alias ([config.template.yaml](../../compose/torii/config.template.yaml)).

## Load target

The `audio` row's `[rows.load]` table in the
[strix-halo profile](../../classes/strix-halo/profile.toml).

## Run noise

The audio row's 48 streams of docinfer's windows, on vLLM v0.34.0 and kernel 7.2.15-4-omarchy,
each run from a restarted row, on the second-half rate the row's peak is read on
([audio-real-30s](../findings/audio.md#audio-real-30s),
[audio-noise](../findings/audio.md#audio-noise)):

- **Within-session**: 4.4%, 2.133 and 2.044 requests a second; the repeats at 24 and 32 streams
  read the same rate twice.
- **Across-days**: not measured.

## Watch items

- [A gfx1151 MIOpen find database in vLLM's ROCm image](../watch.md#a-gfx1151-miopen-find-database-in-vllms-rocm-image):
  the audio row's image sets `MIOPEN_FIND_MODE=FAST` until the ROCm image ships a gfx1151 find
  database, and an engine move to a release that does reruns the audio probe without it.
