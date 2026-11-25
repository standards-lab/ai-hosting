#!/usr/bin/env bash
# Tests for hosting profile stale (hosting_profile_stale and hosting_release_older in
# lib/profile.sh), on the clone's copy of each class profile and of lib/vllm.env, each test setting
# the pin and the rows' measured releases it reads: it lists the rows
# measured on a release older than the pin, compares releases number by number, exits 0 whether it
# lists any or none, and refuses bad arguments and an invalid profile before listing anything.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/hosting.sh
source "$repo/lib/hosting.sh"

set_measured() {
  hosting_yq -p toml -o toml -i "(.rows[] | select(.alias == \"$2\")).measured_vllm = \"$3\"" \
    "$clone/classes/$1/profile.toml"
}

set_pin() {
  sed -i "s/^VLLM_RELEASE=.*/VLLM_RELEASE=$1/" "$clone/lib/vllm.env"
}

measure_every_row_on() {
  local class
  for class in gb10 strix-halo; do
    hosting_yq -p toml -o toml -i ".rows[].measured_vllm = \"$1\"" \
      "$clone/classes/$class/profile.toml"
  done
}

measure_gb10_one_release_behind() {
  set_pin v0.34.0
  measure_every_row_on v0.34.0
  set_measured gb10 agent v0.33.0
  set_measured gb10 vision v0.33.0
}

test_the_rows_measured_before_the_pin_are_listed() {
  measure_gb10_one_release_behind
  run_hosting profile stale
  assert_equal status "$status" 0
  assert_equal stdout "$out" "gb10 agent: measured on v0.33.0, the pin is v0.34.0
gb10 vision: measured on v0.33.0, the pin is v0.34.0"
  assert_equal stderr "$err" ""
}

test_a_class_given_lists_only_its_rows() {
  measure_gb10_one_release_behind
  run_hosting profile stale strix-halo
  assert_equal status "$status" 0
  assert_equal stdout "$out" ""
  run_hosting profile stale gb10
  assert_equal status "$status" 0
  assert_equal stdout "$out" "gb10 agent: measured on v0.33.0, the pin is v0.34.0
gb10 vision: measured on v0.33.0, the pin is v0.34.0"
}

test_every_row_current_lists_none_and_exits_0() {
  set_pin v0.34.0
  measure_every_row_on v0.34.0
  run_hosting profile stale
  assert_equal status "$status" 0
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" ""
}

test_a_row_measured_after_the_pin_is_not_listed() {
  set_pin v0.34.0
  measure_every_row_on v0.35.0
  run_hosting profile stale
  assert_equal status "$status" 0
  assert_equal stdout "$out" ""
}

test_releases_compare_by_number_not_by_text() {
  set_pin v0.10.0
  measure_every_row_on v0.10.0
  set_measured gb10 agent v0.9.0
  set_measured strix-halo audio v0.9.12
  set_measured strix-halo embedding v0.33.0
  run_hosting profile stale
  assert_equal status "$status" 0
  assert_equal stdout "$out" "gb10 agent: measured on v0.9.0, the pin is v0.10.0
strix-halo audio: measured on v0.9.12, the pin is v0.10.0"
}

test_release_older_compares_each_number() {
  local older newer
  while read -r older newer; do
    hosting_release_older "$older" "$newer" || fail "$older is not older than $newer"
    ! hosting_release_older "$newer" "$older" || fail "$newer is older than $older"
  done <<'EOF'
v0.9.0 v0.10.0
v0.33.0 v0.34.0
v0.34.0 v0.34.1
v0.34.9 v0.35.0
v0.99.99 v1.0.0
v0.08.0 v0.10.0
EOF
  ! hosting_release_older v0.34.0 v0.34.0 || fail "v0.34.0 is older than itself"
}

test_an_unknown_class_is_refused() {
  run_hosting profile stale gb20
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: gb20 is none of gb10 strix-halo
usage: hosting profile stale [<class>]"
}

test_a_class_list_in_one_argument_is_refused() {
  run_hosting profile stale "gb10 strix-halo"
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_contains stderr "$err" "is none of gb10 strix-halo"
}

test_more_than_one_argument_is_refused() {
  run_hosting profile stale gb10 strix-halo
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: profile stale takes at most one class
usage: hosting profile stale [<class>]"
}

test_an_invalid_profile_is_refused_before_anything_is_listed() {
  set_measured strix-halo audio 0.34
  run_hosting profile stale
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: classes/strix-halo/profile.toml: rows[0].measured_vllm: required, a vLLM release such as v0.33.0"
}

test_the_host_class_is_not_probed() {
  measure_gb10_one_release_behind
  HOSTING_CLASS=gb20 run_hosting profile stale
  assert_equal status "$status" 0
  assert_equal stdout "$out" "gb10 agent: measured on v0.33.0, the pin is v0.34.0
gb10 vision: measured on v0.33.0, the pin is v0.34.0"
}

run_tests
