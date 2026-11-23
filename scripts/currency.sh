#!/usr/bin/env bash
# currency reports every mise tool and GitHub Actions pin that trails its latest release, the vLLM
# release in lib/vllm.env, and each image the suite builds (images/*/Dockerfile): its base image's
# tag and digest against the vLLM release's, and its Python packages' pins against PyPI's latest,
# one line each, and exits non-zero when it reports any. It reads the network and writes nothing.
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

report_outdated_vllm() {
  local latest
  latest=$(gh api repos/vllm-project/vllm/releases/latest --jq .tag_name)
  [ "$VLLM_RELEASE" = "$latest" ] || report "lib/vllm.env: vLLM $VLLM_RELEASE -> $latest"
}

report_outdated_images() {
  local dockerfile base repository tag digest latest pin package version
  for dockerfile in images/*/Dockerfile; do
    base=$(sed -n 's/^FROM //p' "$dockerfile")
    repository=${base%%:*}
    tag=${base#*:}
    tag=${tag%@*}
    digest=${base#*@}
    [ "$tag" = "$VLLM_RELEASE" ] || report "$dockerfile: $repository $tag -> $VLLM_RELEASE"
    latest=$(curl -fsSL "https://hub.docker.com/v2/repositories/$repository/tags/$VLLM_RELEASE" |
      jq -r .digest)
    [ "$digest" = "$latest" ] || report "$dockerfile: $repository:$VLLM_RELEASE $digest -> $latest"
    while read -r pin; do
      package=${pin%%==*}
      version=${pin#*==}
      latest=$(curl -fsSL "https://pypi.org/pypi/$package/json" | jq -r .info.version)
      [ "$version" = "$latest" ] || report "$dockerfile: $package $version -> $latest"
    done < <(grep -o '[A-Za-z0-9_.-]*==[^ ]*' "$dockerfile")
  done
}

# shellcheck source=lib/vllm.env
source lib/vllm.env
report_outdated_mise_tools
report_outdated_actions
report_outdated_vllm
report_outdated_images
exit "$stale"
