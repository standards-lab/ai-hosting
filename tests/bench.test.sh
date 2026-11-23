#!/usr/bin/env bash
# Tests for scripts/lint-bench.sh, the bench scenarios' lint, against the committed scenarios and
# profile and against the fixtures in tests/bench/: a 512-token context with a scenario within it
# and one over it.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

fixtures=$repo/tests/bench

run_lint() {
  run "$repo/scripts/lint-bench.sh" "$@"
}

test_the_committed_scenarios_fit_the_strix_halo_profile() {
  run_lint
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
}

test_510_tokens_and_two_special_tokens_fit_a_512_context() {
  run_lint "$fixtures/context-512.toml" "$fixtures/embedding-510.yaml"
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
}

test_511_tokens_and_two_special_tokens_exceed_a_512_context() {
  run_lint "$fixtures/context-512.toml" "$fixtures/embedding-510.yaml" \
    "$fixtures/embedding-511.yaml"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "FAIL: $fixtures/embedding-511.yaml: 511 input tokens plus 2 special tokens exceed the embedding row's context in $fixtures/context-512.toml, 512"
}

test_a_scenario_that_is_not_embedding_is_not_bounded() {
  run_lint "$fixtures/context-512.toml" "$fixtures/chat-over.yaml"
  assert_equal status "$status" 0
}

test_a_scenario_that_does_not_parse_fails() {
  run_lint "$fixtures/context-512.toml" "$fixtures/unparseable.yaml" \
    "$fixtures/embedding-510.yaml"
  assert_equal status "$status" 1
  assert_contains stderr "$err" "FAIL: $fixtures/unparseable.yaml does not parse"
}

test_a_profile_with_no_embedding_row_is_refused() {
  run_lint "$fixtures/no-embedding-row.toml" "$fixtures/embedding-510.yaml"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "FAIL: $fixtures/no-embedding-row.toml has no embedding row with a numeric context"
}

test_a_missing_scenario_is_refused_before_any_is_read() {
  run_lint "$fixtures/context-512.toml" "$fixtures/embedding-511.yaml" "$fixtures/absent.yaml"
  assert_equal status "$status" 2
  assert_equal stderr "$err" "FAIL: $fixtures/absent.yaml is not a file"
}

test_a_profile_without_scenarios_is_a_usage_error() {
  run_lint "$fixtures/context-512.toml"
  assert_equal status "$status" 2
  assert_contains stderr "$err" "usage: scripts/lint-bench.sh"
}

run_tests
