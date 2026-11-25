# Survey

`/hosting-upgrades survey <host>` reads what has moved for one host and gives each item a verdict,
as [the convention](../../../docs/upgrades.md#when-survey-runs) says: verify, take, hold, or skip.
It runs without root, reads every source fresh, and changes nothing on the host or in a committed
document. A change it would make is a proposal in its report.

## 1. Before the survey

1. Run [setup.md](setup.md), "Before a mode", with `survey`: the host, the rules, the inputs, and
   the probe.
2. Read the host's last report, the newest in `.state/upgrades/<host>/` from before this run, if
   any. The report names what moved since it. An item the last report has no section for, such
   as model security, reads the last 90 days.

## 2. Reconcile the probe with the descriptor

Pause on each of these before going on:

- the descriptor's alias is not among the probe's recorded aliases, or no labeled container
  serves it;
- a labeled row serves an alias the descriptor doesn't name;
- the host's clone is off the default branch or has changed tracked files (`== clone ==`), so its
  rows may not be the profile's.

A row whose running arguments differ from the command `hosting profile render` gives under
`== rows ==` is no pause: it is an item in step 3, since `hosting engine update` would replace it.

## 3. The items

Each item names what was read, cited, and takes one verdict, by
[the convention](../../../docs/upgrades.md#when-survey-runs). An engine move, a settings change,
and a candidate model are never take: each is
[what a measure takes](../../../docs/upgrades.md#what-triggers-a-measure). A take names its
rollback; one with none is hold.

1. **The host's debt**, from the probe: each pending package and firmware update, with the
   distribution's notes for it ([sources.md](sources.md#distribution-packages)), grouped by
   repository and security status where the notes give them; a pending reboot; each failed unit;
   a row that is unhealthy (`hosting engine status`), stranded, or differs from its rendered
   command; each row's startup warnings; images no container uses; models `hosting model list`
   shows no row serving. A package with no notes source, such as the DGX repository's `nvidia-*`
   or Omarchy's own repository, is take when it doesn't touch the row's path, such as a desktop
   app, and otherwise hold, "no notes source". A root step is printed for the architect, never
   run.

   A host clone with no changed files whose commit is behind `origin/main` is take: `git pull` in
   the host's clone, with the rollback `git -C ~/ai-hosting reset --keep <host commit>`. First
   run `git fetch origin main` here, then state whether the row's rendered command is unchanged
   by rendering the served row at `origin/main` in a temporary worktree:

   ```sh
   git worktree add --detach .state/upgrades/<host>/scratch/<timestamp>/main origin/main
   (cd .state/upgrades/<host>/scratch/<timestamp>/main &&
     HOSTING_CLASS=<class> bin/hosting profile render <alias>)
   git worktree remove .state/upgrades/<host>/scratch/<timestamp>/main
   ```

   It is unchanged when the serve arguments the render prints after the image equal the running
   container's `args` from the probe, past docker's leading `serve`, which the render omits.
2. **The engine.** Run `mise run currency`. It prints only what trails, so a release past the pin
   or a built image's base digest behind its tag each print a line, and no line means current. A
   nonzero exit is a finding, not a failure. The latest release is the newest that
   `gh release list --repo vllm-project/vllm` lists ([sources.md](sources.md#vllm)); when it is
   the pin, the engine is skip, "pin is latest". For each release past the pin, read its notes for
   the host's class (CUDA on gb10, ROCm on strix-halo), whether an image is published for the
   class, and any watch entry it moves. One release past the pin with an image and no reported
   regression for the class is verify; one blocked by a named watch entry or fix is hold.
3. **The rows' images.** Currency checks only the images the suite builds; a row running a stock
   image, `vllm/vllm-openai` or `vllm/vllm-openai-rocm`, is read here. Compare the digest the
   probe's `image created … digests` line gives with the registry tag's:

   ```sh
   curl -s https://hub.docker.com/v2/repositories/<repository>/tags/<tag> | jq -r .digest
   ```

   The same digest is skip, "image current". A different one is hold, "tag republished", with
   both digests: `hosting engine update` would pull the new image, an engine change no measure
   has read.
4. **The rows' settings.** For each row the host serves, read every release after the row's
   `measured_vllm` through the latest for each flag in its profile row, and for the defaults its
   other settings rest on: a flag renamed, deprecated, or re-defaulted, or a new option for the
   row's model. Run `bin/hosting profile stale`: a listed row is due re-measurement on the pin,
   which is verify ([the convention](../../../docs/upgrades.md#what-triggers-a-measure)). A
   finding a row's reason leaves owed, or a value a watch entry's parity frees, is verify too.
5. **The watch.** From `mise run watch`: each entry the descriptor names, or that bears on the
   row's engine, model, or image, with its upstream beside its recorded value. An entry that reads
   as recorded is skip. One that differs is a proposal to update the register, and its action,
   when parity is reached, is an item of its own.
6. **Model candidates** for the host's alias ([sources.md](sources.md#models)). Each candidate
   meets [the policy](../../../docs/policy.md)'s gates: origin at all three levels, with its
   clearance; artifact integrity; vLLM's support at the pin for its architecture through the
   role's interface ([sources.md](sources.md#roles)); and its fit in the row's share, the row's
   current `fraction` of the pool's total from the probe's `== gpu ==` memory lines: `MemTotal`
   on gb10, whose GPU shares the system's memory, and amdgpu's GTT total on strix-halo, never
   `MemAvailable`. Every skip is applied before a hold, so read the decisive gates first:
   - a candidate that fails integrity, vLLM support, or fit is skip, naming the gate;
   - a candidate whose card reports no gain for the role over the incumbent is skip, "gains the
     row nothing". A card that never compares the candidate with the incumbent settles nothing;
   - only then origin: a candidate of Chinese origin is skip, "origin, no clearance", unless
     CAISSI's or UK AISI's publications hold an evaluation of its release that clears it by the
     policy's terms ([sources.md](sources.md#model-security)). With one, it passes origin pending
     the architect's admission, a proposal citing the evaluation;
   - a card that needs a login is hold, "card unread", and a candidate whose origin can't be
     established is hold, "origin unclear", with what was checked;
   - a candidate that passes every gate is verify, a candidate screen, when its card reports a
     gain or no card settles the comparison.

   An agent candidate's verify notes that a measure stops it at `model-evaluation`'s tiers
   ([the convention](../../../docs/upgrades.md#measures-three-passes)).
7. **The descriptor.** A descriptor that restates a figure its class profile holds (a load
   target, a cap, a context, a fraction, a port, a model) is stale: list it under "Proposed
   changes", with the profile's value beside it. A watch item the descriptor lacks, or one that no
   longer bears, is a proposal too. So is run noise a finding has since measured. A descriptor
   with none of these is skip, "descriptor current".
8. **Model security**, once a run, whatever the host: CAISSI's and UK AISI's publications since
   the last report, and the state of the methods and standards for detecting a backdoor or covert
   behavior in a model ([sources.md](sources.md#model-security)). With nothing new, it is skip,
   "nothing new". A development that could make it possible to evaluate and clear a model is take
   or verify, as a proposal to [the policy](../../../docs/policy.md#clearance). A correction it
   finds to a document, such as an agency's new name, is take, as a proposal.

Order the items within each section verify, take, hold, skip, and, within a verdict, the item
that risks serving first.

## 4. Write the report

Write `.state/upgrades/<host>/<UTC date>T<HHMM>Z.md`, the run's start in UTC, such as
`2026-11-25T2012Z.md`, so a later run the same day never replaces it. Its shape:

```markdown
# <host>: survey, <UTC date>T<HHMM>Z

Run at <time UTC> from this clone at <commit> on <branch>, whose documents it judges against,
`origin/main` at <commit>; the host's clone at <commit> on <branch>. Last report: <path>, or none.

## Inputs
The descriptor, the policy, the profile row, and the pin, each with its commit; the probe's
sections and skips; currency's and watch's exit and lines that bear here.

## Moved since the last report
What differs from the last report's probe and items, or "first report".

## Host debt
## Engine
## Row images
## Row settings
## Watch
## Model candidates
## Descriptor
## Model security
One line an item: **<verdict>**: <item>: <what was read, with its source and read time>.

## Needs measurement
Each verify item, as the measure pass it calls for: an engine move to <release>, a settings
check of <alias> <flag>, or a candidate screen of <model> for <alias>.

## Proposed changes
Each change to a descriptor, the policy, the watch register, or a profile, one at a time, with
its reason, the model security item's proposals among them; the stale descriptor lines with the
profile's values.

## Sources
Each source cited, with its URL or command, its tier, and its read time.

## Probe
The probe's output as printed.
```
