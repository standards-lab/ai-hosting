#!/usr/bin/env bash
# currency reports every mise tool and GitHub Actions pin that trails its latest release, one
# line each, and exits non-zero when it reports any. It reads the network and writes nothing.
set -euo pipefail
cd "$MISE_PROJECT_ROOT"

stale=0
report() {
  echo "$1"
  stale=1
}

report_outdated_mise_tools() {
  local outdated line
  outdated=$(mise outdated --bump --local --json |
    jq -r 'to_entries[] | "\(.key) \(.value.requested) -> \(.value.bump)"')
  while read -r line; do
    if [ -n "$line" ]; then
      report "mise.toml: $line"
    fi
  done <<<"$outdated"
}

report_outdated_actions() {
  local actions uses action pin repo latest
  actions=$(grep -ho 'uses: *[^ ]*@[^ ]*' .github/workflows/*.yml | sed 's/uses: *//' | sort -u)
  for uses in $actions; do
    action=${uses%@*}
    pin=${uses#*@}
    repo=$(echo "$action" | cut -d/ -f1,2)
    latest=$(gh api "repos/$repo/releases/latest" --jq .tag_name)
    [ "$pin" = "$latest" ] || report ".github/workflows: $action $pin -> $latest"
  done
}

report_outdated_mise_tools
report_outdated_actions
exit "$stale"
