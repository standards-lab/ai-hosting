---
name: hosting-upgrades
description: Evaluates upgrades to one ai-hosting host's vLLM rows, by the project's upgrade convention (docs/upgrades.md). Its survey mode probes the host over SSH, read-only and without root, reads the vLLM release and image currency, the watch register's upstream, each row's flags against vLLM's release notes since its measured_vllm, model candidates for each alias gated by docs/policy.md, and the state of model security (NIST CAISI's and UK AISI's publications), and writes a dated report into the untracked .state/upgrades/ giving each item verify, take, hold, or skip; it changes nothing. Its measure mode takes the host's last survey through up to three passes (an engine move, a settings check, a candidate screen) through the bench cell runner, printing every host-changing command first, or prints the whole pass and runs none of it. Its setup mode prints the permission rules each mode needs, marked present or missing. Use when asked to survey a host, find what a host has fallen behind on, evaluate a vLLM release, a row's settings, or a replacement model, plan or print a measure, or set up the skill's permissions.
argument-hint: setup | survey <host> | measure <host> [dry]
---

# hosting-upgrades

Runs [the upgrade convention](../../../docs/upgrades.md) on one host a run. The convention holds
the rules: when each mode runs, the four verdicts, the three passes, the verdict rule, and the
record an adoption leaves. This skill holds the procedure, and never restates a rule, a row's
settings, or a host's facts; it links them.

## Modes

The first argument, `$0`, names the mode; the second, `$1`, the host.

| Mode | Reads | Writes |
|---|---|---|
| `setup` | the descriptors and the settings | nothing |
| `survey <host>` | the probe, currency, watch, release notes, model cards | `.state/upgrades/<host>/<YYYY-MM-DD>.md` |
| `measure <host>` | the last survey and bench cells | findings cells in `docs/findings/<purpose>.md` |
| `measure <host> dry` | the last survey | nothing: it prints the pass |

- **`setup`**: read [setup.md](setup.md) and run its script. It prints and stops.
- **`survey <host>`**: read [setup.md](setup.md), "Before a mode", then [survey.md](survey.md).
- **`measure <host>`**: read [setup.md](setup.md), "Before a mode", then [measure.md](measure.md).
  With `dry`, it prints the full pass and runs none of its host-changing commands.

With no mode, ask which to run; the default is `survey`. With a mode and no host, list the
descriptors in `docs/hosts/` by name, leaving out `template.md`, and ask which host to use. A run
covers one host.

## Inputs

All relative to the repository root; a run writes none of them.

- [The convention](../../../docs/upgrades.md) and [the policy](../../../docs/policy.md).
- The host's descriptor, `docs/hosts/<host>.md` ([the template](../../../docs/hosts/template.md)):
  its SSH short name, its alias, a link to its row's load target, its run noise, and its watch
  items.
- The class profiles, [gb10](../../../classes/gb10/profile.toml) and
  [strix-halo](../../../classes/strix-halo/profile.toml): each row's model, settings, reasons,
  `measured_vllm`, and load target. The pin is `VLLM_RELEASE` in
  [`lib/vllm.env`](../../../lib/vllm.env).
- [The watch register](../../../docs/watch.md) and the findings in `docs/findings/`.
- [The bench](../../../bench/README.md) and its [cell runner](../../../bench/cell.sh).

When a step needs a value no input states, the run stops and asks the architect, and records the
answer as the architect's; it never invents one ([the policy](../../../docs/policy.md)).

## The files

| File | Holds |
|---|---|
| [setup.md](setup.md) | the permission rules, and what every mode does first |
| [survey.md](survey.md) | the survey's steps and its report's shape |
| [measure.md](measure.md) | the measure's steps, its passes, and its printed form |
| [sources.md](sources.md) | where each fact is read, and how a source is tiered |
| [scripts/probe.sh](scripts/probe.sh) | the read-only, no-root host probe, run by host name |
| [scripts/setup.sh](scripts/setup.sh) | the permission check `setup` runs |

## How a run behaves

- **No root, no sudo.** A fact only root can read is asked for: the run prints
  `ssh -t <host> sudo <command>`, the architect runs it and pastes the output, and the report cites
  it as the architect's.
- **Printed before run.** Every command that changes or loads a host, or pushes a branch, is
  printed before it runs and recorded as run; each asks permission, since `setup` grants none of
  them.
- **Fresh reads.** Every source is read in the run that cites it, with its URL and read time; no
  cache is kept.
- **Pauses.** A run stops and asks when the probe contradicts the descriptor, two sources
  disagree on a verdict, a policy value is missing, the host can't serve, or a step falls outside
  the convention. It states what it found, cites where, gives the options with its default, and
  waits. In a delegated or unattended run, where no one answers, the pause is recorded in
  the report as a hold with its default and a proposal, and the run goes on.
