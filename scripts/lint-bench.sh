#!/usr/bin/env bash
# lint-bench checks the bench's GuideLLM scenarios: every scenario parses as YAML with a spec, and
# every embedding scenario's synthetic input, plus the embedding model's two special tokens, fits
# the embedding row's context in the profile.
#
#   scripts/lint-bench.sh [<profile> <scenario>...]
#
# With no arguments it reads classes/strix-halo/profile.toml and bench/*.yaml. It needs jq and
# mise's pinned mikefarah yq, reads no network, writes nothing, and exits non-zero on any failure.
# See bench/README.md.
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
  set -- "$root/classes/strix-halo/profile.toml" "$root"/bench/*.yaml
fi
profile=$1
shift
for file in "$profile" "$@"; do
  if [[ ! -f $file ]]; then
    echo "FAIL: $file is not a file" >&2
    exit 2
  fi
done

hosting_yq --version >/dev/null || exit
if ! context=$(hosting_yq -p toml -o json '.' "$profile" |
  jq -er '[.rows[]? | select(.alias == "embedding") | .context | numbers] | first'); then
  echo "FAIL: $profile has no embedding row with a numeric context" >&2
  exit 1
fi

fail=0
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
  jq -e '.spec.backend.request_format == "/v1/embeddings"' <<<"$json" >/dev/null || continue
  if ! tokens=$(jq -er '[.spec.data[]? | select(.kind == "synthetic_text")
      | .prompt_tokens, .prompt_tokens_max | numbers] | max // empty' <<<"$json"); then
    echo "FAIL: $scenario is an embedding scenario with no synthetic_text prompt_tokens" >&2
    fail=1
    continue
  fi
  if jq -en --argjson t "$tokens" --argjson s "$special_tokens" --argjson c "$context" \
    '$t + $s > $c' >/dev/null; then
    echo "FAIL: $scenario: $tokens input tokens plus $special_tokens special tokens exceed the embedding row's context in $profile, $context" >&2
    fail=1
  fi
done
exit "$fail"
