#!/usr/bin/env bash
# lint-go-ai-profiles checks each alias's go-ai profile in go-ai/: every file parses as a JSON
# object whose members are among go-ai's formats, completions, messages, and responses, each an
# object; every file names an alias of a class profile; and every class profile's alias has a file.
# It needs jq and mise's pinned mikefarah yq, reads no network, writes nothing, and exits non-zero
# on any failure. See context/host-classes.md.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd) || exit
# shellcheck source=lib/profile.sh
source "$root/lib/profile.sh"

hosting_yq --version >/dev/null || exit
aliases=$(for profile in "$root"/classes/*/profile.toml; do
  hosting_yq -p toml -o json '.' "$profile" | jq -r '.rows[]?.alias'
done) || exit

fail=0
shopt -s nullglob
for file in "$root"/go-ai/*.json; do
  name=go-ai/${file##*/}
  alias=${name#go-ai/}
  alias=${alias%.json}
  if ! grep -qxF -- "$alias" <<<"$aliases"; then
    echo "FAIL: $name names no alias of a class profile" >&2
    fail=1
  fi
  if ! jq -e 'type == "object"
      and all(to_entries[]; (.key | IN("completions", "messages", "responses"))
        and (.value | type == "object"))' "$file" >/dev/null 2>&1; then
    echo "FAIL: $name is not a JSON object of go-ai formats, completions, messages, and responses, each an object" >&2
    fail=1
  fi
done
while read -r alias; do
  if [[ ! -f $root/go-ai/$alias.json ]]; then
    echo "FAIL: go-ai/$alias.json is missing: every class profile's alias has a go-ai profile" >&2
    fail=1
  fi
done <<<"$aliases"
exit "$fail"
