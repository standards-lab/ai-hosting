# Survey

`/hosting-upgrades survey <host>` reads what has moved for one host and gives each item a verdict,
as [the convention](../../../docs/upgrades.md#when-survey-runs) says: verify, take, hold, or skip.
It runs without root, reads every source fresh, and changes nothing on the host or in a committed
document. A change it would make is a proposal in its report.

## 1. Before the survey

1. Run [setup.md](setup.md), "Before a mode", with `survey`: the host, the rules, the inputs, and
   the probe.
2. Read the host's last report, the newest in `.state/upgrades/<host>/`, if any. The report names
   what moved since it.

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
   distribution's notes for it; a pending reboot; each failed unit; a row that is unhealthy,
   stranded, or differs from its rendered command; images no container uses; models
   `hosting model list` shows no row serving. A root step is printed for the architect, never
   run.
2. **The engine.** From `mise run currency`: the pin, the latest vLLM release, and each built
   image's base digest. A nonzero exit is a finding, not a failure. For each release past the
   pin, read its notes ([sources.md](sources.md#vllm)) for the host's class (CUDA on gb10, ROCm
   on strix-halo), whether an image is published for the class, and any watch entry it moves.
   One release past the pin with an image and no reported regression for the class is verify; one
   blocked by a named watch entry or fix is hold.
3. **The rows' settings.** For each row the host serves, read every release from the row's
   `measured_vllm` through the latest for each flag in its profile row, and for the defaults its
   other settings rest on: a flag renamed, deprecated, or re-defaulted, or a new option for the
   row's model. Run `bin/hosting profile stale`: a listed row is due re-measurement on the pin,
   which is verify ([the convention](../../../docs/upgrades.md#what-triggers-a-measure)). A
   finding a row's reason leaves owed, or a value a watch entry's parity frees, is verify too.
4. **The watch.** From `mise run watch`: each entry the descriptor names, or that bears on the
   row's engine, model, or image, with its upstream beside its recorded value. An entry that
   differs is a proposal to update the register, and its action, when parity is reached, is an
   item of its own.
5. **Model candidates** for the host's alias ([sources.md](sources.md#models)). Gate each by
   [the policy](../../../docs/policy.md), in its order, and stop at the first gate it fails:
   origin at all three levels, artifact integrity, then the quantization floor. Then read that
   vLLM supports its architecture at the pin, and that its size fits the row's share of the host,
   from the probe's `engine memory` and the row's `fraction`. A candidate that passes every gate
   and whose card reports a gain for the role over the incumbent is verify; one whose origin
   can't be established is hold, "origin unclear", with what was checked; one that fails a gate
   is skip, naming the gate. An agent candidate's verify notes that a measure stops it at
   `model-evaluation`'s tiers ([the convention](../../../docs/upgrades.md#measures-three-passes)).
6. **The descriptor.** A descriptor that restates a figure its class profile holds (a load
   target, a cap, a context, a fraction, a port, a model) is stale: list it under "Proposed
   changes", with the profile's value beside it. A watch item the descriptor lacks, or one that no
   longer bears, is a proposal too. So is run noise a finding has since measured.

Order the items within each section verify, take, hold, skip, and, within a verdict, the item
that risks serving first.

## 4. Write the report

Write `.state/upgrades/<host>/<YYYY-MM-DD>.md`, the date in UTC. If today's report exists, ask
whether to replace it. Its shape:

```markdown
# <host>: survey, <YYYY-MM-DD>

Run at <time UTC> from <clone commit>. Last report: <path>, or none.

## Inputs
The descriptor, the policy, the profile row, and the pin, each with its commit; the probe's
sections and skips; currency's and watch's exit and lines that bear here.

## Moved since the last report
What differs from the last report's probe and items, or "first report".

## Host debt
## Engine
## Row settings
## Watch
## Model candidates
One line an item: **<verdict>**: <item>: <what was read, with its source and read time>.

## Needs measurement
Each verify item, as the measure pass it calls for: an engine move to <release>, a settings
check of <alias> <flag>, or a candidate screen of <model> for <alias>.

## Proposed changes
Each change to a descriptor, the policy, the watch register, or a profile, one at a time, with
its reason; the stale descriptor lines with the profile's values.

## Sources
Each source cited, with its URL or command, its tier, and its read time.

## Probe
The probe's output as printed.
```
