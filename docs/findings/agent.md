# Agent findings

The measurements behind the gb10 profile's agent row, which serves `openai/gpt-oss-120b` alone on
gb10-1. Each section is one cell: its command, its time in UTC, its figures, and the tool versions
it ran on. The profile's reasons cite the cells by their section; the row's settings live in
[the profile](../../classes/gb10/profile.toml). The row's first measurements are
spike-model-layout's, on vLLM v0.33.0 (`docs/findings/vllm-layout.md`, C.7, D, H, and J); these
cells run them again on v0.34.0.

Each table's Floor column is `levels.jq`'s agent verdict, an inter-token latency median of at most
100 ms.

## Tools

Every cell ran on the tools below.

| Tool | Version |
| --- | --- |
| vLLM | v0.34.0, `vllm/vllm-openai:v0.34.0` at `sha256:20fdb089454afbb324efa4110a2c025ff7b27cc1a086e07aa580b18df8ad1ce1` |
| GuideLLM | 0.8.1, in the bench environment ([bench/README.md](../../bench/README.md)) |
| Tokenizer | `openai/gpt-oss-120b`'s, through transformers 5.24.1 in GuideLLM's environment |
| Checkpoint | `openai/gpt-oss-120b` at `b5c939de8f754692c1647ca79fbf85e8c1e70f8a` |

The row ran as the profile renders it: cap 12 (`--max-num-seqs 12`, `--max-num-queued-reqs 24`),
fraction 0.80, context 131,072, an FP8 KV cache of 32,993,476,982 bytes. The client is the laptop
on the LAN; `tailscale ping gb10-1`, right before each cell, answered direct, 0 or 1 ms. Each cell
started on a row restarted with `docker restart vllm-agent`, and the host's MemAvailable was
sampled every second through the start and every 10 s through the cell, over ssh.

## agent-start

The row's start at 2026-11-26T04:06:37Z, before [agent-sessions](#agent-sessions), healthy 65 s
later. Its weights took 66.14 GiB, and its KV cache held 1,733,249 tokens, 13.22 sessions of
131,072, as spike-model-layout's C.7 read 13.23 on v0.33.0. The host's MemAvailable fell no lower
than 14.91 GiB through the start, against the GB10's floor of 12.2 GiB (spike-model-layout
`docs/findings/vllm-layout.md`, "Reading the figures"). The starts before
[agent-capacity](#agent-capacity) and [agent-noise](#agent-noise) read the same KV cache, and
14.92 and 14.88 GiB.

## agent-sessions

The S-agent sessions, [`bench/agent-sessions.yaml`](../../bench/agent-sessions.yaml), at the target
of 4 sessions and the cap of 12, each level on its own through the cell runner, from
2026-11-26T04:07:57Z, right after [agent-start](#agent-start):

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 --alias agent \
  --scenario bench/agent-sessions.yaml --cell agent-sessions-gb10-1 4 12
```

`levels.jq` with `--arg purpose agent`. A request is one turn of a session; output tok/s counts
the turns that finished within the level's 110 s, and the total adds the tokens of the turns still
in flight at its end, from the result JSON's `output_tokens_per_second.total`.

| Sessions | Start, UTC | ok/err/inc | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Output tok/s | Total output tok/s | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 2026-11-26T04:08:05Z | 12/0/4 | 557 | 49.94 | 26.09 | 32.81 | 55.85 | 74.18 | 110 | meets |
| 12 | 2026-11-26T04:10:04Z | 13/0/11 | 14,017 | 94.30 | 66.19 | 68.98 | 60.50 | 109.20 | 110 | meets |

The row's `/metrics` after the cell: 25 turns finished, each at its 512 output tokens, with 0
preemptions. The host's lowest MemAvailable over the cell was 14.82 GiB.

- **Both levels meet the floor on v0.34.0**: an ITL median of 49.94 ms at 4 sessions and 94.30 ms
  at 12, against spike-model-layout's 49.13 and 99.07 on v0.33.0 (D).
- At 12 sessions the turns queue for prefill, a TTFT median of 14.0 s against 0.56 s at 4.

## agent-capacity

The long-session capacity cell, [`bench/agent-capacity.yaml`](../../bench/agent-capacity.yaml): 8
requests of 65,536 prompt tokens at once, each with 256 output tokens, from a restart at
2026-11-26T04:12:49Z:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 --alias agent \
  --scenario bench/agent-capacity.yaml --cell agent-capacity-gb10-1 8
```

| Streams | Start, UTC | ok/err/inc | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Prompt tok/s | Output tok/s | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 8 | 2026-11-26T04:14:05Z | 8/0/0 | 98,308 | 341.82 | 209.08 | 213.42 | 2,449 | 9.56 | 214 | misses |

The row finished all 8 at their 256 tokens with 0 preemptions; the host's lowest MemAvailable over
the cell was 14.80 GiB.

- **The KV cache holds 8 long sessions at once**: all 8 finished, 524,288 prompt tokens in 214 s,
  against 225 s in spike-model-layout's capacity cell (H). The floor doesn't apply here: the
  prefill of 8 prompts of 65,536 tokens at once sets the cell's latency.

## agent-noise

The run noise: [agent-sessions](#agent-sessions)' throughput peak, 12 sessions, run again from a
restart at 2026-11-26T04:19:03Z, as [the verdict](../upgrades.md#the-verdict) asks:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 --alias agent \
  --scenario bench/agent-sessions.yaml --cell agent-sessions-noise-gb10-1 12
```

| Sessions | Start, UTC | ok/err/inc | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Output tok/s | Total output tok/s | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 12 | 2026-11-26T04:20:17Z | 14/0/12 | 14,295 | 92.62 | 67.30 | 70.28 | 65.16 | 110.03 | 110 | meets |

The host's lowest MemAvailable over the cell was 14.77 GiB.

- **The total output throughput spreads 0.76%**, 109.20 and 110.03 tokens a second, and the ITL
  median 1.81%, 94.30 and 92.62 ms.
- The output tok/s of finished turns spreads 7.7%, 60.50 and 65.16: it counts whole turns of 512
  tokens, 13 and 14 of them, so one more turn finishing within the 110 s moves it by that much.
  The total is the throughput figure a verdict reads.

## layout

The agent row in the standing layout cell ([vision.md#layout](vision.md#layout)): the S-agent
sessions at the target of 4, held for 600 s in each of the cell's four rounds beside the other
three rows, each round from a restart:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 --alias agent \
  --scenario bench/agent-sessions.yaml --cell layout-v2-agent-gb10-1 --seconds 600 4
```

The rounds `layout-v4`, `layout-v8` and `layout-v32` ran the same. Against [agent-sessions](#agent-sessions)'
4 sessions alone, whose level ran 110 s:

| Round | Start, UTC | ok/err/inc | TTFT median ms | ITL median ms | Latency median s | Latency p90 s | Output tok/s | Total output tok/s | Duration s | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Alone | 2026-11-26T04:08:05Z | 12/0/4 | 557 | 49.94 | 26.09 | 32.81 | 55.85 | 74.18 | 110 | meets |
| Vision at 2 | 2026-11-26T05:02:47Z | 84/0/4 | 574 | 49.44 | 26.31 | 31.57 | 71.68 | 74.38 | 600 | meets |
| Vision at 4 | 2026-11-26T05:14:17Z | 84/0/4 | 581 | 49.26 | 26.41 | 31.81 | 71.68 | 74.51 | 600 | meets |
| Vision at 8 | 2026-11-26T05:25:43Z | 84/0/4 | 574 | 49.48 | 26.28 | 31.66 | 71.68 | 74.55 | 600 | meets |
| Vision at 32 | 2026-11-26T10:58:12Z | 84/0/4 | 580 | 49.75 | 26.45 | 31.62 | 71.68 | 74.33 | 600 | meets |

Each round's start read the same KV cache, 1,733,249 tokens, and the host's lowest MemAvailable was
14.86 GiB through the starts and 14.57 GiB through the rounds. The row finished 84 turns a round,
each at its 512 output tokens, with 0 preemptions.

- **The agent row beside the others matches it alone**: an ITL median of 49.26 to 49.75 ms against
  49.94, and a total output of 74.33 to 74.55 tokens a second against 74.18, each within
  [agent-noise](#agent-noise)'s spread, against spike-model-layout's 48.13 ms with every host at
  its target on v0.33.0 (J).
- Output tok/s of finished turns reads higher over 600 s than over 110 s, 71.68 against 55.85,
  since fewer of a longer level's turns are cut off at its end.
