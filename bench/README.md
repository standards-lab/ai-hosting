# The bench

The bench measures a host's rows from a client on the hosts' LAN, the laptop at home: GuideLLM
drives load against a row, and MTEB scores an embedding row's retrieval. It is not part of the
suite, and no host installs it. The cells in `docs/findings/` run on it, and so do the measures of
[the upgrade convention](../docs/upgrades.md).

## The environment

The tools live in mise's `bench` environment, [`mise.bench.toml`](../mise.bench.toml), beside
`mise.toml`: Python, GuideLLM 0.8.1 with its vision and audio extras, and MTEB, each pinned
exactly. A command reads that file only with `MISE_ENV=bench` set, so `mise run check` never
installs them and reads no network. `mise run currency` reads its pins with every other pin.
Install it once, from the repository root:

```sh
MISE_ENV=bench mise install
```

Python is held on 3.14. The file's `HOLDS` list, in its `[env]`, gives the reason, one
`<item> <pin>: <reason>` line for each hold. `mise run currency` reports a held pin as held, with
its reason, and fails only on a pin that trails unheld; moving the pin ends its hold.

## The scenarios

Each scenario is one GuideLLM file. None names a host, a model, or a tokenizer: each run gives
them on the command line.

| Scenario | Load | For |
| --- | --- | --- |
| [`embedding-sweep.yaml`](embedding-sweep.yaml) | 1, 4, 16, 32, 64 and 128 concurrent streams, 30 s a level, six levels in one run | The embedding row's knee and plateau, and the cap |
| [`embedding-rate.yaml`](embedding-rate.yaml) | A constant rate, given per run, for 240 s | The embedding row at one rate; [e5-pair](../docs/findings/embedding.md#e5-pair) ran it beside audio, when the two shared `framework` |
| [`embedding-rate-sweep.yaml`](embedding-rate-sweep.yaml) | GuideLLM's sweep: synchronous, throughput, then 14 constant rates between them, 90 s a level, sixteen levels in one run | The highest rate the embedding row keeps |
| [`audio.yaml`](audio.yaml) | 4 concurrent streams for 240 s | The audio row at 4 streams |
| [`audio-8.yaml`](audio-8.yaml) | 8 concurrent streams for 240 s | The audio row alone at 8 streams |
| [`audio-capacity.yaml`](audio-capacity.yaml) | 4, 8, 12, 16, 24 and 32 concurrent streams, 90 s a level, six levels in one run; a cell runs them one at a time | The audio row's throughput and RTFx on short clips |
| [`audio-capacity-30s.yaml`](audio-capacity-30s.yaml) | The same six levels | The audio row's throughput and RTFx on 30 s windows of speech |
| [`vision-capacity.yaml`](vision-capacity.yaml) | 4, 8 and 16 concurrent streams, 90 s a level, three levels in one run; a cell runs them one at a time | The vision row's throughput and request latency at each image budget it is given |
| [`agent-capacity.yaml`](agent-capacity.yaml) | 8 concurrent streams, one request each, at most 570 s | Whether the agent row holds 8 long sessions at once, and its inter-token latency, time to first token and output tokens a second while it does |

Each embedding request is 510 synthetic tokens to `/v1/embeddings`: with the 2 special tokens an
XLM-R tokenizer adds, 512, the embedding row's context. `scripts/lint-bench.sh`, which the check
runs, fails when a scenario doesn't parse, or when an embedding scenario's input tokens plus those 2
exceed the context of the strix-halo profile's embedding row, and when an agent scenario's session,
its prompt and output tokens over all its turns, exceeds the context of the gb10 profile's agent
row; a scenario is an agent scenario when its file is named `agent*.yaml`. Its tests, and those of
`levels.jq`'s level names, are [`tests/bench.test.sh`](../tests/bench.test.sh).

The rate sweep runs GuideLLM 0.8.1's built-in `sweep` profile: a synchronous level, then a
throughput level, then constant rates spaced evenly from the synchronous level's request rate to
the throughput level's, the last at the throughput rate. Its `sweep_size` of 16 counts every level,
so 14 are constant. It holds at most 16 requests in flight, the row's load target, at every
level: past the row's cap, more requests in flight lower its throughput (62 requests a second at
GuideLLM's default of 512 against 78 at 16, on the LAN), so an uncapped throughput level sits
below the row's ceiling and squeezes the constant rates into a band under it. Capped, the levels
run from the synchronous rate, about 56 a second on the LAN, to the throughput rate at 16
streams, about 78, so the constant rates fall about 1.6 apart
([e5-lan-sweep](../docs/findings/embedding.md#e5-lan-sweep)). Each level runs 90 s, not the
constant-rate cell's 240 s: a level still holds over 5,000 requests, and the run takes about 26
minutes. A rate past the row's limit queues at the client once 16 are in flight, so the level
reports the rate achieved, which falls short of the target.

Each audio request is one LibriSpeech clip (`hf-internal-testing/librispeech_asr_dummy`, clean
validation split) sent as 16 kHz WAV to `/v1/chat/completions` with the transcription prompt of
the model's card, each reply at most 256 tokens. GuideLLM reads its two sources side by side, one
row of each a request, and stops when either runs out, never cycling one. So the split is read 12
times over, 876 rows, and the prompt is listed 876 times: room for 3.65 requests a second over
240 s. A run whose streams send faster ends when the rows do, before 240 s, and its result's
duration says so. At 8 streams those rows ran out at 146 s (spike-model-layout
docs/findings/vllm-layout.md, F.5), so `audio-8.yaml` reads the same split 24 times over, 1,752
rows, with the prompt listed 1,752 times: room for 7.3 requests a second over 240 s. Its requests
are the same clips and prompt as `audio.yaml`'s, so its cells compare with the 4-stream ones.

The audio capacity scenarios read their requests from local files that
[`audio-clips.sh`](audio-clips.sh) writes, so a run needs no Hugging Face download. It takes the
same 73 LibriSpeech clips, 1.6 to 29.4 s long and 6.6 s on average, and writes each as a 16 kHz WAV
under the untracked `.state/bench/audio/clips/`. It joins consecutive clips, in the split's order
and across speakers and chapters alike, into windows of 28 to 30 s of real speech, written under
`windows-30/`. A window never overlaps the next, and a clip that would carry one past 30 s drops the
window's first clip instead, so the 8 minutes of the set make 11 windows, one of them the set's
single 29.4 s clip. The grouping is [`audio-windows.jq`](audio-windows.jq). Each WAV has its
reference transcript beside it, as a `.txt` of the same name.

It then writes the rows: `short.jsonl`, 5,400 rows cycling through the 73 clips, and
`windows-30.jsonl`, 1,800 rows cycling through the 11 windows, each row the card's transcription
prompt and the path of its own WAV, under `rows-short/` or `rows-windows-30/`. A row's WAV is its
clip or window at a gain of 1 + n/4096, where n counts the times the rows have cycled through the
clips, and the window rows' count carries on from the short rows' last, so no two rows of either
file send the same audio, and the writer stops on a repeat. The gains run from 1 to about 1.06, half
a decibel, which leaves the speech and its transcript unchanged; distinct audio keeps vLLM's prefix
and multimodal caches from reusing one request's work for another within a level.

With the prompt in the same row, the scenario reads one source, and each level reads the file again
from its first row, so a level repeats the earlier levels' first rows: in one run of the six levels,
74% of the short-clip requests' audio hit the row's multimodal cache, and 51% of their prompt tokens
its prefix cache ([audio-capacity-short](../docs/findings/audio.md#audio-capacity-short)). A cell
therefore runs each level on its own, on its own slice of the rows, against a row whose caches hold
none of them, as [Running a cell](#running-a-cell) gives.

Each level's slice leaves room over its 90 s for over 1.2 times the rate the row reached there at
cap 32: from 4.4 requests a second at 4 streams to 15.6 at 32 on short clips, against 3.1 and 9.1,
and from 1.7 to 5.6 on windows, against 0.7 and 1.8
([audio-capacity-short](../docs/findings/audio.md#audio-capacity-short),
[audio-capacity-30s](../docs/findings/audio.md#audio-capacity-30s)). A level whose streams send
faster ends when its rows do, and its duration says so. GuideLLM 0.8.1's scenario takes no parameter
for the window length, so each length is its own file.

Each reply is at most 256 tokens on short clips and 512 on windows: the 30 s probe clip's whole
transcript took 81 tokens ([audio-probe](../docs/findings/audio.md#audio-probe)), so either cap
leaves room for a full transcript. These are bench settings, sized so that a cut-off
transcript doesn't lower a level's cost; they are not advice to a client on `max_tokens`.

Each vision request is one synthetic 1440p JPEG beside 200 synthetic text tokens, sent to
`/v1/chat/completions`, each reply exactly 100 tokens; GuideLLM's vision extra generates the
images. The requests and the 90 s level match spike-model-layout's vision cells
(`bench/vllm-layout-vision-capacity.yaml`, which ran 8 and 16 streams), and the scenario adds a
level at 4. A level stops at 90 s, and the requests still in flight count as incomplete.

Each agent request is 65,536 synthetic prompt tokens to `/v1/chat/completions`, each reply exactly
256 tokens: GuideLLM sends `max_completion_tokens` with `ignore_eos` whenever `output_tokens` is
set, so every request generates its full 256. Each of the 8 streams sends one request, all 8 at
once, 524,288 prompt tokens in all, so the level reads whether the row's KV cache holds 8 long
sessions at once. The requests match spike-model-layout's agent capacity cell
(`bench/agent-vllm-capacity.yaml`, B-cap and F-cap in its `docs/findings/agent-vllm.md`, H), which
took 225 s on a GB10. A level stops at 570 s, and the requests still in flight then count as
incomplete. The row's context must hold the 65,792 tokens of a prompt and its reply; the agent
row's 131,072 does.

## Running a cell

From the repository root, each run gives the row's address (a host by its short name, as the
class runbook gives it, and the row's port from the profile), the name the row serves under (its
alias), and its model's tokenizer, and writes GuideLLM's JSON into the untracked `.state/bench/`.
A cell runs from a client on the LAN, its `tailscale ping` to the host answering direct, never
over a DERP relay: a relayed path limits the uploads and times out GuideLLM's fixed 5 s writes,
so it measures the path, not the row ([audio-8](../docs/findings/audio.md#audio-8)). Clients off
the LAN reach the rows through the gateway.

The embedding stream sweep on framework-2:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://framework-2:<port> \
  MISE_ENV=bench mise exec -- guidellm run -c bench/embedding-sweep.yaml \
  --backend kind=openai_http,model=embedding \
  --tokenizer kind=huggingface_auto,model=intfloat/multilingual-e5-large \
  --output kind=json,path=.state/bench/<cell>.json
```

The embedding rate sweep on framework-2, which takes no rate:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://framework-2:<port> \
  MISE_ENV=bench mise exec -- guidellm run -c bench/embedding-rate-sweep.yaml \
  --backend kind=openai_http,model=embedding \
  --tokenizer kind=huggingface_auto,model=intfloat/multilingual-e5-large \
  --output kind=json,path=.state/bench/<cell>.json
```

The audio row alone at 8 streams on `framework`:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://framework:<port> \
  MISE_ENV=bench mise exec -- guidellm run -c bench/audio-8.yaml \
  --backend kind=openai_http,model=audio \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it \
  --output kind=json,path=.state/bench/<cell>.json
```

The audio capacity scenarios on `framework`, after writing their files once, from the bench
environment (it downloads the LibriSpeech dummy set on its first run, then reads it from the
Hugging Face cache):

```sh
MISE_ENV=bench mise exec -- bench/audio-clips.sh scenarios
GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/audio-capacity.yaml \
  --backend kind=openai_http,model=audio \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it \
  --output kind=json,path=.state/bench/<cell>.json
GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/audio-capacity-30s.yaml \
  --backend kind=openai_http,model=audio \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it \
  --output kind=json,path=.state/bench/<cell>.json
```

A cell runs the levels one at a time instead, through [the cell runner](#the-cell-runner), so
that no level repeats another's audio: each level takes its own slice of the rows, the slices taken
in order and sized for the level's throughput, 400, 600, 800, 1,000, 1,200 and 1,400 of the short
rows and 150, 200, 250, 300, 400 and 500 of the window rows. The short clips, writing one JSON a
level:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host framework --alias audio \
  --scenario bench/audio-capacity.yaml --cell <cell> \
  4:400 8:600 12:800 16:1000 24:1200 32:1400
```

The windows run the same way with `audio-capacity-30s.yaml` and the window slices,
`4:150 8:200 12:250 16:300 24:400 32:500`, on a row restarted since the short clips ran: the
runner refuses a row whose cache counters don't read 0.

`audio-clips.sh scenarios --output <dir>` writes the files elsewhere, but the scenarios read
`.state/bench/audio/`. `audio-clips.sh probe <dir>` writes single clips for probing the row by
hand: `10s.wav`, `30s.wav`, `60s.wav` and `120s.wav`, each the first window in the set of
consecutive clips lasting between 14/15 of that length and the length, so 9.90, 29.40, 56.60 and
115.36 s, each with its transcript beside it. The argument handling's tests are
[`tests/audio-clips.test.sh`](../tests/audio-clips.test.sh), and the windows' are in
[`tests/bench.test.sh`](../tests/bench.test.sh), against the set's clip lengths.

The vision row's three levels on gb10-2:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8001 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/vision-capacity.yaml \
  --backend kind=openai_http,model=vision \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it \
  --output kind=json,path=.state/bench/<cell>.json
```

A vision cell runs the levels one at a time too. GuideLLM 0.8.1 draws each synthetic image from
the image source's `seed`, 42 unless given, and the request's row number, which starts again at 0
at every level, so each level of a one-run sweep, and every run, sends the same images in the same
order. Each synthetic text starts with the level's count and the row's and is drawn from the run's
`--seed`, so it differs between the levels of one run but repeats between runs of one seed
([synthetic-data](../docs/findings/vision.md#synthetic-data)). The cell runner therefore gives each
level both seeds its own value, its streams:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-2 --alias vision \
  --scenario bench/vision-capacity.yaml --cell <cell> 4 8
```

The agent row's capacity cell on gb10-1, its one level drawing its text from a seed of 8 the same
way:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host gb10-1 --alias agent \
  --scenario bench/agent-capacity.yaml --cell <cell> 8
```

The rate scenario takes its rate from the environment too,
`GUIDELLM__SPEC__PROFILE__RATE=<requests a second>`; with none set, GuideLLM refuses to start. The
earlier pair cell was two runs started together, `audio.yaml` against the audio row and
`embedding-rate.yaml` against the embedding row, each writing its own JSON.

### The cell runner

[`cell.sh`](cell.sh) runs one concurrent scenario against one row, one level at a time, each
level a GuideLLM run of its own. It runs from the repository root in the bench environment:

```sh
MISE_ENV=bench mise exec -- bench/cell.sh --host <host> --alias <alias> --scenario <file> \
  --cell <cell> [--output <dir>] <streams>[:<rows>]...
```

The host goes by its short name, and the alias names the row in the class profiles, which give
its port and its model's tokenizer, the base model's when the profile names one. Each level is a
count of streams, given in the order the levels run, with no count twice. For a scenario that reads
a JSON file, a level also gives the count of rows it takes, `<streams>:<rows>`: each level takes
the rows after the previous level's, written to `<dir>/<cell>-<streams>.jsonl`. Every level draws
its synthetic text and images from seeds set to its streams. Each level writes GuideLLM's JSON to
`<dir>/<cell>-<streams>.json`; `<dir>` defaults to the untracked `.state/bench/`.

A cell starts on a row restarted since its last cell, since a restart empties the row's caches.
Before the first level, the runner reads the row's `/metrics` and refuses to start unless
`vllm:mm_cache_queries_total` and `vllm:prefix_cache_queries_total`, each summed over its series,
read 0; a counter the row doesn't expose reads 0. The runner doesn't restart the row; on the host,
`hosting engine update <alias>` or `docker restart <container>` does.

Before its first request, the runner exits 2 on any of these: a missing or malformed argument,
an alias that names no row or more than one in the class profiles, a scenario that isn't a
concurrent profile or reads data other than synthetic text, synthetic images, and one JSON file,
levels taking more rows than the file holds, a level whose result JSON exists, or a run outside the
bench environment. It stops at the first level GuideLLM fails, exiting with GuideLLM's status. Its
tests are [`tests/cell.test.sh`](../tests/cell.test.sh).

## Reading the results

[`levels.jq`](levels.jq) turns a result JSON into one table a file, one row a level: its streams,
`rate <r>` on a constant-rate level, its rate to two places, or `synchronous` or `throughput` on a
sweep's first two levels; requests ok, errored, and incomplete; requests a second; the TTFT median;
the ITL median; the request latency's median, p90, and minimum; for vision, the count of requests
that finished in 10 s or less; prompt tok/s; output tok/s; for audio, the RTFx median and
minimum and the count of requests at RTFx 5 or more (each request's clip seconds over its request
time); and the level's floor verdict. Embedding's floor is a mean of 4,300 prompt tok/s, audio's
an RTFx median of 5, vision's a request latency median of at most 10 s, and the agent's an
inter-token latency median of at most 100 ms; a level with no successful request misses. The
verdict doesn't set a cap: the vision and audio rows' caps follow their throughput peaks, as their
profiles' `cap_reason` says. A sweep's table starts with the knee GuideLLM concluded. Medians and
percentiles interpolate linearly between the two nearest ranks.

```sh
jq -r --arg purpose embed -f bench/levels.jq .state/bench/<cell>.json
jq -r --arg purpose agent -f bench/levels.jq .state/bench/<cell>-8.json
jq -r --arg purpose audio -f bench/levels.jq .state/bench/<cell>.json
jq -r --arg purpose vision -f bench/levels.jq .state/bench/<cell>.json
```

## Preliminary cells

A findings cell labeled preliminary ran its row alone, not beside the layout's other rows. Its
figures stand for the row alone until `acceptance`'s standing layout cell (planned) re-measures
the row beside the others.

## Scoring retrieval

[`retrieval.sh`](retrieval.sh) runs MTEB's BelebeleRetrieval against an embedding row's
`/v1/embeddings`, through [`retrieval.py`](retrieval.py), with the Python of the environment's
MTEB. From the repository root, giving the row's address and both prefixes, each of which may be
empty:

```sh
MISE_ENV=bench mise exec -- bench/retrieval.sh --endpoint framework-2:<port> \
  --query-prefix 'query: ' --passage-prefix 'passage: ' [--output <dir>] [<subset>...]
```

The runner sends the row's served name, `embedding`, and adds the prefixes itself: a model such as
multilingual-e5-large declares none that vLLM applies, so a run without them scores the model as
no caller uses it. MTEB's query texts take the query prefix and its passages the passage prefix.
With no subset given, it runs the 37 for ~/docs' 13 languages, the list in `retrieval.sh`: each
language against itself, and each but English paired with English both ways. Chinese is
`zho_Hans`, Simplified; e5's published results cover it and `zho_Hant` alike. A subset is named
`<corpus>-<queries>` in Flores codes, as `eng_Latn-rus_Cyrl`.

It refuses a missing or malformed argument, a subset BelebeleRetrieval doesn't define, and a row
that doesn't serve `embedding`, before the first embedding request. It sends MTEB's batches of 32
and never asks the row to truncate: an input over the row's context is refused by vLLM, and the run
stops there with the row's answer, so a long input can't score as a silently shortened one. It
downloads the Belebele dataset from Hugging Face on its first run.

The result is MTEB's, one score set a subset, at
`<dir>/results/<served model>/embedding/BelebeleRetrieval.json`, the served model being the
row's `root` in `/v1/models`. The output defaults to the untracked `.state/bench/retrieval`. A run
overwrites the result in its directory, so give each cell its own. The run ends by printing each
subset's nDCG@10, BelebeleRetrieval's main score. The argument handling's tests are
[`tests/retrieval.test.sh`](../tests/retrieval.test.sh).
