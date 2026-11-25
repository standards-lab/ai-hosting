#!/usr/bin/env bash
# currency reports every mise tool pin, the bench environment's (mise.bench.toml) among them, and
# every GitHub Actions pin that trails its latest release, the vLLM release in lib/vllm.env, each
# image the suite builds (images/*/Dockerfile): its base image's tag and digest against the vLLM
# release's, and its Python packages' pins against PyPI's latest, and each gateway service's image
# (compose/*/Dockerfile): its FROM tag against the highest release tag crane lists with the same
# `v` prefix and variant suffix, one line each. A pin the HOLDS list names, one
# `<item> <pin>: <reason>` line each in mise.bench.toml's [env], is reported as held with its
# reason. It exits non-zero when it reports any pin that isn't held. It reads the network and
# writes nothing.
# See architecture/principles/rolling-currency.md
set -euo pipefail
cd "$MISE_PROJECT_ROOT"

holds=$(MISE_ENV=bench MISE_LOG_LEVEL=error mise env --json | jq -r '.HOLDS // ""')

held() {
  local line
  while IFS= read -r line; do
    if [[ $line == "$1 $2: "* ]]; then
      echo "${line#"$1 $2: "}"
      return
    fi
  done <<<"$holds"
}

stale=0
trailing() {
  local reason
  reason=$(held "$2" "$3")
  if [ -n "$reason" ]; then
    echo "$1: $2 $3 -> $4 held: $reason"
  else
    echo "$1: $2 $3 -> $4"
    stale=1
  fi
}

report_outdated_mise_tools() {
  local outdated path name pinned latest
  outdated=$(MISE_ENV=bench MISE_LOG_LEVEL=error mise outdated --bump --local --json |
    jq -r --arg root "$MISE_PROJECT_ROOT/" 'to_entries[]
      | (.value.bump // .value.latest) as $latest
      | select($latest != null and $latest != .value.requested)
      | [(.value.source.path | ltrimstr($root)), .key, .value.requested, $latest] | @tsv')
  while IFS=$'\t' read -r path name pinned latest; do
    if [ -n "$name" ]; then
      trailing "$path" "$name" "$pinned" "$latest"
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
    [ "$pin" = "$latest" ] || trailing .github/workflows "$action" "$pin" "$latest"
  done
}

report_outdated_vllm() {
  local latest
  latest=$(gh api repos/vllm-project/vllm/releases/latest --jq .tag_name)
  [ "$VLLM_RELEASE" = "$latest" ] || trailing lib/vllm.env vLLM "$VLLM_RELEASE" "$latest"
}

report_outdated_images() {
  local dockerfile base repository tag digest latest pin package version
  for dockerfile in images/*/Dockerfile; do
    base=$(sed -n 's/^FROM //p' "$dockerfile")
    repository=${base%%:*}
    tag=${base#*:}
    tag=${tag%@*}
    digest=${base#*@}
    [ "$tag" = "$VLLM_RELEASE" ] || trailing "$dockerfile" "$repository" "$tag" "$VLLM_RELEASE"
    latest=$(curl -fsSL "https://hub.docker.com/v2/repositories/$repository/tags/$VLLM_RELEASE" |
      jq -r .digest)
    [ "$digest" = "$latest" ] || trailing "$dockerfile" "$repository:$VLLM_RELEASE" "$digest" "$latest"
    while read -r pin; do
      package=${pin%%==*}
      version=${pin#*==}
      latest=$(curl -fsSL "https://pypi.org/pypi/$package/json" | jq -r .info.version)
      [ "$version" = "$latest" ] || trailing "$dockerfile" "$package" "$version" "$latest"
    done < <(grep -o '[A-Za-z0-9_.-]*==[^ ]*' "$dockerfile")
  done
}

latest_release_tag() {
  local image=$1 pin=$2 prefix='' version suffix
  if [[ $pin == v* ]]; then
    prefix=v
  fi
  version=${pin#"$prefix"}
  suffix=${version#"${version%%[!0-9.]*}"}
  crane ls "$image" |
    sed -nE "s/^${prefix}([0-9]+(\.[0-9]+)+)${suffix//./\\.}\$/\1/p" |
    sort -V | tail -n 1 | sed "s/.\+/${prefix}&${suffix}/"
}

report_outdated_service_images() {
  local dockerfile base image pin latest
  for dockerfile in compose/*/Dockerfile; do
    [ -e "$dockerfile" ] || continue
    base=$(sed -n 's/^FROM  *\([^ ]*\).*/\1/p' "$dockerfile" | head -n 1)
    image=${base%:*}
    pin=${base##*:}
    latest=$(latest_release_tag "$image" "$pin")
    if [ -z "$latest" ]; then
      echo "$dockerfile: $image lists no release tag of $pin's form" >&2
      stale=1
    elif [ "$pin" != "$latest" ]; then
      trailing "$dockerfile" "$image" "$pin" "$latest"
    fi
  done
}

# shellcheck source=lib/vllm.env
source lib/vllm.env
report_outdated_mise_tools
report_outdated_actions
report_outdated_vllm
report_outdated_images
report_outdated_service_images
exit "$stale"
