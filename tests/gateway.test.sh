#!/usr/bin/env bash
# Tests for agentgateway's config render (lib/gateway.sh, lib/gateway.jq): a copy of
# compose/agentgateway rendered against the fixture class profiles under tests/gateway/classes, a
# fixture key list, and the overflow switches, with a stub docker in place of the pinned image.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/hosting.sh
source "$repo/lib/hosting.sh"

fixture_classes=$repo/tests/gateway/classes
interactive_key=fixture-interactive-key
bulk_key=fixture-bulk-key

# Points the render at a copy of compose/agentgateway, with an empty key list, and the fixture class
# profiles.
use_fixtures() {
  cp -R "$repo/compose/agentgateway" "$tmp/agentgateway"
  rm -f "$tmp/agentgateway/config.yaml"
  grep '^#' "$repo/compose/agentgateway/keys.toml" >"$tmp/agentgateway/keys.toml"
  HOSTING_GATEWAY=$tmp/agentgateway
  HOSTING_GATEWAY_STATE=$tmp/state
  HOSTING_PROFILES=$fixture_classes
  HOSTING_ADDRESS=192.0.2.10
}

# Prints the SHA-256 hash of the key given, as lowercase hex.
hash_of() {
  printf %s "$1" | sha256sum | cut -d ' ' -f 1
}

# Writes the copy's key list: one interactive key for cerebro and one bulk key for batch.
write_keys() {
  cat >>"$HOSTING_GATEWAY/keys.toml" <<EOF

[[keys]]
consumer = "cerebro"
class = "interactive"
sha256 = "$(hash_of "$interactive_key")"

[[keys]]
consumer = "batch"
class = "bulk"
sha256 = "$(hash_of "$bulk_key")"
EOF
}

# Renders the copy, holding the config in out, the errors in err, and the status in status, and
# the config decoded to JSON in config.
render() {
  run hosting_gateway_render
  config=$(hosting_yq -o json '.' <<<"$out")
}

# Prints the field given of the route with the alias given, from the rendered config:
# route <alias> <jq path>.
route() {
  jq -r --arg alias "$1" ".routes[] | select(.name == \$alias) | $2" <<<"$config"
}

test_each_alias_routes_to_its_host_at_its_profile_port() {
  use_fixtures
  render
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal agent "$(route agent '.backends[0].ai.groups[0].providers[0].hostOverride')" gb10-1:9100
  assert_equal vision "$(route vision '.backends[0].ai.groups[0].providers[0].hostOverride')" \
    gb10-2:9101
  assert_equal audio "$(route audio '.backends[0].ai.groups[0].providers[0].hostOverride')" \
    framework:9102
  assert_equal embedding "$(route embedding '.backends[0].ai.groups[0].providers[0].hostOverride')" \
    framework-2:9103
}

test_each_alias_models_answer_lists_the_alias_with_its_row_model_as_root() {
  local alias model
  use_fixtures
  render
  for alias in agent vision audio embedding; do
    case $alias in
      agent) model=example/agent-model ;;
      vision) model=example/vision-model-NVFP4 ;;
      audio) model=example/audio-model ;;
      embedding) model=example/embedding-model ;;
    esac
    assert_equal "$alias models" "$(route "$alias" '.policies.directResponse.conditional[0]
      | select(.condition == "request.path == \"/v1/models\"") | .body | fromjson
      | [.data[] | "\(.id) \(.root)"] | join(",")')" "$alias $model"
  done
}

test_the_tokenize_route_follows_the_embedding_row_host_and_port() {
  use_fixtures
  render
  assert_equal status "$status" 0
  assert_equal host "$(route embedding-tokenize '[.backends[].host] | join(" ")')" framework-2:9103
}

test_each_key_carries_its_hash_consumer_and_class_and_no_budget() {
  use_fixtures
  write_keys
  render
  assert_equal status "$status" 0
  assert_equal keys "$(jq -r '.gateways.consumer.apiKey.keys[]
    | [.keyHash, .metadata.name, .metadata.class, has("budgets")] | join(" ")' <<<"$config")" \
    "sha256:$(hash_of "$interactive_key") cerebro interactive false
sha256:$(hash_of "$bulk_key") batch bulk false"
}

test_an_empty_key_list_renders_no_key() {
  use_fixtures
  render
  assert_equal status "$status" 0
  assert_equal keys "$(jq -c '.gateways.consumer.apiKey.keys' <<<"$config")" "[]"
}

test_a_switch_off_drops_only_its_alias_azure_group() {
  use_fixtures
  sed -i 's/^vision = true/vision = false/' "$HOSTING_GATEWAY/overflow.toml"
  render
  assert_equal status "$status" 0
  assert_equal agent "$(route agent '[.backends[0].ai.groups[].providers[].name] | join(" ")')" \
    "agent-row agent-azure"
  assert_equal vision "$(route vision '[.backends[0].ai.groups[].providers[].name] | join(" ")')" \
    "vision-row"
  assert_equal audio "$(route audio '[.backends[0].ai.groups[].providers[].name] | join(" ")')" \
    "audio-row audio-azure"
}

test_every_switch_on_keeps_each_azure_group_and_embedding_has_none() {
  use_fixtures
  render
  assert_equal groups "$(jq -r '.routes[] | select(.backends[0].ai) | "\(.name) \([.backends[0].ai.groups[].providers[].name]
    | join(","))"' <<<"$config")" "agent agent-row,agent-azure
vision vision-row,vision-azure
audio audio-row,audio-azure
embedding embedding-row"
}

test_each_azure_provider_drops_what_its_deployment_refuses_and_the_rows_keep_the_request() {
  use_fixtures
  render
  assert_equal status "$status" 0
  assert_equal transformations "$(jq -r '.routes[] | select(.backends[0].ai)
    | .backends[0].ai.groups[].providers[]
    | "\(.name) \(.policies.ai.transformations // {} | to_entries | map("\(.key)=\(.value)") | join(";"))"' \
    <<<"$config")" "agent-row priority=apiKey.class == \"bulk\" ? 10 : 0
agent-azure ignore_eos=fail(\"remove\")
vision-row priority=apiKey.class == \"bulk\" ? 10 : 0
vision-azure max_completion_tokens=has(llmRequest.max_completion_tokens) ? llmRequest.max_completion_tokens : llmRequest.max_tokens;max_tokens=fail(\"remove\");top_p=fail(\"remove\");top_k=fail(\"remove\");reasoning_effort=\"minimal\"
audio-row 
audio-azure stream_options=has(llmRequest.stream_options) ? {\"include_usage\": true} : fail(\"remove\")
embedding-row "
  assert_equal "azure policies" "$(jq -r '[.routes[].backends[0].ai.groups[]?.providers[]
    | select(.name | endswith("-azure")) | .policies
    | [.health.unhealthyExpression, .backendAuth.key.value.file,
      .responseHeaderModifier.set["x-gateway-overflow"], (.backendTLS | tostring)] | join(" ")]
    | unique | .[]' <<<"$config")" \
    "!has(response.code) || response.code == 503 || response.code == 429 /run/secrets/azure-foundry-key azure {}"
}

test_the_render_holds_no_secret() {
  use_fixtures
  write_keys
  AZURE_FOUNDRY_ACCOUNT=fixture-account run hosting_gateway_render
  assert_equal status "$status" 0
  [[ $out != *"$interactive_key"* && $out != *"$bulk_key"* ]] || fail "a key is in the render"
  [[ $out != *fixture-account* ]] || fail "the account's name is in the render"
  config=$(hosting_yq -o json '.' <<<"$out")
  # shellcheck disable=SC2016 # The config holds ${AZURE_FOUNDRY_ACCOUNT} unexpanded.
  assert_equal "azure hosts" "$(jq -r '[.routes[].backends[0].ai.groups[1].providers[0].hostOverride
    // empty] | unique | join(" ")' <<<"$config")" \
    '${AZURE_FOUNDRY_ACCOUNT}.services.ai.azure.com:443'
  assert_equal "azure key" "$(jq -c '[.routes[].backends[0].ai.groups[1].providers[0].policies
    .backendAuth.key.value // empty] | unique' <<<"$config")" \
    '[{"file":"/run/secrets/azure-foundry-key"}]'
}

test_the_key_list_is_validated_with_every_error_at_once() {
  use_fixtures
  cat >>"$HOSTING_GATEWAY/keys.toml" <<EOF
note = "x"

[[keys]]
consumer = "Cerebro"
class = "urgent"
sha256 = "abc"

[[keys]]
consumer = "pi"
class = "bulk"
sha256 = "$(hash_of "$bulk_key")"
key = "$bulk_key"

[[keys]]
consumer = "pi"
class = "interactive"
sha256 = "$(hash_of "$bulk_key")"
EOF
  render
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: compose/agentgateway/keys.toml: note: not a key the schema defines
hosting: compose/agentgateway/keys.toml: keys[0].consumer: required, lowercase letters, digits, and hyphens
hosting: compose/agentgateway/keys.toml: keys[0].class: required, one of interactive, bulk
hosting: compose/agentgateway/keys.toml: keys[0].sha256: required, 64 lowercase hex digits
hosting: compose/agentgateway/keys.toml: keys[1].key: not a key the schema defines
hosting: compose/agentgateway/keys.toml: keys: consumer pi is listed more than once
hosting: compose/agentgateway/keys.toml: keys: a hash is listed more than once"
}

test_the_switches_are_validated_with_every_error_at_once() {
  use_fixtures
  cat >"$HOSTING_GATEWAY/overflow.toml" <<EOF
agent = "yes"
vision = true
embedding = true
EOF
  render
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: compose/agentgateway/overflow.toml: embedding: no alias with an Azure group; the switches are agent, vision, audio
hosting: compose/agentgateway/overflow.toml: agent: true or false
hosting: compose/agentgateway/overflow.toml: audio: required, true or false"
}

test_a_route_whose_alias_no_profile_has_is_refused() {
  use_fixtures
  mkdir -p "$tmp/classes/gb10" "$tmp/classes/strix-halo"
  cp "$fixture_classes/gb10/profile.toml" "$tmp/classes/gb10/"
  hosting_yq -p toml -o toml 'del(.rows[0])' "$fixture_classes/strix-halo/profile.toml" \
    >"$tmp/classes/strix-halo/profile.toml"
  HOSTING_PROFILES=$tmp/classes
  render
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: classes: audio: no class profile has a row with this alias"
}

test_an_invalid_class_profile_is_refused() {
  use_fixtures
  mkdir -p "$tmp/classes/gb10" "$tmp/classes/strix-halo"
  cp "$fixture_classes/gb10/profile.toml" "$tmp/classes/gb10/"
  cp "$repo/tests/profiles/fraction-over-one.toml" "$tmp/classes/strix-halo/profile.toml"
  HOSTING_PROFILES=$tmp/classes
  render
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: classes/strix-halo/profile.toml: rows[0].fraction: 1.2 is over 1"
}

test_a_config_that_validates_is_renamed_into_place_readable_by_the_image_user() {
  use_fixtures
  write_keys
  write_stub docker
  write_stub tailscale 'echo 192.0.2.20'
  run hosting_gateway_render_in_place
  assert_equal status "$status" 0
  assert_equal config "$(<"$HOSTING_GATEWAY/config.yaml")" "$(hosting_gateway_render)"
  assert_equal mode "$(stat -c %a "$HOSTING_GATEWAY/config.yaml")" 644
  assert_equal copies "$(find "$HOSTING_GATEWAY" -name 'config.yaml.*')" ""
  assert_contains docker "$(calls)" "docker run --rm --network none --volume $HOSTING_GATEWAY:/config:ro"
  assert_contains docker "$(calls)" ":/run/secrets/azure-foundry-key:ro --env AZURE_FOUNDRY_ACCOUNT=validate cr.agentgateway.dev/agentgateway:v"
  assert_contains docker "$(calls)" " -f /config/config.yaml."
  assert_contains docker "$(calls)" " --validate-only"
}

test_a_config_that_fails_validation_leaves_the_config_in_place() {
  use_fixtures
  echo "the config in place" >"$HOSTING_GATEWAY/config.yaml"
  write_stub docker 'echo "Error: invalid" >&2; exit 1'
  run hosting_gateway_render_in_place
  assert_equal status "$status" 1
  assert_equal stderr "$err" "Error: invalid"
  assert_equal config "$(<"$HOSTING_GATEWAY/config.yaml")" "the config in place"
  assert_equal copies "$(find "$HOSTING_GATEWAY" -name 'config.yaml.*')" ""
}

test_a_render_refusal_never_reaches_validation() {
  use_fixtures
  echo 'agent = 1' >"$HOSTING_GATEWAY/overflow.toml"
  write_stub docker
  run hosting_gateway_render_in_place
  assert_equal status "$status" 1
  assert_equal docker "$(calls)" ""
  assert_equal config "$([[ -e $HOSTING_GATEWAY/config.yaml ]] && echo present)" ""
  assert_equal copies "$(find "$HOSTING_GATEWAY" -name 'config.yaml.*')" ""
}

run_tests
