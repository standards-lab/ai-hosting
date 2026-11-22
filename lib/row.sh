#!/usr/bin/env bash
# A row's container, in one place: the image, the docker run options, and the vllm serve arguments
# a row of the host's class profile runs, which hosting profile render prints and engine install
# and update run. Sourced by lib/hosting.sh. See context/engines.md and classes/README.md.
# Adapted from spike-model-engines (6ce3210): host/vllm.sh's vllm_flavor, vllm_row, and vllm_run,
# reading the row from the class profile in place of the rows file, with the row label, and
# without tracing.

# shellcheck source=lib/vllm.env
source "$(dirname "${BASH_SOURCE[0]}")/vllm.env"

# The label every row's container carries, its value the row's alias.
HOSTING_ROW_LABEL=ai-hosting.row

# Where a row's container mounts the host's vLLM compile cache, ~/.cache/vllm, as its home.
HOSTING_ROW_HOME=/home/vllm

# Sets the gb10 class's image repository and the docker run options that give a container its GPU.
hosting_row_platform_gb10() {
  HOSTING_ROW_REPOSITORY=$VLLM_REPOSITORY_GB10
  HOSTING_ROW_DEVICES=(--gpus all)
}

# Sets the strix-halo class's image repository and the docker run options that give a container
# its GPU.
hosting_row_platform_strix_halo() {
  HOSTING_ROW_REPOSITORY=$VLLM_REPOSITORY_STRIX_HALO
  HOSTING_ROW_DEVICES=(--device /dev/kfd --device /dev/dri)
}

# Sets HOSTING_ADDRESS to the host's tailnet IPv4 address, the one address a row publishes its
# port on, refusing when tailscale gives none.
hosting_tailnet_address() {
  if ! HOSTING_ADDRESS=$(tailscale ip -4 2>/dev/null | head -n 1) || [[ -z $HOSTING_ADDRESS ]]; then
    echo "hosting: tailscale ip -4 gives this host no tailnet IPv4 address to publish a row's" \
      "port on; is Tailscale up?" >&2
    return 1
  fi
}

# Reads the row with the alias given from the loaded profile (hosting_profile_load, then
# hosting_profile_alias), published on the address given: hosting_row <alias> <address>. Sets
# HOSTING_ROW_CONTAINER, the container's name; HOSTING_ROW_IMAGE, the row's image, or else the
# class's, at the pinned release; HOSTING_ROW_COMMAND, what the image's entrypoint, vllm serve, is
# given; and HOSTING_ROW_ARGS, docker run's whole argument list: its options, the image, and the
# command. Runs as the invoking user, with ~/.cache/vllm as the container's home.
hosting_row() {
  local fields
  hosting_per_class hosting_row_platform || return
  mapfile -t fields < <(jq -r --arg alias "$1" \
    '.store as $store | .rows[] | select(.alias == $alias) | .container, .port, .image // "", $store' \
    <<<"$HOSTING_PROFILE_JSON")
  HOSTING_ROW_CONTAINER=${fields[0]}
  HOSTING_ROW_IMAGE=${fields[2]:-$HOSTING_ROW_REPOSITORY}:$VLLM_RELEASE
  mapfile -t HOSTING_ROW_COMMAND < <(jq -r --arg alias "$1" '.rows[] | select(.alias == $alias)
    | [.model, "--host", "0.0.0.0", "--port", .port, "--served-model-name", .alias,
        "--max-num-seqs", .cap, "--max-model-len", .context, "--gpu-memory-utilization", .fraction]
      + (if has("queue_limit") then ["--max-num-queued-reqs", .queue_limit] else [] end)
      + (.flags // [])
      + (if has("sampling") then
          ["--override-generation-config", (.sampling | del(.source) | tojson)]
        else [] end)
    | .[] | tostring' <<<"$HOSTING_PROFILE_JSON")
  # shellcheck disable=SC2034 # The commands that source this file read HOSTING_ROW_ARGS.
  HOSTING_ROW_ARGS=(
    --detach --name "$HOSTING_ROW_CONTAINER" --label "$HOSTING_ROW_LABEL=$1"
    --restart unless-stopped "${HOSTING_ROW_DEVICES[@]}"
    --ipc host --user "$(id -u):$(id -g)"
    --publish "$2:${fields[1]}:${fields[1]}"
    --volume "${fields[3]}:${fields[3]}" --env "HF_HUB_CACHE=${fields[3]}"
    --volume "$HOME/.cache/vllm:$HOSTING_ROW_HOME" --env "HOME=$HOSTING_ROW_HOME"
    --env "USER=$(id -un)"
    "$HOSTING_ROW_IMAGE" "${HOSTING_ROW_COMMAND[@]}"
  )
}
