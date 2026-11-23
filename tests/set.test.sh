#!/usr/bin/env bash
# Tests for hosting profile set (hosting_profile_set in lib/profile.sh), on the clone's copy of each
# class profile: a valid edit changes only its field's line and keeps yq's output format, and an
# edit that fails validation, or names an unknown alias or field, leaves the profile byte-identical.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/hosting.sh
source "$repo/lib/hosting.sh"

set_field() {
  HOSTING_CLASS=gb10 run_hosting profile set "$@"
}

changed_lines() {
  diff "$repo/classes/gb10/profile.toml" "$clone/classes/gb10/profile.toml" | grep '^[<>]'
}

assert_unchanged() {
  cmp -s "$repo/classes/gb10/profile.toml" "$clone/classes/gb10/profile.toml" || fail "the profile changed: $(changed_lines)"
}

assert_in_yqs_format() {
  assert_equal format "$(hosting_yq -p toml -o toml '.' "$clone/classes/gb10/profile.toml")" "$(<"$clone/classes/gb10/profile.toml")"
}

test_a_number_field_changes_only_its_line() {
  set_field vision fraction=0.45
  assert_equal status "$status" 0
  assert_equal stdout "$out" "classes/gb10/profile.toml: set vision's fraction"
  assert_equal stderr "$err" ""
  assert_equal changed "$(changed_lines)" "< fraction = 0.40
> fraction = 0.45"
  assert_in_yqs_format
}

test_a_text_field_in_a_table_changes_only_its_line() {
  set_field agent "load.target=6 sessions"
  assert_equal status "$status" 0
  assert_equal changed "$(changed_lines)" '< target = "4 sessions"
> target = "6 sessions"'
  assert_in_yqs_format
}

test_flags_are_set_as_words() {
  set_field vision "flags=--scheduling-policy priority --kv-cache-dtype bfloat16"
  assert_equal status "$status" 0
  assert_equal flags "$(hosting_yq -p toml -o json '.rows[1].flags' "$clone/classes/gb10/profile.toml" | jq -c .)" \
    '["--scheduling-policy","priority","--kv-cache-dtype","bfloat16"]'
  assert_equal "changed lines" "$(changed_lines | wc -l)" 2
  assert_in_yqs_format
}

test_an_edit_that_fails_validation_writes_nothing() {
  set_field agent cap=10
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" \
    "hosting: classes/gb10/profile.toml: rows[0].queue_limit: 24 is not twice the cap, 10"
  assert_unchanged
}

test_a_number_field_given_text_writes_nothing() {
  set_field agent port=eight
  assert_equal status "$status" 1
  assert_equal stderr "$err" \
    "hosting: classes/gb10/profile.toml: rows[0].port: required, a port from 1 to 65535"
  assert_unchanged
}

test_an_unknown_alias_is_refused() {
  set_field audio cap=8
  assert_equal status "$status" 1
  assert_equal stderr "$err" \
    "hosting: classes/gb10/profile.toml has no row audio; its aliases are agent vision"
  assert_unchanged
}

test_an_unknown_field_is_refused() {
  local field
  for field in kv_cache load source.country rows; do
    set_field agent "$field=1"
    assert_equal "$field status" "$status" 1
    assert_equal "$field stderr" "$err" \
      "hosting: $field is no field of a row; see classes/README.md for a row's keys"
  done
  assert_unchanged
}

test_an_invalid_profile_is_refused_before_the_edit() {
  hosting_yq -p toml -o toml -i '.rows[0].fraction = 1.5' "$clone/classes/gb10/profile.toml"
  cp "$clone/classes/gb10/profile.toml" "$tmp/before.toml"
  set_field vision fraction=0.45
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: classes/gb10/profile.toml: rows[0].fraction: 1.5 is over 1"
  cmp -s "$tmp/before.toml" "$clone/classes/gb10/profile.toml" || fail "the invalid profile changed"
}

test_set_takes_an_alias_and_one_assignment() {
  local args
  for args in "" "agent" "agent cap" "agent cap=8 fraction=0.5"; do
    # shellcheck disable=SC2086 # Each case's words are the arguments.
    set_field $args
    assert_equal "[$args] status" "$status" 2
    assert_equal "[$args] stderr" "$err" "hosting: profile set takes an alias and one <field>=<value>
usage: hosting profile set <alias> <field>=<value>"
  done
  assert_unchanged
}

run_tests
