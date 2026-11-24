#!/usr/bin/env bash
# Tests for scripts/lint-bench.sh, the bench scenarios' lint, against the committed scenarios and
# profile and against the fixtures in tests/bench/: a 512-token context with a scenario within it
# and one over it, a stream sweep and a rate sweep among them. Tests too for bench/levels.jq's level
# names against the result fixtures there: a rate sweep's and a stream sweep's.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/profile.sh
source "$repo/lib/profile.sh"

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

test_the_committed_scenarios_include_the_8_stream_audio_and_the_rate_sweep() {
  local audio sweep
  audio=$(hosting_yq -o json '.' "$repo/bench/audio-8.yaml" | jq -c '[.spec.profile,
    (.spec.data[0].data.prompt | length),
    (.spec.data[1].load_kwargs.split | split("+") | length)]')
  assert_equal "audio-8 profile and rows" "$audio" '[{"kind":"concurrent","streams":8},1752,24]'
  sweep=$(hosting_yq -o json '.' "$repo/bench/embedding-rate-sweep.yaml" | jq -c '[.spec.profile,
    .spec.backend.request_format, .spec.data[0].prompt_tokens]')
  assert_equal "rate sweep profile and input" "$sweep" \
    '[{"kind":"sweep","sweep_size":16},"/v1/embeddings",510]'
}

test_a_rate_sweep_over_the_context_fails() {
  run_lint "$fixtures/context-512.toml" "$fixtures/rate-sweep-511.yaml"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "FAIL: $fixtures/rate-sweep-511.yaml: 511 input tokens plus 2 special tokens exceed the embedding row's context in $fixtures/context-512.toml, 512"
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

run_levels() {
  run jq -r --arg purpose embed -f "$repo/bench/levels.jq" "$@"
}

test_levels_names_a_rate_sweeps_synchronous_throughput_and_constant_levels() {
  run_levels "$fixtures/sweep-result.json"
  assert_equal status "$status" 0
  assert_equal levels "$(cut -d '|' -f 1-3,13 <<<"$out")" "## sweep-result.json
level | ok/err/inc | req/s | floor
synchronous | 2/0/1 | 9.250 | meets
throughput | 2/1/0 | 70.500 | meets
rate 13.66 | 1/0/0 | 13.600 | MISSES"
}

test_levels_names_a_stream_sweeps_level_by_its_streams() {
  run_levels "$fixtures/streams-result.json"
  assert_equal status "$status" 0
  assert_equal levels "$(sed -n 3p <<<"$out" | cut -d '|' -f 1)" "16 "
}

run_tests
