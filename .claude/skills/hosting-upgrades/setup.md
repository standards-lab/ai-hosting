# Setup

`/hosting-upgrades setup` prints the permission rules the skill's modes need and stops. Survey and
measure run "Before a mode" first.

## The permission check

From the repository root, run:

```sh
.claude/skills/hosting-upgrades/scripts/setup.sh
```

It prints survey's rules, then measure's own, each marked `present` or `missing` against the
`permissions.allow` lists of `.claude/settings.json` and `.claude/settings.local.json`, then the
JSON of every missing rule to add to `.claude/settings.json`. Given `survey` or `measure`, it
prints that mode's rules alone; measure's include survey's. It writes no settings file; the
architect adds the rules.

| Rule | Mode | For |
|---|---|---|
| `Bash(.claude/skills/hosting-upgrades/scripts/probe.sh <host>)`, one per descriptor | both | the probe, by the descriptor's file name in `docs/hosts/` |
| `Bash(mise run currency)`, `Bash(mise run watch)` | both | the vLLM release, image tags and digests, and the watch register's upstream |
| `Bash(bin/hosting profile stale)` | both | the rows measured on a release older than the pin |
| `Bash(gh release list *)`, `Bash(gh release view *)` | both | vLLM's release notes |
| `Bash(gh search issues *)`, `Bash(gh search prs *)`, `Bash(gh issue view *)`, `Bash(gh pr view *)` | both | vLLM's tracker |
| `Bash(curl -s https://<site>/*)` for `huggingface.co`, `hub.docker.com`, `raw.githubusercontent.com`, `changelogs.ubuntu.com`, `ubuntu.com`, `archlinux.org`, `www.nist.gov`, and `www.aisi.gov.uk`; `Bash(jq *)` | both | JSON and raw files: the Hub's API, Docker Hub's tags, vLLM's files at a tag, the distributions' package notes, and CAISI's and UK AISI's publications ([sources.md](sources.md#reading-a-source)) |
| `WebFetch`, `WebSearch` | both | model cards, publishers' documents, and what the list doesn't hold |
| `Edit(.state/upgrades/**)` | both | the survey report |
| `Bash(tailscale ping -c 1 <short name>)`, one per descriptor | measure | the direct path a cell needs ([bench/README.md](../../../bench/README.md#running-a-cell)) |
| `Edit(docs/findings/**)` | measure | the findings cells |

The probe's rule names one host each, never a wildcard: a wildcard would match any argument,
which the probe refuses, but a rule should not depend on that. `setup.sh` takes each probe rule's
host from a descriptor's file name and each `tailscale ping` rule's from the descriptor's SSH short
name, so a new descriptor brings its rules at the next `setup`.

**Never granted.** Every command that changes or loads a host asks each time, in the architect's
view: `ssh` beyond the probe, `docker`, `hosting engine update`, `hosting model pull`,
`hosting profile set`, `git push`, and `bench/cell.sh`. So does `gh api`, which writes as readily
as it reads.

## Before a mode

1. **The host.** Take it from `$1`. With none, list the descriptors in `docs/hosts/` by name,
   leaving out `template.md`, and ask. Read `docs/hosts/<host>.md`; if it is absent, stop and
   name the descriptors that exist.
2. **The rules.** Run `setup.sh survey` or `setup.sh measure`. When a rule is missing, ask whether
   to go on with the prompts it brings or wait while the architect adds it; the default is to
   wait.
3. **The inputs.** Read [the convention](../../../docs/upgrades.md),
   [the policy](../../../docs/policy.md), the descriptor's alias row in its class profile, the
   pin in [`lib/vllm.env`](../../../lib/vllm.env), and each [watch](../../../docs/watch.md)
   entry the descriptor names.
4. **The probe.** Run, from the repository root:

   ```sh
   .claude/skills/hosting-upgrades/scripts/probe.sh <host>
   ```

   It refuses, with exit 2, any argument but a host with a descriptor, before it reaches the host.
   It then runs [probe-host.sh](scripts/probe-host.sh) on the host over ssh, read-only and
   without root, and prints its sections with every tailnet address and MagicDNS name redacted:

   - `== system ==`: the OS, the kernel, a pending reboot, `ip_nonlocal_bind`, and docker.
   - `== gpu ==`: on gb10, the NVIDIA driver and the CUDA version; on strix-halo, the amdgpu
     module's version and the ROCm version and packages readable without root.
   - `== clone ==`: the host's `~/ai-hosting` branch, commit, changed files, and its pin.
   - `== rows ==`: the recorded aliases; `hosting engine status`, `engine models`,
     `engine memory`, and `model list`; then each labeled row container's state, image and its
     digests, running arguments, the warnings and errors its log gives from its start to
     "Application startup complete", `hosting engine metrics`, and the command
     `hosting profile render` gives for it from the host's clone. The rows' health is
     `engine status`'s; their containers have no docker health check.
   - `== updates ==`, `== firmware-updates ==`, `== units ==`, `== docker-disk ==`: pending
     packages and firmware, failed units, and images no container uses, compared by image ID,
     since a compose container reports its image without a tag. Pending packages come from apt's
     cached lists, which the probe never refreshes, or from Arch's `checkupdates`, which syncs
     into a temporary database of its own and leaves pacman's untouched.
   - `== skipped ==`: every read that couldn't run.

   If ssh fails, stop and quote the error. If a section is missing or docker refuses, name it and
   ask whether to go on without it.
