#!/usr/bin/env bash
# The model store: the Hugging Face cache the host class's profile names, which hf downloads into
# and every row's container mounts. Sourced by lib/hosting.sh. See context/hosting-suite.md.

# Refuses an argument that isn't a Hugging Face model repository, <owner>/<name>.
hosting_model_repo() {
  if [[ ! $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "hosting: $1 is not a Hugging Face model repository, <owner>/<name>" >&2
    return 1
  fi
}

# Prints the loaded profile's (hosting_profile_load) model store.
hosting_model_store() {
  jq -r '.store' <<<"$HOSTING_PROFILE_JSON"
}

# Downloads the repository given into the store given with hf, the CLI mise.toml pins:
# hosting_model_pull <repo> <store>. Uses the host's hf token when hf auth whoami accepts it, and
# downloads unauthenticated otherwise. A download already in the store fetches nothing. Refuses a
# gated repository the token can't read, saying so, and fails with hf's own error otherwise.
hosting_model_pull() {
  local log status=0 anonymous=()
  if ! command -v hf >/dev/null; then
    echo "hosting: hf is not on PATH; run mise install and put mise's tools on PATH" >&2
    return 1
  fi
  hf auth whoami >/dev/null 2>&1 || anonymous=(HF_HUB_DISABLE_IMPLICIT_TOKEN=1)
  log=$(mktemp) || return
  { env "${anonymous[@]}" HF_HUB_CACHE="$2" hf download "$1" --cache-dir "$2" 2>&1 >&3 |
    tee "$log" >&2; } 3>&1 || status=$?
  if ((status != 0)) && grep -q 'requires approval' "$log"; then
    echo "hosting: $1 is a gated repository: an account granted access at" \
      "https://huggingface.co/$1 must hold the token hf auth login stores on this host" \
      "${anonymous:+(hf auth whoami finds none)}" >&2
  fi
  rm -f "$log"
  return "$status"
}
