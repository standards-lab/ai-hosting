#!/usr/bin/env bash
# The gateway's stack and agentgateway's config: the render that fills
# compose/agentgateway/config.template.yaml with each row's port and model from the class
# profiles, each key from keys.toml, and the switches in overflow.toml; the validation of a config
# with the pinned agentgateway image; the two together, which put a config in place, with the
# compose override holding each row host's tailnet address, only once it validates; and the
# compose stack the gateway group runs on gb10-2, its Foundry key read from fnox. Sourced by
# lib/hosting.sh. See context/gateway.md.

# The clone's root, holding the stack's compose.yml and fnox.toml.
HOSTING_GATEWAY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# The directory holding agentgateway's Dockerfile, its config template, the key list, the
# overflow switches, and the rendered config.yaml, which the gateway's compose service mounts.
HOSTING_GATEWAY=$HOSTING_GATEWAY_ROOT/compose/agentgateway

# The gitignored directory, 0700, holding what the stack reads that the clone commits no copy of:
# the Foundry key's secret file, which compose/agentgateway.yml names, and the render's compose
# override and env file, which hold the tailnet addresses.
HOSTING_GATEWAY_STATE=$HOSTING_GATEWAY_ROOT/.state/gateway

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
# by the image's uid 65532, validates the copy (hosting_gateway_validate), writes the compose
# override and env file holding the addresses its row hosts and the gateway publish on
# (hosting_gateway_addresses, after hosting_tailnet_address), and only then renames the copy to
# config.yaml, so agentgateway never reads an unvalidated config. Fails, removing the copy and
# leaving config.yaml, the override, and the env file as they were, when the render, the
# validation, or an address lookup does.
hosting_gateway_render_in_place() {
  local copy
  copy=$(mktemp "$HOSTING_GATEWAY/config.yaml.XXXXXX") || return
  chmod 644 "$copy"
  if hosting_gateway_render >"$copy" && hosting_gateway_validate "$copy" &&
    hosting_gateway_addresses "$copy"; then
    mv "$copy" "$HOSTING_GATEWAY/config.yaml"
    return
  fi
  rm -f "$copy"
  return 1
}

# Refuses, before anything touches Docker, a host whose class (hosting_class) isn't gb10, the
# class of gb10-2, where the gateway's stack runs.
hosting_gateway_host() {
  hosting_class || return
  if [[ $HOSTING_CLASS != gb10 ]]; then
    echo "hosting: the gateway's stack runs on gb10-2, a gb10 host, and this host is" \
      "$HOSTING_CLASS" >&2
    return 1
  fi
}

# Prints each row host the config at the path given names, one a line, sorted: each provider's
# hostOverride without its port, leaving out the Azure hosts, which ${AZURE_FOUNDRY_ACCOUNT} opens.
hosting_gateway_hosts() {
  local json
  json=$(hosting_yq -o json '.' "$1") || return
  jq -r '[.. | objects | .hostOverride? | strings | select(startswith("$") | not)
    | sub(":[0-9]+$"; "")] | unique[]' <<<"$json"
}

# Writes the stack's compose override and env file into HOSTING_GATEWAY_STATE from the config at
# the path given, after hosting_tailnet_address: the override, compose.override.yml, gives
# agentgateway an extra_hosts entry for each row host the config names (hosting_gateway_hosts),
# since a container on gb10-2 can't resolve a tailnet short name; the env file, compose.env, sets
# GATEWAY_ADDRESS, where the consumer port is published, to this host's tailnet address. That one
# lookup also serves the row host this host is, by its short name; tailscale gives each other
# host's. Prints no address, and fails, writing neither file, when a host has none.
hosting_gateway_addresses() {
  local hosts host address entries=() override env
  hosts=$(hosting_gateway_hosts "$1") || return
  for host in $hosts; do
    address=$HOSTING_ADDRESS
    if [[ $host != "${HOSTNAME%%.*}" ]]; then
      address=$(tailscale ip -4 "$host" 2>/dev/null | head -n 1) || address=
    fi
    if [[ -z $address ]]; then
      echo "hosting: tailscale ip -4 $host gives no tailnet IPv4 address for $host, a row host" \
        "the gateway's config names; is it on the tailnet?" >&2
      return 1
    fi
    entries+=("      $host: \"$address\"")
  done
  mkdir -p "$HOSTING_GATEWAY_STATE" || return
  chmod 700 "$HOSTING_GATEWAY_STATE" || return
  override=$(mktemp "$HOSTING_GATEWAY_STATE/compose.override.yml.XXXXXX") || return
  env=$(mktemp "$HOSTING_GATEWAY_STATE/compose.env.XXXXXX") || return
  {
    echo "# The gateway's compose override, written by hosting gateway render: each row host's"
    echo "# tailnet address. See context/gateway.md"
    echo "services:"
    echo "  agentgateway:"
    if ((${#entries[@]})); then
      echo "    extra_hosts:"
      printf '%s\n' "${entries[@]}"
    else
      echo "    extra_hosts: {}"
    fi
  } >"$override"
  echo "GATEWAY_ADDRESS=$HOSTING_ADDRESS" >"$env"
  mv "$override" "$HOSTING_GATEWAY_STATE/compose.override.yml"
  mv "$env" "$HOSTING_GATEWAY_STATE/compose.env"
}

# Runs docker compose with the arguments given on the gateway's stack, the clone's compose.yml,
# with the render's override and env file (hosting_gateway_addresses) when they are present.
hosting_gateway_compose() {
  local options=(--file "$HOSTING_GATEWAY_ROOT/compose.yml")
  if [[ -f $HOSTING_GATEWAY_STATE/compose.override.yml ]]; then
    options+=(--file "$HOSTING_GATEWAY_STATE/compose.override.yml")
  fi
  if [[ -f $HOSTING_GATEWAY_STATE/compose.env ]]; then
    options+=(--env-file "$HOSTING_GATEWAY_STATE/compose.env")
  fi
  docker compose "${options[@]}" "$@"
}

# Prints the secret with the name given from the clone's fnox.toml, refusing when fnox gives
# none, as on a host holding no age identity among its recipients. See context/secrets.md.
hosting_gateway_secret() {
  local value
  if ! value=$(fnox -c "$HOSTING_GATEWAY_ROOT/fnox.toml" get "$1") || [[ -z $value ]]; then
    echo "hosting: fnox gives no $1 from $HOSTING_GATEWAY_ROOT/fnox.toml; it decrypts it only" \
      "on a host holding an age identity among its recipients" >&2
    return 1
  fi
  printf '%s' "$value"
}

# Writes the key given to the Foundry key's secret file, azure-foundry-key in
# HOSTING_GATEWAY_STATE, which compose/agentgateway.yml names: 0644, so agentgateway's uid 65532
# reads it, in the 0700 directory, since Compose outside swarm ignores a secret's uid and mode.
# The key reaches no command's arguments.
hosting_gateway_key_file() {
  local file
  mkdir -p "$HOSTING_GATEWAY_STATE" || return
  chmod 700 "$HOSTING_GATEWAY_STATE" || return
  file=$(mktemp "$HOSTING_GATEWAY_STATE/azure-foundry-key.XXXXXX") || return
  printf '%s' "$1" >"$file" && chmod 644 "$file" &&
    mv "$file" "$HOSTING_GATEWAY_STATE/azure-foundry-key"
}

# Builds and starts the stack, waiting for it: refuses unless the render
# (hosting_gateway_render_in_place) has put the config, the override, and the env file in place;
# reads the Foundry key and account from fnox (hosting_gateway_secret) and writes the key's secret
# file (hosting_gateway_key_file); then runs compose with the account in its environment, which
# the key never enters. Builds with buildx's default attestations off, since Compose drops a
# service's provenance: false, and an attestation's build times would give an unchanged Dockerfile
# a new image ID and recreate its container on every up. See context/gateway.md
hosting_gateway_up() {
  local file key account
  for file in "$HOSTING_GATEWAY/config.yaml" "$HOSTING_GATEWAY_STATE/compose.override.yml" \
    "$HOSTING_GATEWAY_STATE/compose.env"; do
    if [[ ! -f $file ]]; then
      echo "hosting: $file is missing; hosting gateway render writes it" >&2
      return 1
    fi
  done
  key=$(hosting_gateway_secret AZURE_FOUNDRY_KEY) || return
  account=$(hosting_gateway_secret AZURE_FOUNDRY_ACCOUNT) || return
  hosting_gateway_key_file "$key" || return
  AZURE_FOUNDRY_ACCOUNT=$account BUILDX_NO_DEFAULT_ATTESTATIONS=1 \
    hosting_gateway_compose up --detach --wait --build
}

# Prints a table of the stack's containers, each service's container, state, and status, then
# flags agentgateway, the one container bound to gb10-2's tailnet address, when it is stranded
# (hosting_observe_stranded). Fails when the stack has no container, any is not running, or
# agentgateway is stranded, and when Docker does.
hosting_gateway_status() {
  local containers service name state status id row address published networks flag fail=0
  containers=$(hosting_gateway_compose ps --all \
    --format '{{.Service}}'$'\t''{{.Name}}'$'\t''{{.State}}'$'\t''{{.Status}}') || return
  if [[ -z $containers ]]; then
    echo "the gateway's stack has no container; hosting gateway up starts it"
    return 1
  fi
  printf '%-16s %-30s %-10s %s\n' SERVICE CONTAINER STATE STATUS
  while IFS=$'\t' read -r service name state status; do
    printf '%-16s %-30s %-10s %s\n' "$service" "$name" "$state" "$status"
    [[ $state == running ]] || fail=1
  done <<<"$containers"
  id=$(hosting_gateway_compose ps --all --quiet agentgateway) || return
  [[ -n $id ]] || return 1
  row=$(hosting_observe_inspect com.docker.compose.service "$id") || return
  IFS=$'\t' read -r _ _ name state address published networks <<<"$row"
  if [[ $state == running ]] && flag=$(hosting_observe_stranded "$name" "$address" "$published" \
    "$networks"); then
    hosting_observe_flags "$flag"
    fail=1
  fi
  return "$fail"
}
