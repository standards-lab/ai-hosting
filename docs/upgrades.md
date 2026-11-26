# Upgrade evaluation

This convention says how ai-hosting evaluates an upgrade to a host's rows: a vLLM release, a row's
settings, or a replacement model. A survey reads what has moved and gives each item a verdict; a
measure takes the items only the host can settle to bench cells; and an adoption leaves findings
cells, a moved `measured_vllm`, and, once every host holds, a moved pin. The `hosting-upgrades`
skill runs both modes from the documents below.

- [The policy](policy.md): the gates every candidate passes, how it is judged on the host, and
  the tuning rule.
- [The host descriptors](hosts/), one a host: how to reach it, the alias it serves, its run
  noise, and its watch items.
- The class profiles, [gb10](../classes/gb10/profile.toml) and
  [strix-halo](../classes/strix-halo/profile.toml): each row's settings, load target, and the
  reasons that cite its findings. Nothing here restates them.
- [The watch register](watch.md): what this project waits for upstream, and what blocks a row.

## When survey runs

A survey runs on one host at a time, over SSH, read-only and without root, and changes nothing on
the host or in a committed document. It runs:

- **weekly, on each host**, whether or not anything triggered it, since engine releases, models,
  and upstream fixes move without an event on the host;
- **after a host update**, once the architect has updated the host's packages or rebooted it;
- **when `mise run currency` or `mise run watch` reports a change**: a vLLM release past the pin
  in [`lib/vllm.env`](../lib/vllm.env), a base image behind its tag, or a watch entry whose
  upstream or watched line differs;
- **when the host's descriptor, or its row in the class profile, changes**, since the survey
  judges every item against them;
- **before any change to the host**: a measure works from the host's last survey, so a session
  that changes a host runs the update, then the survey, then the measure.

A survey reads the host's probe (pending updates, failed units, the system's other debt, and the
running rows), `mise run currency` (the vLLM release, image tags, and digests), `mise run watch`
(each entry's upstream), each row's flags against vLLM's release notes since the row's
`measured_vllm`, model candidates for each alias the host serves, gated by the policy, and the
state of model security: NIST CAISSI's and UK AISI's publications, and the methods and standards
for detecting a backdoor or covert behavior in a model. It reads every source fresh: no research
cache is kept. It gives each item one verdict:

- **verify**: only the host can settle it, so a measure takes it;
- **take**: it needs no measurement, and goes with the host's next update;
- **hold**: it waits on something named, such as an upstream fix or a measurement;
- **skip**: it fails a gate, or gains the row nothing.

A survey proposes and applies nothing. A change it would make to a descriptor, the policy, the
watch register, or a profile is a proposal in its report, which the architect accepts or rejects
one at a time before the host's next survey. The model security item proposes a change to the
policy's origin section when a development could make it possible to evaluate and clear a model
([the policy](policy.md#clearance)). A descriptor that restates a figure the class profile holds,
such as a load target, a cap, or a context, is flagged as stale under the report's proposed
changes, with the profile's value beside it.

### Where survey reports go

Each survey writes one report, `.state/upgrades/<host>/<UTC date>T<HHMM>Z.md`, in the clone it
runs from, so no later run replaces it. `.state/` is untracked, so a report is never committed:
it is host state, read by the next survey and the next measure. What a report settles reaches the
repository only as a findings cell or an accepted proposal. The watch register holds what blocks a
row from an upgrade, each entry with its upstream state, so there is no separate blocker register.

## What triggers a measure

A measure takes the host's last survey to bench cells. It runs when that survey:

- gives verify to an engine move: a vLLM release the rows should run;
- gives verify to a row's settings: a flag the release notes change, a key a finding left owed, or
  a value a watch entry's parity frees;
- gives verify to a candidate model: one that passes the policy's gates, origin with its
  clearance, artifact integrity, vLLM's support, and its fit in the row's share, and whose card
  reports a gain for the role or which no card settles. A candidate whose card reports no gain is
  skip: it gains the row nothing.

`hosting profile stale` lists, read-only, each row whose `measured_vllm` is older than the pin in
`lib/vllm.env`, by class and alias, and exits 0 whether it lists any or none. A listed row's
settings rest on measurements of an older release than the one it runs, so the row is due
re-measurement on the pin. That is a settings check with no profile change: the cells its reasons
cite run again through the cell runner, and each is compared with the figures its findings hold.
The row's `measured_vllm` moves when they hold.

## Measure's three passes

A measure runs up to three passes on one host, each on one state. It prints each command that
changes the host before running it, and records the command as it ran.

1. **An engine move.** The candidate vLLM release runs off the pin, from a branch whose only change
   is `VLLM_RELEASE` in `lib/vllm.env`. The host's clone checks out that branch, then `hosting
   engine update` replaces the host's rows on the candidate's image. Rollback is the default branch
   and the same update.

   ```sh
   cd ~/ai-hosting && git fetch && git switch <branch> && hosting engine update
   cd ~/ai-hosting && git switch main && hosting engine update
   ```

   The pin moves on the default branch only through a pull request, once every host holds (see
   "The verdict").
2. **A settings check.** One row is measured without and then with a profile change. The change is
   `hosting profile set` on a branch, committed there, which the host's clone checks out before
   `hosting engine update <alias>`; the default branch and the same update return the row.
3. **A candidate screen.** A replacement model for one alias: its card, the policy's gates, probes
   at the row's context and of its purpose, a capacity cell, and the row's accuracy measure, judged
   as [the policy](policy.md#judged-on-the-host) says. The candidate runs from a branch whose
   profile names it, after `hosting model pull`. An agent
   candidate stops after the gates and the capacity cell, at "needs `model-evaluation`'s tiers":
   its BFCL and conform tiers are that goal's, and no agent candidate is adopted before they run.

The incumbent's cells run once a measure, and every pass in it compares with them. When the
findings ran a cell under settings the profile no longer holds, the cell runs at the current
settings instead, and its figures become the row's new baseline. The measure then gives that row
no drift verdict, and says so.

Every load goes through the bench cell runner, [`bench/cell.sh`](../bench/cell.sh): one scenario
against one row, each level alone, on inputs no other level sends, from a row restarted since its
last cell, which the runner refuses otherwise
([bench/README.md](../bench/README.md#running-a-cell)). A level that repeats another's inputs
reads the row's caches, not the row, and overstates its throughput. The accuracy measures are not
loads: embedding's retrieval runs through `bench/retrieval.sh`
([bench/README.md](../bench/README.md#scoring-retrieval)), and a probe is single requests with no
other load, as the purpose's findings give them.

Each pass records its cells in that purpose's findings, `docs/findings/<purpose>.md`, one section
a cell: its command as it ran, its time in UTC, its figures, and the tool versions it ran on, as
[the audio findings](findings/audio.md) do. A measure ends with the host serving its rows from the
default branch.

## The verdict

An engine move is adopted only when every row passes both tests:

- **Accuracy holds**, by the row's own measure:
  - audio: the probe clips up to 30 s still transcribe whole, each reaching its reference's last
    word ([audio-probe](findings/audio.md#audio-probe));
  - embedding: nDCG@10 within 0.02 of the published score on each of its BelebeleRetrieval
    subsets ([e5-retrieval](findings/embedding.md#e5-retrieval));
  - vision: the probe pages' prompt tokens unchanged at the row's image budget
    ([probe-1120](findings/vision.md#probe-1120)), read by `bench/vision-probe.sh` from the
    committed pages ([bench/README.md](../bench/README.md#the-vision-probe));
  - agent: the inter-token latency median at most 100 ms at its load target.
- **Throughput holds**: the row's throughput peak is within the host's run noise of the
  incumbent's, or ahead of it. The run noise is the widest within-session spread the host's
  descriptor gives. A host whose descriptor gives none has its incumbent's peak level run again,
  from a restarted row, in the same measure, and that spread stands as its run noise. gb10-2's
  descriptor gives a spread from llama.cpp's anchors, not from a row on vLLM, so a measure there
  replaces it by the same rule: the incumbent's peak run again.

Otherwise the move is held, and the measure writes a finding that says which row failed which test,
with the figures. The pin moves only when the move holds on all four hosts. The architect may
overrule a verdict; the record then gives the architect's reason beside the figures.

A settings check and a candidate screen use the same two tests for their one row, the change or
candidate against the row as it stands.

## The record an adoption leaves

1. **The findings cells**, in the purpose's findings, which the profile's reasons cite by section.
   A reason states the measurement behind the value the row runs, so an adoption that changes a
   value rewrites its reason to cite the new cell.
2. **`measured_vllm`**, which moves to the release a row's cells ran on, once that row's
   measurements behind its reasons have run there. `hosting profile stale` then drops the row.
3. **The pin**, `VLLM_RELEASE` in `lib/vllm.env`, moved by a pull request citing every row's
   cells, only when all four hosts hold.
4. **The watch register**: an entry a release clears moves to its next state, and is deleted
   once the project has acted on it ([watch.md](watch.md)).
5. **The descriptor's run noise**, when the measure repeated a level to set it.

## What stays with `model-evaluation`

The backlog goal `model-evaluation` keeps what no card and no capacity cell can settle:

- **The agent tiers**: BFCL and the conform tool-reliability check, run on our own harness. A
  measure screens an agent candidate through the gates and a capacity cell, then stops.
- **Our own workloads**: our agents and consumers under their real sessions, which no publisher
  measures.
- **Tuning at scale**: concurrency and context tuned per model, workload, and host.
