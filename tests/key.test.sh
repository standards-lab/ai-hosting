#!/usr/bin/env bash
# Tests for the hosting key group (bin/hosting-key-*, lib/key.sh), run on a copy of the clone's
# compose project and a temporary consumer repository, with fnox stubbed to log its arguments and
# keep what it reads on stdin: issue writes the hash of the key fnox received, with its class, and
# the key reaches no fnox argument, output, or file but fnox's stdin; each refusal comes before any
# effect; rotate replaces the hash; revoke deletes exactly its consumer's entry; list names the
# consumers; and the render carries an issued key's hash.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/hosting.sh
source "$repo/lib/hosting.sh"

# Readies a copy of the compose project with an empty key list and a consumer repository, consumer,
# an age provider and no AI_GATEWAY_TOKEN, with fnox stubbed to keep its stdin in fnox-stdin.
ready() {
  cp -R "$repo/compose.yml" "$repo/compose" "$clone/"
  keys=$clone/compose/torii/keys.toml
  grep '^#' "$repo/compose/torii/keys.toml" >"$keys"
  consumer=$tmp/consumer
  mkdir -p "$consumer"
  cat >"$consumer/fnox.toml" <<'EOF'
root = true

[providers.age]
type = "age"

[providers.age.recipients]
laptop = "age1e264848005cx7h3cpzhlqcy0w5xq45gcmq7schraf7f53u5rlfqsjgpx0g"
EOF
  write_stub fnox "cat >$(printf %q "$tmp/fnox-stdin")"
}

# Prints the key the fnox stub last received on stdin.
received() {
  cat "$tmp/fnox-stdin"
}

# Prints the SHA-256 hash of the key given, as lowercase hex.
hash_of() {
  printf %s "$1" | sha256sum | cut -d ' ' -f 1
}

# Prints the key list's entries as "consumer class sha256" lines.
entries() {
  hosting_yq -p toml -o json '.' "$keys" |
    jq -r '(.keys // [])[] | "\(.consumer) \(.class) \(.sha256)"'
}

# Fails unless the command just run refused, exiting nonzero with the message given on stderr,
# with no fnox call and the key list as the copy at the path given holds it:
# assert_refused <message> <key list copy>.
assert_refused() {
  [[ $status != 0 ]] || fail "status: got 0, want nonzero"
  assert_contains stderr "$err" "$1"
  assert_equal calls "$(calls)" ""
  cmp -s "$keys" "$2" || fail "the key list changed"
}

test_issue_writes_the_hash_of_the_key_fnox_received_and_its_class() {
  local key
  ready
  run_hosting key issue mikoshi interactive "$consumer"
  assert_equal status "$status" 0
  assert_contains stdout "$out" "issued mikoshi its interactive key"
  key=$(received)
  [[ $key =~ ^[0-9a-f]{64}$ ]] || fail "the key is not 64 lowercase hex digits"
  assert_equal entries "$(entries)" "mikoshi interactive $(hash_of "$key")"
  assert_contains "fnox call" "$(calls)" \
    "fnox -c $consumer/fnox.toml set --provider age --description The ai-hosting model gateway's"
  assert_contains "fnox call" "$(calls)" " AI_GATEWAY_TOKEN"
  assert_contains "key list header" "$(head -n 1 "$keys")" "# The gateway's consumer keys"
}

test_issue_keeps_the_key_off_fnox_arguments_the_output_and_every_file() {
  local key file
  ready
  run_hosting key issue mikoshi bulk "$consumer"
  assert_equal status "$status" 0
  key=$(received)
  if [[ -z $key ]]; then
    fail "fnox received no key"
    return
  fi
  [[ $(calls) != *"$key"* ]] || fail "the key is in a fnox call's arguments"
  [[ $out != *"$key"* ]] || fail "the key is in stdout"
  [[ $err != *"$key"* ]] || fail "the key is in stderr"
  while IFS= read -r file; do
    [[ $file == "$tmp/fnox-stdin" ]] || fail "the key is in $file"
  done < <(grep -rlF -- "$key" "$tmp")
}

test_issue_gives_no_description_when_the_variable_has_one() {
  ready
  echo '[secrets]' >>"$consumer/fnox.toml"
  echo 'AI_GATEWAY_TOKEN = { provider = "age", value = "x", description = "Its own." }' \
    >>"$consumer/fnox.toml"
  run_hosting key issue mikoshi interactive "$consumer"
  assert_equal status "$status" 0
  assert_equal "fnox call" "$(calls)" \
    "fnox -c $consumer/fnox.toml set --provider age AI_GATEWAY_TOKEN"
}

test_issue_refuses_a_bad_consumer_name_before_any_effect() {
  ready
  cp "$keys" "$tmp/keys.before"
  run_hosting key issue Mikoshi interactive "$consumer"
  assert_refused "consumer 'Mikoshi' is not lowercase letters" "$tmp/keys.before"
}

test_issue_refuses_an_unknown_class_before_any_effect() {
  ready
  cp "$keys" "$tmp/keys.before"
  run_hosting key issue mikoshi urgent "$consumer"
  assert_refused "class 'urgent' is none of interactive bulk" "$tmp/keys.before"
}

test_issue_refuses_a_repository_with_no_fnox_file_before_any_effect() {
  ready
  rm "$consumer/fnox.toml"
  cp "$keys" "$tmp/keys.before"
  run_hosting key issue mikoshi interactive "$consumer"
  assert_refused "$consumer/fnox.toml is missing" "$tmp/keys.before"
}

test_issue_refuses_a_fnox_file_with_no_age_provider_before_any_effect() {
  ready
  echo 'root = true' >"$consumer/fnox.toml"
  cp "$keys" "$tmp/keys.before"
  run_hosting key issue mikoshi interactive "$consumer"
  assert_refused "is no fnox config with exactly one age provider" "$tmp/keys.before"
}

test_issue_refuses_an_invalid_key_list_before_any_effect() {
  ready
  printf '\n[[keys]]\nconsumer = "batch"\nclass = "bulk"\nsha256 = "short"\n' >>"$keys"
  cp "$keys" "$tmp/keys.before"
  run_hosting key issue mikoshi interactive "$consumer"
  assert_refused "keys.toml: keys[0].sha256" "$tmp/keys.before"
}

test_issue_refuses_a_consumer_already_holding_a_key_without_rotate() {
  ready
  run_hosting key issue mikoshi interactive "$consumer"
  rm -f "$tmp/calls"
  cp "$keys" "$tmp/keys.before"
  run_hosting key issue mikoshi interactive "$consumer"
  assert_refused "mikoshi already holds a key; --rotate replaces it" "$tmp/keys.before"
}

test_rotate_refuses_a_consumer_holding_no_key() {
  ready
  cp "$keys" "$tmp/keys.before"
  run_hosting key issue mikoshi interactive "$consumer" --rotate
  assert_refused "mikoshi holds no key to rotate" "$tmp/keys.before"
}

test_rotate_replaces_the_hash() {
  local first second
  ready
  run_hosting key issue mikoshi interactive "$consumer"
  first=$(received)
  run_hosting key issue mikoshi bulk "$consumer" --rotate
  assert_equal status "$status" 0
  second=$(received)
  [[ $first != "$second" ]] || fail "the rotated key is the first one"
  assert_equal entries "$(entries)" "mikoshi bulk $(hash_of "$second")"
}

test_revoke_removes_exactly_that_entry() {
  local athena
  ready
  run_hosting key issue mikoshi interactive "$consumer"
  run_hosting key issue athena bulk "$consumer"
  athena=$(hash_of "$(received)")
  run_hosting key issue pi interactive "$consumer"
  run_hosting key revoke mikoshi
  assert_equal status "$status" 0
  assert_equal entries "$(entries | cut -d ' ' -f 1,2)" $'athena bulk\npi interactive'
  assert_contains "athena's hash" "$(entries)" "athena bulk $athena"
  assert_contains "key list header" "$(head -n 1 "$keys")" "# The gateway's consumer keys"
}

test_revoke_refuses_a_consumer_holding_no_key() {
  ready
  cp "$keys" "$tmp/keys.before"
  run_hosting key revoke mikoshi
  assert_refused "mikoshi holds no key" "$tmp/keys.before"
}

test_revoking_the_last_key_leaves_the_header_alone() {
  ready
  cp "$keys" "$tmp/keys.before"
  run_hosting key issue mikoshi interactive "$consumer"
  run_hosting key revoke mikoshi
  assert_equal status "$status" 0
  cmp -s "$keys" "$tmp/keys.before" || fail "the key list is not as it was before the issue"
}

test_list_names_each_consumer_with_its_class() {
  ready
  run_hosting key list
  assert_equal status "$status" 0
  assert_equal "empty list" "$out" "no consumer holds a key; hosting key issue issues one"
  run_hosting key issue mikoshi interactive "$consumer"
  run_hosting key issue batch bulk "$consumer"
  run_hosting key list
  assert_equal status "$status" 0
  assert_equal list "$out" "$(printf '%-24s %s\n' CONSUMER CLASS mikoshi interactive batch bulk)"
}

test_usage_errors() {
  ready
  run_hosting key issue mikoshi interactive
  assert_equal status "$status" 2
  assert_contains stderr "$err" "usage: hosting key issue <consumer> <class> <repository> [--rotate]"
  run_hosting key issue mikoshi interactive "$consumer" --force
  assert_equal status "$status" 2
  run_hosting key revoke
  assert_equal status "$status" 2
  run_hosting key list mikoshi
  assert_equal status "$status" 2
  assert_equal calls "$(calls)" ""
}

test_the_render_carries_an_issued_key_hash() {
  local key config
  ready
  run_hosting key issue mikoshi interactive "$consumer"
  key=$(received)
  local HOSTING_GATEWAY=$clone/compose/torii
  local HOSTING_PROFILES=$repo/tests/gateway/classes
  run hosting_gateway_render
  assert_equal status "$status" 0
  config=$(hosting_yq -o json '.' <<<"$out")
  assert_equal keys "$(jq -r '.gateways.consumer.apiKey.keys[]
    | "\(.metadata.name) \(.metadata.class) \(.keyHash)"' <<<"$config")" \
    "mikoshi interactive sha256:$(hash_of "$key")"
}

run_tests
