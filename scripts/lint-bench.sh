#!/usr/bin/env bash
# lint-bench checks the bench's GuideLLM scenarios: every scenario parses as YAML with a spec, every
# embedding scenario's synthetic input, plus the embedding model's two special tokens, fits the
# embedding row's context, and every agent scenario's (a file named agent*.yaml) synthetic session,
# its prompt and output tokens over all its turns, fits the agent row's context.
#
#   scripts/lint-bench.sh [<profile> <scenario>...]
#
# With no arguments it reads bench/*.yaml against the embedding row of
# classes/strix-halo/profile.toml and the agent row of classes/gb10/profile.toml; given a profile,
# it reads both rows from it. It needs jq and mise's pinned mikefarah yq, reads no network, writes
# nothing, and exits non-zero on any failure. See bench/README.md.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd) || exit
# shellcheck source=lib/profile.sh
source "$root/lib/profile.sh"

special_tokens=2

if (($# == 1)); then
  echo "usage: scripts/lint-bench.sh [<profile> <scenario>...]" >&2
  exit 2
fi
if (($# == 0)); then
  embedding_profile=$root/classes/strix-halo/profile.toml
  agent_profile=$root/classes/gb10/profile.toml
  set -- "$root"/bench/*.yaml
else
  embedding_profile=$1 agent_profile=$1
  shift
fi
for file in "$embedding_profile" "$agent_profile" "$@"; do
  if [[ ! -f $file ]]; then
    echo "FAIL: $file is not a file" >&2
    exit 2
  fi
done

hosting_yq --version >/dev/null || exit

# Prints the numeric context of the profile's row with the alias given:
# row_context <profile> <alias>.
row_context() {
  hosting_yq -p toml -o json '.' "$1" |
    jq -er --arg alias "$2" '[.rows[]? | select(.alias == $alias) | .context | numbers] | first'
}

fail=0

# Checks the embedding scenario given, as its path and its JSON, against the embedding row's
# context.
lint_embedding() {
  local tokens
  if [[ ! -v embedding_context ]]; then
    embedding_context=$(row_context "$embedding_profile" embedding) || embedding_context=
    [[ -n $embedding_context ]] ||
      echo "FAIL: $embedding_profile has no embedding row with a numeric context" >&2
  fi
  if [[ -z $embedding_context ]]; then
    fail=1
    return
  fi
  if ! tokens=$(jq -er '[.spec.data[]? | select(.kind == "synthetic_text")
      | .prompt_tokens, .prompt_tokens_max | numbers] | max // empty' <<<"$2"); then
    echo "FAIL: $1 is an embedding scenario with no synthetic_text prompt_tokens" >&2
    fail=1
    return
  fi
  if ((tokens + special_tokens > embedding_context)); then
    echo "FAIL: $1: $tokens input tokens plus $special_tokens special tokens exceed the embedding row's context in $embedding_profile, $embedding_context" >&2
    fail=1
  fi
}

# Checks the agent scenario given, as its path and its JSON, against the agent row's context.
lint_agent() {
  local tokens
  if [[ ! -v agent_context ]]; then
    agent_context=$(row_context "$agent_profile" agent) || agent_context=
    [[ -n $agent_context ]] || echo "FAIL: $agent_profile has no agent row with a numeric context" >&2
  fi
  if [[ -z $agent_context ]]; then
    fail=1
    return
  fi
  if ! tokens=$(jq -er '[.spec.data[]? | select(.kind == "synthetic_text")
      | (.prompt_tokens_max // .prompt_tokens) as $p | (.turns // 1) as $t
      | select($p | type == "number")
      | (.first_prompt_tokens // $p) + ($t - 1) * $p
        + $t * (.output_tokens_max // .output_tokens // 0)] | max // empty' <<<"$2"); then
    echo "FAIL: $1 is an agent scenario with no synthetic_text prompt_tokens" >&2
    fail=1
    return
  fi
  if ((tokens > agent_context)); then
    echo "FAIL: $1: a session of $tokens tokens exceeds the agent row's context in $agent_profile, $agent_context" >&2
    fail=1
  fi
}

for scenario in "$@"; do
  if ! json=$(hosting_yq -p yaml -o json '.' "$scenario" 2>&1); then
    echo "FAIL: $scenario does not parse: $json" >&2
    fail=1
    continue
  fi
  if ! jq -e '.spec | type == "object"' <<<"$json" >/dev/null; then
    echo "FAIL: $scenario has no spec mapping" >&2
    fail=1
    continue
  fi
  if [[ ${scenario##*/} == agent*.yaml ]]; then
    lint_agent "$scenario" "$json"
    continue
  fi
  if jq -e '.spec.backend.request_format == "/v1/embeddings"' <<<"$json" >/dev/null; then
    lint_embedding "$scenario" "$json"
  fi
done
exit "$fail"
