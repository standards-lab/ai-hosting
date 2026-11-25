# Measure

`/hosting-upgrades measure <host>` takes the host's last survey through up to three passes, each on
one state, as [the convention](../../../docs/upgrades.md#measures-three-passes) gives them: an
engine move, a settings check, and a candidate screen. Every load goes through
[the cell runner](../../../bench/cell.sh); every cell is recorded in its purpose's findings; and
every command that changes the host, a branch, or the remote is printed before it runs.

`/hosting-upgrades measure <host> dry` is the printed pass: steps 1 to 3 as below, then the whole
pass printed, step by step, with its values filled in, and none of it run. It runs only reads: the
probe, `tailscale ping`, and the documents. It restarts, updates, pulls, and loads nothing,
creates and pushes no branch, and writes no finding.

## 1. Before the measure

1. Run [setup.md](setup.md), "Before a mode", with `measure`.
2. **The last survey**: the newest `.state/upgrades/<host>/<YYYY-MM-DD>.md`. With none, stop:
   "No survey for `<host>`; run `/hosting-upgrades survey <host>` first." Name the report.
3. **What moved.** Compare the probe with the report's: the clone's commit and branch, each row's
   image and arguments, a pending update now applied. A change that would alter an item's verdict
   is a pause.
4. **The path.** Run `tailscale ping -c 1 <host>`. A path through a DERP relay is a pause: a cell
   needs a direct one ([bench/README.md](../../../bench/README.md#running-a-cell)).

## 2. The passes

From the report's "Needs measurement", take at most one of each pass, and ask the architect which
when the report gives more than one. They run in the convention's order, so the settings check
and the candidate screen run on the release that stays. With none, say so and stop.

For each pass, read from the class profile the row's alias, container, model, and the reasons that
cite its findings, and from each cited section the cell as it ran: its scenario, its levels, and
its accuracy measure. Those are the cells the pass runs again
([the convention](../../../docs/upgrades.md#what-triggers-a-measure)).

## 3. The run noise

Read the descriptor's "Run noise". When it gives none, the pass adds the incumbent's peak level run
again, from a restarted row, as [the verdict](../../../docs/upgrades.md#the-verdict) says.

## 4. Each step

Each command is printed, then run, then recorded with its UTC time and exit status:

```text
[<n>] <what it changes: the host, a local branch, or the remote>
    $ <command>
    rollback: <command>, or none
```

A dry pass prints the same lines and ends each with `not run (dry)`. Each pass has three parts.

**The incumbent.** On the default branch, for each cell the pass runs:

```sh
ssh <host> docker restart <container>
ssh <host> 'cd ~/ai-hosting && hosting engine status'
MISE_ENV=bench mise exec -- bench/cell.sh --host <host> --alias <alias> \
  --scenario <scenario> --cell <cell>-incumbent <levels>
<the purpose's accuracy measure, as its findings section gives it>
```

`engine status` is read until the row is healthy. Restart before each cell, and run the accuracy
measure after it: the runner refuses a row whose caches have served a request
([bench/README.md](../../../bench/README.md#running-a-cell)).
The accuracy measures are each purpose's own: embedding's retrieval through `bench/retrieval.sh`
([bench/README.md](../../../bench/README.md#scoring-retrieval)), and the audio, vision, and agent
probes as their findings give them.

**The change**, from a branch the host's clone checks out:

| Pass | The branch's one change | On the host |
|---|---|---|
| Engine move | `VLLM_RELEASE=<release>` in `lib/vllm.env` | `ssh <host> 'cd ~/ai-hosting && git fetch && git switch <branch> && hosting engine update'` |
| Settings check | `bin/hosting profile set <alias> <field>=<value>` | `ssh <host> 'cd ~/ai-hosting && git fetch && git switch <branch> && hosting engine update <alias>'` |
| Candidate screen | the row's `model`, and its `source` table, naming the candidate | `ssh <host> 'cd ~/ai-hosting && git fetch && git switch <branch> && hosting model pull <model> && hosting engine update <alias>'` |

The branch is cut, committed, and pushed from this clone, `measure/<host>-<what>`, each command
printed:

```sh
git switch -c measure/<host>-<what> main
git commit -m "<the change>" -- <file>
git push -u origin measure/<host>-<what>
```

Then the incumbent's cells again on the changed row, each from a restart, with the cell name
`<cell>-<release, field, or model>`.

A candidate screen first re-reads the policy's gates on the candidate, as
[survey.md](survey.md#3-the-items), item 5, reads them, and loads nothing that fails one. An agent
candidate stops after the gates and the capacity cell, at "needs `model-evaluation`'s tiers".

**The return** to the default branch, which ends every pass and the measure:

```sh
ssh <host> 'cd ~/ai-hosting && git switch main && hosting engine update'
.claude/skills/hosting-upgrades/scripts/probe.sh <host>
```

The probe reads back that each row runs the command its profile renders. A candidate's model stays
in the store until the architect prunes it with `hosting model prune --yes`.

## 5. The verdict

Judge each pass by [the verdict](../../../docs/upgrades.md#the-verdict): each row's accuracy, then
its throughput peak against the incumbent's within the run noise.

## 6. The record

Each cell goes into its purpose's findings, `docs/findings/<purpose>.md`, a section a cell, as
[the audio findings](../../../docs/findings/audio.md) do: each command as it ran, its time in UTC,
its figures, and the tool versions. A pass that fails the verdict writes which row failed which
test, with the figures. What an adoption changes beyond the findings, a reason, `measured_vllm`,
or the pin, follows [the record an adoption leaves](../../../docs/upgrades.md#the-record-an-adoption-leaves),
each a change the architect accepts on its own; the measure proposes them in its account and
makes none of them.

A dry pass ends with the account it would give: the passes, their cells, the incumbent's figures
from the findings each would be compared with, and the run noise it would use.
