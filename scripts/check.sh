#!/usr/bin/env bash
# Shellchecks every tracked file whose first line is a sh or bash shebang, checks that every
# relative link in a tracked Markdown file resolves to a present file, and runs lint-context,
# lint-references, and scripts/lint-secrets.sh. Reads no network.
set -uo pipefail
cd "$(dirname "$0")/.." || exit

fail=0

shellcheck_scripts() {
  local file scripts=()
  while IFS= read -r -d '' file; do
    if head -n 1 "$file" | grep -Eq '^#!.*\b(ba)?sh\b'; then
      scripts+=("$file")
    fi
  done < <(git ls-files -z)
  if ((${#scripts[@]})); then
    shellcheck "${scripts[@]}" || fail=1
  fi
}

links_without_scheme_or_anchor() {
  grep -oP '\]\(\K(?![a-z][a-z0-9+.-]*:|#)[^)\s]+' "$1"
}

check_relative_links() {
  local file dir target
  while IFS= read -r -d '' file; do
    dir=$(dirname "$file")
    while read -r target; do
      target=${target%%#*}
      [[ -z $target ]] && continue
      if [[ ! -e "$dir/$target" ]]; then
        echo "FAIL: $file: link $target does not resolve" >&2
        fail=1
      fi
    done < <(links_without_scheme_or_anchor "$file")
  done < <(git ls-files -z -- '*.md')
}

run_lint() {
  if ! command -v "$1" >/dev/null; then
    echo "FAIL: $1 is not on PATH; run mise install" >&2
    fail=1
    return
  fi
  "$1" || fail=1
}

shellcheck_scripts
check_relative_links
run_lint lint-context
run_lint lint-references
scripts/lint-secrets.sh || fail=1
exit "$fail"
