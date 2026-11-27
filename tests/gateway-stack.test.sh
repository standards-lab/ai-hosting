#!/usr/bin/env bash
# Tests for the hosting gateway group (bin/hosting-gateway-*, lib/gateway.sh), run on a copy of the
# clone's compose project and class profiles, with docker, fnox, and tailscale stubbed to log their
# calls, docker answering from a fake stack and validating every config: each verb refuses a host
# that isn't gb10 before any docker call, render puts the config and the addresses in place only
# once both are good and commits no address, up keeps the Foundry key off every command line and
# out of compose's environment, and down, reset, and status act on the stack as they say.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/hosting.sh
source "$repo/lib/hosting.sh"

foundry_key=fixture-foundry-key
foundry_account=fixture-account

# Readies a gb10 host named gb10-2 holding a copy of the compose project, with docker, fnox, and
# tailscale stubbed: tailscale gives this host 192.0.2.10 and each other row host its own address,
# and fails for any host HOSTING_TEST_OFFLINE names; fnox gives the fixture key and account; docker
# compose answers ps from the fake stack, and docker run, the validation, fails when
# HOSTING_TEST_INVALID is set.
ready_host() {
  cp -R "$repo/compose.yml" "$repo/compose" "$clone/"
  rm -f "$clone/compose/torii/config.yaml"
  state=$clone/.state/gateway
  export HOSTING_CLASS=gb10 HOSTNAME=gb10-2 HOSTING_TEST_DOCKER=$tmp/docker
  unset HOSTING_TEST_INVALID HOSTING_TEST_OFFLINE
  mkdir -p "$HOSTING_TEST_DOCKER"
  write_stub docker "$(
    cat <<'EOF'
case $1 in
  compose)
    [[ " $* " != *" up "* ]] || env >"$HOSTING_TEST_DOCKER/up-env"
    if [[ $* == *"ps --all --quiet torii" ]]; then
      cat "$HOSTING_TEST_DOCKER/id" 2>/dev/null || true
    elif [[ $* == *"ps --all --format"* ]]; then
      cat "$HOSTING_TEST_DOCKER/ps" 2>/dev/null || true
    fi
    ;;
  container) cat "$HOSTING_TEST_DOCKER/inspect" ;;
  run)
    if [[ -n ${HOSTING_TEST_INVALID:-} ]]; then
      echo "Error: invalid" >&2
      exit 1
    fi
    ;;
esac
EOF
  )"
  write_stub tailscale "$(
    cat <<'EOF'
case ${3:-} in
  '') echo 192.0.2.10 ;;
  "${HOSTING_TEST_OFFLINE:-}") exit 1 ;;
  gb10-1) echo 192.0.2.11 ;;
  gb10-2) echo 192.0.2.10 ;;
  framework) echo 192.0.2.12 ;;
  framework-2) echo 192.0.2.13 ;;
  *) exit 1 ;;
esac
EOF
  )"
  write_stub fnox "$(
    cat <<EOF
case \${4:-} in
  AZURE_FOUNDRY_KEY) echo $foundry_key ;;
  AZURE_FOUNDRY_ACCOUNT) echo $foundry_account ;;
  *) exit 1 ;;
esac
EOF
  )"
}

# Writes what a render leaves: the config, the compose override, and the env file.
rendered() {
  mkdir -p "$state"
  echo "the rendered config" >"$clone/compose/torii/config.yaml"
  echo "the override" >"$state/compose.override.yml"
  echo "GATEWAY_ADDRESS=192.0.2.10" >"$state/compose.env"
}

# Sets the fake stack: one tab-separated ps line a container given, as
# <service> <name> <state> <status>, and Torii's inspect, running with the count of networks
# given: stack <networks> [<service> <name> <state> <status>]...
stack() {
  local networks=$1
  shift
  while (($# >= 4)); do
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$HOSTING_TEST_DOCKER/ps"
    shift 4
  done
  echo 0123456789abcdef >"$HOSTING_TEST_DOCKER/id"
  jq -n --argjson networks "$networks" '[{
    Id: "0123456789abcdef", Name: "/gateway-torii-1", State: {Status: "running"},
    Config: {Labels: {"com.docker.compose.service": "torii"}},
    HostConfig: {PortBindings: {"3000/tcp": [{HostIp: "192.0.2.10", HostPort: "3000"}],
      "3001/tcp": [{HostIp: "127.0.0.1", HostPort: "3001"}]}},
    NetworkSettings: {Ports: {"3000/tcp": [{HostIp: "192.0.2.10", HostPort: "3000"}]},
      Networks: (if $networks == 0 then {} else {gateway_default: {}} end)}}]' \
    >"$HOSTING_TEST_DOCKER/inspect"
}

docker_calls() {
  calls | grep '^docker' || true
}

compose_call() {
  echo "docker compose --file $clone/compose.yml --file $state/compose.override.yml" \
    "--env-file $state/compose.env $*"
}

test_every_verb_refuses_a_host_that_isnt_gb10_before_docker() {
  local verb
  ready_host
  rendered
  for verb in render validate up down reset status; do
    HOSTING_CLASS=strix-halo run_hosting gateway "$verb"
    assert_equal "$verb status" "$status" 1
    assert_equal "$verb stderr" "$err" \
      "hosting: the gateway's stack runs on gb10-2, a gb10 host, and this host is strix-halo"
  done
  unset HOSTING_CLASS
  run_hosting gateway status
  assert_equal "unknown class status" "$status" 1
  assert_contains "unknown class stderr" "$err" "this host is no known class"
  assert_equal calls "$(calls)" ""
}

test_render_puts_the_config_override_and_env_file_in_place() {
  ready_host
  run_hosting gateway render
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "rendered $clone/compose/torii/config.yaml;\
 hosting gateway up starts the stack on it"
  assert_contains config "$(<"$clone/compose/torii/config.yaml")" "hostOverride: gb10-1:"
  assert_contains docker "$(docker_calls)" " --validate-only"
  assert_equal hosts "$(hosting_yq -o json '.services.torii.extra_hosts' \
    "$state/compose.override.yml" | jq -r 'to_entries[] | "\(.key) \(.value)"')" \
    "framework 192.0.2.12
framework-2 192.0.2.13
gb10-1 192.0.2.11
gb10-2 192.0.2.10"
  assert_equal env "$(<"$state/compose.env")" "GATEWAY_ADDRESS=192.0.2.10"
  assert_equal "state mode" "$(stat -c %a "$state")" 700
  assert_equal "lookups" "$(calls | grep '^tailscale')" "tailscale ip -4
tailscale ip -4 framework
tailscale ip -4 framework-2
tailscale ip -4 gb10-1"
}

test_render_commits_no_address() {
  ready_host
  run_hosting gateway render
  assert_equal status "$status" 0
  [[ $out$err != *192.0.2.* ]] || fail "render printed an address"
  assert_equal "files outside .state" \
    "$(grep -rl '192\.0\.2\.' "$clone" --exclude-dir=.state || true)" ""
}

test_render_leaves_everything_in_place_when_validation_fails() {
  ready_host
  rendered
  export HOSTING_TEST_INVALID=1
  run_hosting gateway render
  assert_equal status "$status" 1
  assert_equal stderr "$err" "Error: invalid"
  assert_equal config "$(<"$clone/compose/torii/config.yaml")" "the rendered config"
  assert_equal override "$(<"$state/compose.override.yml")" "the override"
  assert_equal copies "$(find "$clone/compose/torii" -name 'config.yaml.*')" ""
  assert_equal state "$(find "$state" -type f -printf '%f\n' | sort)" "compose.env
compose.override.yml"
}

test_render_leaves_everything_in_place_when_a_row_host_has_no_address() {
  ready_host
  export HOSTING_TEST_OFFLINE=framework
  run_hosting gateway render
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: tailscale ip -4 framework gives no tailnet IPv4 address\
 for framework, a row host the gateway's config names; is it on the tailnet?"
  assert_equal config "$([[ -e $clone/compose/torii/config.yaml ]] && echo present)" ""
  assert_equal override "$(find "$state" -type f 2>/dev/null)" ""
  assert_equal copies "$(find "$clone/compose/torii" -name 'config.yaml.*')" ""
}

test_render_refuses_a_host_with_no_tailnet_address_before_docker() {
  ready_host
  write_stub tailscale 'exit 1'
  run_hosting gateway render
  assert_equal status "$status" 1
  assert_contains stderr "$err" "gives this host no tailnet IPv4 address"
  assert_equal docker "$(docker_calls)" ""
}

test_validate_checks_the_rendered_config_and_changes_nothing() {
  ready_host
  rendered
  run_hosting gateway validate
  assert_equal status "$status" 0
  assert_contains docker "$(docker_calls)" \
    "docker run --rm --network none --volume $clone/compose/torii:/config:ro"
  assert_contains docker "$(docker_calls)" " -f /config/config.yaml --validate-only"
  assert_equal config "$(<"$clone/compose/torii/config.yaml")" "the rendered config"
  export HOSTING_TEST_INVALID=1
  run_hosting gateway validate
  assert_equal "invalid status" "$status" 1
  assert_equal "invalid stderr" "$err" "Error: invalid"
}

test_validate_refuses_without_a_rendered_config() {
  ready_host
  run_hosting gateway validate
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: $clone/compose/torii/config.yaml is missing;\
 hosting gateway render writes it"
  assert_equal docker "$(docker_calls)" ""
}

test_up_refuses_without_a_rendered_config() {
  ready_host
  run_hosting gateway up
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: $clone/compose/torii/config.yaml is missing;\
 hosting gateway render writes it"
  assert_equal calls "$(calls)" ""
  assert_equal secret "$(find "$clone" -name azure-foundry-key)" ""
}

test_up_writes_the_key_file_and_starts_the_stack_with_the_account() {
  ready_host
  rendered
  run_hosting gateway up
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal "key file" "$(<"$state/azure-foundry-key")" "$foundry_key"
  assert_equal "key mode" "$(stat -c %a "$state/azure-foundry-key")" 644
  assert_equal "state mode" "$(stat -c %a "$state")" 700
  assert_equal docker "$(docker_calls)" "$(compose_call up --detach --wait --build)"
  assert_contains env "$(<"$HOSTING_TEST_DOCKER/up-env")" "AZURE_FOUNDRY_ACCOUNT=$foundry_account"
  assert_contains env "$(<"$HOSTING_TEST_DOCKER/up-env")" "BUILDX_NO_DEFAULT_ATTESTATIONS=1"
  [[ $(calls) != *"$foundry_key"* ]] || fail "the key is on a command line"
  [[ $(<"$HOSTING_TEST_DOCKER/up-env") != *"$foundry_key"* ]] || fail "the key is in compose's environment"
  [[ $out$err != *"$foundry_key"* ]] || fail "up printed the key"
}

test_up_refuses_when_fnox_gives_no_key() {
  ready_host
  rendered
  write_stub fnox 'exit 1'
  run_hosting gateway up
  assert_equal status "$status" 1
  assert_contains stderr "$err" "hosting: fnox gives no AZURE_FOUNDRY_KEY from $clone/fnox.toml"
  assert_equal docker "$(docker_calls)" ""
  assert_equal secret "$([[ -e $state/azure-foundry-key ]] && echo present)" ""
}

test_down_keeps_the_volumes_and_reset_drops_them() {
  ready_host
  rendered
  run_hosting gateway down
  assert_equal "down status" "$status" 0
  run_hosting gateway reset
  assert_equal "reset status" "$status" 0
  assert_equal docker "$(docker_calls)" "$(compose_call down)
$(compose_call down --volumes)"
}

test_status_shows_a_running_stack() {
  ready_host
  stack 1 torii gateway-torii-1 running "Up 2 hours" \
    postgres gateway-postgres-1 running "Up 2 hours (healthy)"
  run_hosting gateway status
  assert_equal status "$status" 0
  assert_equal stdout "$out" "$(printf '%-16s %-30s %-10s %s\n' SERVICE CONTAINER STATE STATUS \
    torii gateway-torii-1 running "Up 2 hours" \
    postgres gateway-postgres-1 running "Up 2 hours (healthy)")"
}

test_status_flags_a_stranded_torii() {
  ready_host
  stack 0 torii gateway-torii-1 running "Up 2 hours"
  run_hosting gateway status
  assert_equal status "$status" 1
  assert_contains stdout "$out" "gateway-torii-1 is stranded: it is on no network, so\
 192.0.2.10:3000 is published nowhere; docker network connect bridge gateway-torii-1\
 reattaches it"
}

test_status_fails_on_a_stopped_service_or_no_stack() {
  ready_host
  stack 1 torii gateway-torii-1 running "Up 2 hours" \
    postgres gateway-postgres-1 exited "Exited (1) 2 minutes ago"
  run_hosting gateway status
  assert_equal "stopped status" "$status" 1
  rm "$HOSTING_TEST_DOCKER/ps" "$HOSTING_TEST_DOCKER/id"
  run_hosting gateway status
  assert_equal "empty status" "$status" 1
  assert_equal "empty stdout" "$out" "the gateway's stack has no container; hosting gateway up\
 starts it"
}

run_tests
