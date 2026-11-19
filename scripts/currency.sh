#!/usr/bin/env bash
# currency reports every mise tool and GitHub Actions pin that trails its latest release, one
# line each, and exits non-zero when it reports any. It reads the network and writes nothing.
# Run it through `mise run currency`. The hosts and gateway tasks add the image pins.
set -euo pipefail
cd "$MISE_PROJECT_ROOT"

stale=0
report() {
  echo "$1"
  stale=1
}

# mise tools pinned below their latest version.
outdated=$(mise outdated --bump --local --json |
  jq -r 'to_entries[] | "\(.key) \(.value.requested) -> \(.value.bump)"')
while read -r line; do
  [ -n "$line" ] && report "mise.toml: $line"
done <<<"$outdated"

# GitHub Actions pinned below the action's latest release.
actions=$(grep -ho 'uses: *[^ ]*@[^ ]*' .github/workflows/*.yml | sed 's/uses: *//' | sort -u)
for uses in $actions; do
  action=${uses%@*}
  pin=${uses#*@}
  repo=$(echo "$action" | cut -d/ -f1,2)
  latest=$(gh api "repos/$repo/releases/latest" --jq .tag_name)
  [ "$pin" = "$latest" ] || report ".github/workflows: $action $pin -> $latest"
done

exit "$stale"
