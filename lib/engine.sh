#!/usr/bin/env bash
# The rows a host stands on: the install record, the checks engine install and update run before
# they touch Docker, and the container and image each row runs, found by its row label. Sourced by
# lib/hosting.sh. See context/hosting-suite.md and context/engines.md.
# Adapted from spike-model-engines (6ce3210): host/vllm.sh's vllm_pull, vllm_running, vllm_run, and
# vllm_remove_images, and host/engines.sh's engines_preflight, finding a row's container by its
# label, building a row's own image in place of refusing it, comparing the image ID and the
# command, and removing only the image a replaced or removed container leaves unused.

# The directory holding one build directory per image the suite builds, images/<name> for an
# image ai-hosting/<name>.
HOSTING_IMAGES=$(cd "$(dirname "${BASH_SOURCE[0]}")/../images" 2>/dev/null && pwd)

# The NVIDIA Container Toolkit's CDI specs, the driver files it mounts into a GPU container: the
# one generated at boot, and any written under /etc/cdi.
HOSTING_CDI_SPECS=(/var/run/cdi/nvidia.yaml '/etc/cdi/*.yaml')

# Prints the path of the install record, the host's installed aliases, one a line.
hosting_record_path() {
  echo "${XDG_STATE_HOME:-$HOME/.local/state}/hosting/aliases"
}

# Prints the recorded aliases, one a line, and nothing when the host has no record.
hosting_record() {
  local path
  path=$(hosting_record_path)
  [[ ! -f $path ]] || grep -v '^$' "$path" || true
}

# Appends the alias given to the record, unless it holds it already.
hosting_record_add() {
  local path
  path=$(hosting_record_path)
  hosting_record | grep -qx -- "$1" && return
  mkdir -p "$(dirname "$path")" && echo "$1" >>"$path"
}

# Drops the alias given from the record.
hosting_record_drop() {
  local path kept
  path=$(hosting_record_path)
  [[ -f $path ]] || return 0
  kept=$(grep -vx -- "$1" "$path" || true)
  printf '%s' "${kept:+$kept$'\n'}" >"$path"
}

# Refuses unless the rows of the loaded profile (hosting_profile_load) that would stand on the
# host, the recorded aliases and those given, reserve fractions of the GPU's memory summing to at
# most 1. Refuses a recorded alias the profile has no row for.
hosting_engine_fractions() {
  local alias aliases sum
  mapfile -t aliases < <({
    hosting_record
    printf '%s\n' "$@"
  } | awk 'NF && !seen[$0]++')
  for alias in $(hosting_record); do
    if ! hosting_profile_alias "$alias" 2>/dev/null; then
      echo "hosting: the record $(hosting_record_path) holds $alias, which" \
        "$HOSTING_PROFILE_NAME has no row for; hosting engine uninstall $alias removes it" >&2
      return 1
    fi
  done
  # shellcheck disable=SC2016 # $ARGS and $a are jq's.
  sum=$(jq -r '[.rows[] | select(.alias as $a | $ARGS.positional | index([$a]))] as $rows
    | ($rows | map(.fraction) | add // 0 | . * 1000000 | round / 1000000) as $sum
    | if $sum > 1 then
        ($rows | map("\(.alias) \(.fraction)") | join(", ")) + " sum to \($sum)"
      else "" end' --args "${aliases[@]}" <<<"$HOSTING_PROFILE_JSON")
  if [[ -n $sum ]]; then
    echo "hosting: the rows that would stand on this host reserve more than all its GPU's" \
      "memory: $sum, over 1" >&2
    return 1
  fi
}

# Refuses unless net.ipv4.ip_nonlocal_bind is 1, so a row's container can bind the tailnet
# address before Tailscale is up, then runs the class's own checks (hosting_engine_preflight_gb10
# and hosting_engine_preflight_strix_halo). Each refusal points at the class's runbook.
hosting_engine_preflight() {
  local sysctl=${HOSTING_SYSROOT:-}/proc/sys/net/ipv4/ip_nonlocal_bind value=
  [[ -r $sysctl ]] && value=$(<"$sysctl")
  if [[ $value != 1 ]]; then
    echo "hosting: net.ipv4.ip_nonlocal_bind is ${value:-unreadable}, not 1; the root step in" \
      "classes/$HOSTING_CLASS/runbook.md, \"Root steps\", sets it" >&2
    return 1
  fi
  hosting_per_class hosting_engine_preflight
}

# Refuses when a CDI spec (HOSTING_CDI_SPECS) names a driver file that is gone, as an upgrade
# without a reboot leaves it, printing the command that regenerates the spec.
# Adapted from spike-ai-pipeline (6a631f1): scripts/host-update-lib.sh's cdi_host_paths and
# host_facts, reading each spec's hostPath entries under HOSTING_SYSROOT.
hosting_engine_preflight_gb10() {
  local spec path missing fail=0
  for spec in "${HOSTING_CDI_SPECS[@]}"; do
    for path in "${HOSTING_SYSROOT:-}"$spec; do
      [[ -r $path ]] || continue
      missing=$(sed -nE "s/^[[:space:]-]*hostPath:[[:space:]]*[\"']?([^\"']+)[\"']?[[:space:]]*$/\1/p" \
        "$path" | while read -r file; do
        [[ -e ${HOSTING_SYSROOT:-}$file ]] || echo "$file"
      done)
      [[ -n $missing ]] || continue
      echo "hosting: the CDI spec ${path#"${HOSTING_SYSROOT:-}"} names ${missing//$'\n'/ }, which" \
        "this host no longer has; sudo nvidia-ctk cdi generate" \
        "--output=${path#"${HOSTING_SYSROOT:-}"} regenerates it (classes/gb10/runbook.md," \
        "\"Root steps\")" >&2
      fail=1
    done
  done
  return "$fail"
}

# The strix-halo class has no checks beyond hosting_engine_preflight's.
hosting_engine_preflight_strix_halo() {
  :
}

# Prints the build directory of the image the row with the alias given names in the loaded profile
# (hosting_profile_load), and nothing for a row on the class's image. Refuses an image the suite
# has no build directory for.
hosting_engine_build_dir() {
  local image
  image=$(jq -r --arg alias "$1" '.rows[] | select(.alias == $alias) | .image // ""' \
    <<<"$HOSTING_PROFILE_JSON")
  [[ -n $image ]] || return 0
  if [[ $image != ai-hosting/* || ! -f $HOSTING_IMAGES/${image#ai-hosting/}/Dockerfile ]]; then
    echo "hosting: $HOSTING_PROFILE_NAME's row $1 names the image $image, which ai-hosting has" \
      "no images/${image#*/}/Dockerfile to build" >&2
    return 1
  fi
  echo "$HOSTING_IMAGES/${image#ai-hosting/}"
}

# Fetches the row's image, after hosting_row: builds the row's own image from its build directory
# (hosting_engine_build_dir), and pulls the class's.
hosting_engine_fetch() {
  local dir
  dir=$(hosting_engine_build_dir "$1") || return
  if [[ -n $dir ]]; then
    docker build --tag "$HOSTING_ROW_IMAGE" "$dir"
  else
    docker pull "$HOSTING_ROW_IMAGE"
  fi
}

# Prints the ID of the container carrying the row label of the alias given, and nothing when the
# host has none. Fails when Docker does, so an unreachable daemon is never read as "not installed".
hosting_engine_container() {
  docker container ls --all --quiet --filter "label=$HOSTING_ROW_LABEL=$1"
}

# Starts the row's container, after hosting_row, creating the compile cache directory first, so
# Docker doesn't create it as root.
hosting_engine_run() {
  mkdir -p "$HOME/.cache/vllm"
  docker run "${HOSTING_ROW_ARGS[@]}" >/dev/null
}

# Removes the image with the ID given when no container, running or stopped, uses it, printing
# what it removed.
hosting_engine_remove_unused_image() {
  local users
  users=$(docker container ls --all --quiet --filter "ancestor=$1") || return
  [[ -z $users ]] || return 0
  docker image rm "$1" >/dev/null || return
  echo "removed image $1"
}

# Checks what engine install and update need before they touch Docker, for the aliases given:
# each is a row of the loaded profile (hosting_profile_load) with an image the suite can fetch,
# the rows standing on the host fit its GPU's memory (hosting_engine_fractions), the host passes
# the preflight (hosting_engine_preflight), and it has a tailnet address (hosting_tailnet_address).
hosting_engine_check() {
  local alias
  for alias in "$@"; do
    hosting_profile_alias "$alias" || return
    hosting_engine_build_dir "$alias" >/dev/null || return
  done
  hosting_engine_fractions "$@" || return
  hosting_engine_preflight || return
  hosting_tailnet_address
}
