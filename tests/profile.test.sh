#!/usr/bin/env bash
# Tests for hosting profile validate (lib/profile.sh, lib/profile.jq) and the committed class
# profiles. tests/profiles/valid.toml validates clean, and each other tests/profiles/<name>.toml is
# a refusal fixture whose errors, each by key path, are exactly the lines of its <name>.err.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/hosting.sh
source "$repo/lib/hosting.sh"

fixtures=$repo/tests/profiles

# Prints what the jq expression given makes of the clone's profile of the class given.
profile_json() {
  hosting_yq -p toml -o json '.' "$clone/classes/$1/profile.toml" | jq -r "$2"
}

test_the_committed_profiles_validate() {
  run_hosting profile validate
  assert_equal status "$status" 0
  assert_equal stdout "$out" "classes/gb10/profile.toml: valid
classes/strix-halo/profile.toml: valid"
  assert_equal stderr "$err" ""
}

test_the_committed_profiles_are_in_yqs_output_format() {
  local class
  for class in gb10 strix-halo; do
    assert_equal "$class profile" "$(hosting_yq -p toml -o toml '.' "$repo/classes/$class/profile.toml")" \
      "$(<"$repo/classes/$class/profile.toml")"
  done
}

test_each_class_holds_its_standing_rows() {
  assert_equal "gb10 aliases" "$(profile_json gb10 '[.rows[].alias] | join(" ")')" "agent vision"
  assert_equal "strix-halo aliases" "$(profile_json strix-halo '[.rows[].alias] | join(" ")')" \
    "audio embedding"
}

test_the_vision_row_records_that_its_generation_config_is_the_cards() {
  local row='.rows[] | select(.alias == "vision")'
  assert_equal sampling "$(profile_json gb10 "$row | has(\"sampling\")")" false
  assert_equal "base model" "$(profile_json gb10 "$row | .provenance.base_model")" \
    google/gemma-4-26B-A4B-it
  assert_contains "generation config" "$(profile_json gb10 "$row | .provenance.generation_config")" \
    "temperature 1.0, top_k 64, top_p 0.95"
}

test_the_valid_fixture_validates() {
  run_hosting profile validate "$fixtures/valid.toml"
  assert_equal status "$status" 0
  assert_equal stdout "$out" "$fixtures/valid.toml: valid"
  assert_equal stderr "$err" ""
}

test_each_refusal_fixture_produces_exactly_its_errors() {
  local fixture name
  for fixture in "$fixtures"/*.toml; do
    name=$(basename "$fixture" .toml)
    [[ $name == valid ]] && continue
    if [[ ! -f $fixtures/$name.err ]]; then
      fail "$name: no $name.err beside the fixture"
      continue
    fi
    run_hosting profile validate "$fixture"
    assert_equal "$name status" "$status" 1
    assert_equal "$name stdout" "$out" ""
    assert_equal "$name stderr" "$err" "$(sed "s|^|hosting: $fixture: |" "$fixtures/$name.err")"
  done
}

test_every_file_given_is_validated_and_each_error_reported() {
  run_hosting profile validate "$fixtures/fraction-over-one.toml" "$fixtures/valid.toml" \
    "$fixtures/missing-cap-reason.toml"
  assert_equal status "$status" 1
  assert_equal stdout "$out" "$fixtures/valid.toml: valid"
  assert_equal stderr "$err" "hosting: $fixtures/fraction-over-one.toml: rows[0].fraction: 1.2 is over 1
hosting: $fixtures/missing-cap-reason.toml: rows[0].cap_reason: required"
}

test_an_invalid_class_profile_fails_the_validation_of_every_profile() {
  hosting_yq -p toml -o toml -i '.rows[0].fraction = 0' "$clone/classes/gb10/profile.toml"
  run_hosting profile validate
  assert_equal status "$status" 1
  assert_equal stdout "$out" "classes/strix-halo/profile.toml: valid"
  assert_equal stderr "$err" \
    "hosting: classes/gb10/profile.toml: rows[0].fraction: required, a number over 0"
}

test_a_file_that_is_not_toml_is_refused_by_name() {
  printf 'store = \n' >"$tmp/broken.toml"
  run_hosting profile validate "$tmp/broken.toml"
  assert_equal status "$status" 1
  assert_contains stderr "$err" "hosting: $tmp/broken.toml: "
}

test_a_class_without_its_profile_is_refused() {
  rm "$clone/classes/strix-halo/profile.toml"
  run_hosting profile validate
  assert_equal status "$status" 1
  assert_equal stdout "$out" "classes/gb10/profile.toml: valid"
  assert_equal stderr "$err" "hosting: classes/strix-halo/profile.toml: missing"
}

test_a_directory_for_no_class_is_refused() {
  mkdir "$clone/classes/gb20"
  run_hosting profile validate
  assert_equal status "$status" 1
  assert_equal stderr "$err" \
    "hosting: classes/gb20: not a host class; the classes are gb10 strix-halo"
}

test_a_class_directory_holds_only_its_profile_and_runbook() {
  touch "$clone/classes/gb10/runbook.md" "$clone/classes/gb10/notes.md" \
    "$clone/classes/gb10/.profile.toml.swp"
  run_hosting profile validate
  assert_equal status "$status" 1
  assert_equal stderr "$err" \
    "hosting: classes/gb10/notes.md: a class directory holds only profile.toml and runbook.md
hosting: classes/gb10/.profile.toml.swp: a class directory holds only profile.toml and runbook.md"
}

test_the_first_mikefarah_yq_on_path_is_used() {
  write_stub yq 'echo "yq 4.4.5"'
  run_hosting profile validate "$fixtures/valid.toml"
  assert_equal status "$status" 0
  assert_equal calls "$(calls)" "yq --version
yq --version"
}

test_a_path_without_mikefarahs_yq_is_refused() {
  local dir dirs path=$stubs
  write_stub yq 'echo "yq 4.4.5"'
  IFS=: read -ra dirs <<<"$base_path"
  for dir in "${dirs[@]}"; do
    if [[ -x $dir/yq ]] && "$dir/yq" --version 2>/dev/null | grep -q mikefarah/yq; then
      continue
    fi
    path+=:$dir
  done
  PATH=$path run_hosting profile validate "$fixtures/valid.toml"
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_contains stderr "$err" "no yq on PATH is mikefarah yq"
}

run_tests
