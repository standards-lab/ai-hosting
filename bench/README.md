# The bench

The bench measures a host's rows from a client on the hosts' LAN, the laptop at home: GuideLLM
drives load against a row, and MTEB scores an embedding row's retrieval. It is not part of the
suite, and no host installs it. The cells in `docs/findings/` run on it; a repeatable measuring
convention is planned for the `upgrades` task ([host-classes.md](../context/host-classes.md)).

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
| [`audio-8.yaml`](audio-8.yaml) | 8 concurrent streams for 240 s | The audio row alone at a cap of 8 |
| [`vision-capacity.yaml`](vision-capacity.yaml) | 4, 8 and 16 concurrent streams, 90 s a level, three levels in one run | The vision row's throughput and request latency at each image budget it is given |

Each embedding request is 510 synthetic tokens to `/v1/embeddings`: with the 2 special tokens an
XLM-R tokenizer adds, 512, the embedding row's context. `scripts/lint-bench.sh`, which the check
runs, fails when a scenario doesn't parse, or when an embedding scenario's input tokens plus those 2
exceed the context of the strix-halo profile's embedding row. Its tests, and those of
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

Each vision request is one synthetic 1440p JPEG beside 200 synthetic text tokens, sent to
`/v1/chat/completions`, each reply exactly 100 tokens; GuideLLM's vision extra generates the
images. The requests and the 90 s level match spike-model-layout's vision cells
(`bench/vllm-layout-vision-capacity.yaml`, which ran 8 and 16 streams), and the scenario adds a
level at 4. A level stops at 90 s, and the requests still in flight count as incomplete.

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

The vision row's three levels on gb10-2:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8001 \
  MISE_ENV=bench mise exec -- guidellm run -c bench/vision-capacity.yaml \
  --backend kind=openai_http,model=vision \
  --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it \
  --output kind=json,path=.state/bench/<cell>.json
```

The rate scenario takes its rate from the environment too,
`GUIDELLM__SPEC__PROFILE__RATE=<requests a second>`; with none set, GuideLLM refuses to start. The
earlier pair cell was two runs started together, `audio.yaml` against the audio row and
`embedding-rate.yaml` against the embedding row, each writing its own JSON.

## Reading the results

[`levels.jq`](levels.jq) turns a result JSON into one table a file, one row a level: its streams,
`rate <r>` on a constant-rate level, its rate to two places, or `synchronous` or `throughput` on a
sweep's first two levels; requests ok, errored, and incomplete; requests a second;
the TTFT median; the ITL median; the request latency's median, p90, and minimum; for vision, the
count of requests that finished in 10 s or less; prompt tok/s; for audio, the RTFx median and
minimum and the count of requests at RTFx 5 or more (each request's clip seconds over its request
time); and the level's floor verdict. Embedding's floor is a mean of 4,300 prompt tok/s, audio's an
RTFx median of 5, vision's a request latency median of at most 10 s; a level with no successful
request misses. A sweep's table starts with the knee GuideLLM concluded. Medians and percentiles
interpolate linearly between the two nearest ranks.

```sh
jq -r --arg purpose embed -f bench/levels.jq .state/bench/<cell>.json
jq -r --arg purpose audio -f bench/levels.jq .state/bench/<cell>.json
jq -r --arg purpose vision -f bench/levels.jq .state/bench/<cell>.json
```

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
