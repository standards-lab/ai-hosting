# The bench

The bench measures a host's rows from the laptop: GuideLLM drives load against a row, and MTEB
scores an embedding row's retrieval. It is not part of the suite, and no host installs it. The
`embedding` task's measurements run on it; the repeatable measuring convention is the `upgrades`
task's ([host-classes.md](../context/host-classes.md)).

## The environment

The tools live in mise's `bench` environment, [`mise.bench.toml`](../mise.bench.toml), beside
`mise.toml`: Python, GuideLLM 0.8.1 with its audio extra, and MTEB, each pinned exactly. A command
reads that file only with `MISE_ENV=bench` set, so `mise run check` never installs them and reads
no network. `mise run currency` reads its pins with every other pin. Install it once, from the
repository root:

```sh
MISE_ENV=bench mise install
```

Python is held on 3.14 for the reason beside its pin, so currency reports it until the hold lifts.

## The scenarios

Each scenario is one GuideLLM file. None names a host, a model, or a tokenizer: each run gives
them on the command line.

| Scenario | Load | For |
| --- | --- | --- |
| [`embedding-sweep.yaml`](embedding-sweep.yaml) | 1, 4, 16, 32, 64 and 128 concurrent streams, 30 s a level, six levels in one run | The embedding row's knee and plateau, and the cap |
| [`embedding-rate.yaml`](embedding-rate.yaml) | A constant rate, given per run, for 240 s | The embedding row at the rate the gateway admits, beside audio |
| [`audio.yaml`](audio.yaml) | 4 concurrent streams for 240 s | The audio row, alone or beside embedding |

Each embedding request is 510 synthetic tokens to `/v1/embeddings`: with the 2 special tokens an
XLM-R tokenizer adds, 512, the embedding row's context. `scripts/lint-bench.sh`, which the check
runs, fails when a scenario doesn't parse, or when an embedding scenario's input tokens plus those 2
exceed the context of the strix-halo profile's embedding row. Its tests are
[`tests/bench.test.sh`](../tests/bench.test.sh).

Each audio request is one LibriSpeech clip (`hf-internal-testing/librispeech_asr_dummy`, clean
validation split) sent as 16 kHz WAV to `/v1/chat/completions` with the transcription prompt of
the model's card, each reply at most 256 tokens. GuideLLM reads its two sources side by side, one
row of each a request, and stops when either runs out, never cycling one. So the split is read 12
times over, 876 rows, and the prompt is listed 876 times: room for 3.65 requests a second over
240 s. A run whose streams send faster ends when the rows do, before 240 s, and its result's
duration says so.

## Running a cell

From the repository root, each run gives the row's address (a host by its short name, as the
class runbook gives it, and the row's port from the profile), the model the row serves, and its
tokenizer, and writes GuideLLM's JSON into the untracked `.state/bench/`. The embedding sweep on
the Framework:

```sh
GUIDELLM__SPEC__BACKEND__TARGET=http://framework:<port> \
  MISE_ENV=bench mise exec -- guidellm run -c bench/embedding-sweep.yaml \
  --backend kind=openai_http,model=<model> --tokenizer kind=huggingface_auto,model=<model> \
  --output kind=json,path=.state/bench/<cell>.json
```

The rate scenario takes its rate from the environment too, `GUIDELLM__SPEC__PROFILE__RATE=<requests
a second>`; with none set, GuideLLM refuses to start. A pair cell is two runs started together, `audio.yaml` against the
audio row and `embedding-rate.yaml` against the embedding row, each writing its own JSON.

## Reading the results

[`levels.jq`](levels.jq) turns a result JSON into one table a file, one row a level: its streams,
or `rate <r>` on a constant-rate level; requests ok, errored, and incomplete; requests a second;
the request latency's median, p90, and minimum; prompt tok/s; for audio, the RTFx median and
minimum and the count of requests at RTFx 5 or more (each request's clip seconds over its request
time); and the level's floor verdict. Embedding's floor is a mean of 4,300 prompt tok/s, audio's an
RTFx median of 5; a level with no successful request misses. A sweep's table starts with the knee
GuideLLM concluded. Medians and percentiles interpolate linearly between the two nearest ranks.

```sh
jq -r --arg purpose embed -f bench/levels.jq .state/bench/<cell>.json
jq -r --arg purpose audio -f bench/levels.jq .state/bench/<cell>.json
```
