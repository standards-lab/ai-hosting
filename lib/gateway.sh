#!/usr/bin/env bash
# agentgateway's config: the render that fills compose/agentgateway/config.template.yaml with each
# row's port and model from the class profiles, each key from keys.toml, and the switches in
# overflow.toml; the validation of a config with the pinned agentgateway image; and the two
# together, which put a config in place only once it validates. Sourced by lib/hosting.sh. See
# context/gateway.md.

# The directory holding agentgateway's Dockerfile, its config template, the key list, the
# overflow switches, and the rendered config.yaml, which the gateway's compose service mounts.
HOSTING_GATEWAY=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/compose/agentgateway

# Runs jq with the program given, which may call lib/profile.jq's and lib/gateway.jq's
# definitions, and the remaining arguments.
hosting_gateway_jq() {
  jq -L "$(dirname "${BASH_SOURCE[0]}")" "include \"profile\"; include \"gateway\"; $1" "${@:2}"
}

# Prints each error the jq program given yields over the JSON given as
# "hosting: <name>: <key path>: <message>", and fails if it yields any:
# hosting_gateway_report <name> <json> <program> [jq arguments].
hosting_gateway_report() {
  local errors line
  errors=$(hosting_gateway_jq "$3"' | "\(.path | key_path): \(.message)"' -r "${@:4}" <<<"$2") ||
    return
  [[ -z $errors ]] && return
  while IFS= read -r line; do
    echo "hosting: $1: $line" >&2
  done <<<"$errors"
  return 1
}

# Decodes the TOML file given to JSON, printing yq's error as "hosting: <name>: <error>" and
# failing when it doesn't parse: hosting_gateway_toml <path> <name>.
hosting_gateway_toml() {
  local json
  if ! json=$(hosting_yq -p toml -o json '.' "$1" 2>&1); then
    echo "hosting: $2: ${json#Error: }" >&2
    return 1
  fi
  echo "$json"
}

# Prints agentgateway's config rendered from the template, the class profiles, the key list, and
# the overflow switches, holding each key's hash and no secret. Validates every input first,
# printing each error at once: each class profile (hosting_profile_validate); the key list, each
# [[keys]] entry a consumer, its class, interactive or bulk, and its key's SHA-256 hash in
# sha256; the switches, one true or false for each alias with an Azure group; and one row for
# each route's alias across the profiles. Fails, printing nothing, when any is invalid.
hosting_gateway_render() {
  local fail=0 template rows='[]' class profile name keys overflow
  hosting_yq --version >/dev/null || return
  template=$(hosting_yq -o json 'explode(.)' "$HOSTING_GATEWAY/config.template.yaml") || return
  for class in "${HOSTING_CLASSES[@]}"; do
    profile=$(hosting_profile_path "$class")
    name=classes/$class/profile.toml
    if ! hosting_profile_validate "$profile" "$name"; then
      fail=1
      continue
    fi
    rows=$(hosting_yq -p toml -o json '.' "$profile" |
      jq --argjson rows "$rows" '$rows + [.rows[] | {alias, port, model}]') || return
  done
  name=compose/agentgateway/keys.toml
  if keys=$(hosting_gateway_toml "$HOSTING_GATEWAY/keys.toml" "$name"); then
    # shellcheck disable=SC2016 # $template is jq's, bound by --argjson.
    hosting_gateway_report "$name" "$keys" 'key_errors($template | key_classes)' \
      --argjson template "$template" || fail=1
  else
    fail=1
  fi
  name=compose/agentgateway/overflow.toml
  if overflow=$(hosting_gateway_toml "$HOSTING_GATEWAY/overflow.toml" "$name"); then
    # shellcheck disable=SC2016 # $template is jq's, bound by --argjson.
    hosting_gateway_report "$name" "$overflow" 'overflow_errors($template | switchable)' \
      --argjson template "$template" || fail=1
  else
    fail=1
  fi
  if ((fail == 0)); then
    # shellcheck disable=SC2016 # $rows is jq's, bound by --argjson.
    hosting_gateway_report classes "$template" 'row_errors($rows)' --argjson rows "$rows" ||
      fail=1
  fi
  ((fail == 0)) || return 1
  echo "# agentgateway's config, rendered by lib/gateway.sh from config.template.yaml."
  echo "# See context/gateway.md"
  # shellcheck disable=SC2016 # $rows, $keys, and $overflow are jq's, bound by --argjson.
  hosting_gateway_jq 'render($rows; $keys; $overflow)' --argjson rows "$rows" \
    --argjson keys "$keys" --argjson overflow "$overflow" <<<"$template" |
    hosting_yq -p json -o yaml '.'
}

# Prints the image agentgateway's Dockerfile pins.
hosting_gateway_image() {
  sed -n 's/^FROM //p' "$HOSTING_GATEWAY/Dockerfile"
}

# Validates the config at the path given with the pinned agentgateway image's --validate-only, on
# no network, changing nothing: the config's directory is mounted read-only, each file it reads
# from (a `file:` value) is an empty stand-in, and each ${VAR} it expands is set to a placeholder.
# Prints agentgateway's refusal and fails when the config is invalid.
hosting_gateway_validate() {
  local dir file json path variable options=() stand_in status
  dir=$(cd "$(dirname "$1")" && pwd) || return
  file=$(basename "$1")
  json=$(hosting_yq -o json '.' "$1") || return
  stand_in=$(mktemp) || return
  chmod 644 "$stand_in"
  while IFS= read -r path; do
    options+=(--volume "$stand_in:$path:ro")
  done < <(jq -r '[.. | objects | .file? | strings] | unique[]' <<<"$json")
  while IFS= read -r variable; do
    options+=(--env "$variable=validate")
  done < <(grep -oP '\$\{\K[A-Za-z_][A-Za-z0-9_]*(?=\})' "$1" | sort -u)
  docker run --rm --network none --volume "$dir:/config:ro" "${options[@]}" \
    "$(hosting_gateway_image)" -f "/config/$file" --validate-only
  status=$?
  rm -f "$stand_in"
  return "$status"
}

# Renders agentgateway's config (hosting_gateway_render) into a copy beside config.yaml, readable
# by the image's uid 65532, validates the copy (hosting_gateway_validate), and only then renames
# it to config.yaml, so agentgateway never reads an unvalidated config. Fails, removing the copy
# and leaving config.yaml as it was, when the render or the validation does.
hosting_gateway_render_in_place() {
  local copy
  copy=$(mktemp "$HOSTING_GATEWAY/config.yaml.XXXXXX") || return
  chmod 644 "$copy"
  if hosting_gateway_render >"$copy" && hosting_gateway_validate "$copy"; then
    mv "$copy" "$HOSTING_GATEWAY/config.yaml"
    return
  fi
  rm -f "$copy"
  return 1
}
