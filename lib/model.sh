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

# Refuses unless hf, the CLI mise.toml pins, is on PATH.
hosting_model_hf() {
  if ! command -v hf >/dev/null; then
    echo "hosting: hf is not on PATH; run mise install and put mise's tools on PATH" >&2
    return 1
  fi
}

# Prints the models in the store given, as hf cache ls finds them, one a line, tab-separated: the
# repository, its size, the recorded rows (hosting_record) of the loaded profile
# (hosting_profile_load) serving it, and the profile's other rows serving it, each list
# comma-separated or "-" when empty. Prints nothing for a store that doesn't exist, and hf's
# warnings only when it fails.
hosting_model_cached() {
  local listed log status=0 installed=()
  [[ -d $1 ]] || return 0
  mapfile -t installed < <(hosting_record)
  log=$(mktemp) || return
  listed=$(hf cache ls --cache-dir "$1" --json 2>"$log") || status=$?
  ((status == 0)) || cat "$log" >&2
  rm -f "$log"
  ((status == 0)) || return "$status"
  # shellcheck disable=SC2016 # $ARGS, $p, $m, and $installed are jq's.
  jq -r --argjson p "$HOSTING_PROFILE_JSON" '
    def names: if length > 0 then join(",") else "-" end;
    $ARGS.positional as $installed
    | .[] | select(.repo_type == "model") | .repo_id as $m
    | [$p.rows[] | select(.model == $m) | .alias] as $rows
    | [$m, .size,
        ($rows | map(select(. as $a | $installed | index([$a]))) | names),
        ($rows | map(select(. as $a | $installed | index([$a]) | not)) | names)]
    | @tsv' --args "${installed[@]}" <<<"$listed"
}

# Prints the store given's models (hosting_model_cached) under a header: each model's repository,
# its size, the rows recorded on this host serving it, and the profile's other rows serving it.
hosting_model_list() {
  local models repo size rows others
  models=$(hosting_model_cached "$1") || return
  printf '%-48s %-10s %-20s %s\n' MODEL SIZE ROWS 'PROFILE ROWS'
  while IFS=$'\t' read -r repo size rows others; do
    [[ -n $repo ]] || continue
    printf '%-48s %-10s %-20s %s\n' "$repo" "$size" "$rows" "$others"
  done <<<"$models"
}

# Prints, or with "yes" as the second argument deletes, what the store given holds that no row
# recorded on this host (hosting_record) serves: each model no recorded row of the loaded profile
# (hosting_profile_load) serves, removed with hf cache rm, and each incomplete download, a
# *.incomplete file, outside those models: hosting_model_prune <store> [yes].
hosting_model_prune() {
  local models repo size rows others file i unused=() sizes=() incomplete=()
  models=$(hosting_model_cached "$1") || return
  while IFS=$'\t' read -r repo size rows others; do
    [[ -n $repo && $rows == - ]] || continue
    unused+=("$repo")
    sizes+=("$size")
  done <<<"$models"
  if [[ -d $1 ]]; then
    while IFS= read -r -d '' file; do
      for repo in "${unused[@]}"; do
        [[ $file == "$1/models--${repo//\//--}/"* ]] && continue 2
      done
      incomplete+=("$file")
    done < <(find "$1" -type f -name '*.incomplete' -print0 | sort -z)
  fi
  if ((${#unused[@]} + ${#incomplete[@]} == 0)); then
    echo "nothing to prune: every model in $1 is served by a row recorded on this host"
    return
  fi
  local verb="would remove"
  [[ ${2:-} == yes ]] && verb=removed
  for i in "${!unused[@]}"; do
    if [[ ${2:-} == yes ]]; then
      hf cache rm "model/${unused[i]}" --cache-dir "$1" --yes >/dev/null || return
    fi
    echo "$verb model ${unused[i]} (${sizes[i]})"
  done
  for file in "${incomplete[@]}"; do
    if [[ ${2:-} == yes ]]; then
      rm -f -- "$file" || return
    fi
    echo "$verb incomplete download $file"
  done
  [[ ${2:-} == yes ]] || echo "hosting model prune --yes removes them"
}

# Downloads the repository given into the store given with hf, the CLI mise.toml pins:
# hosting_model_pull <repo> <store>. Uses the host's hf token when hf auth whoami accepts it, and
# downloads unauthenticated otherwise. A download already in the store fetches nothing. Refuses a
# gated repository the token can't read, saying so, and fails with hf's own error otherwise.
hosting_model_pull() {
  local log status=0 anonymous=()
  hosting_model_hf || return
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
