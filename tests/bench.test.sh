#!/usr/bin/env bash
# Tests for scripts/lint-bench.sh, the bench scenarios' lint, against the committed scenarios and
# profile and against the fixtures in tests/bench/: a 512-token context with a scenario within it
# and one over it, a stream sweep and a rate sweep among them. Tests too that each committed audio
# scenario lists one prompt per clip row, and for bench/levels.jq's level names and vision's
# figures and floor against the result fixtures there: a rate sweep's, a stream sweep's, and a
# vision stream sweep's.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/profile.sh
source "$repo/lib/profile.sh"

fixtures=$repo/tests/bench
librispeech_dummy_clips=73

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

test_each_audio_scenario_lists_one_prompt_per_clip_row() {
  local scenario counts
  for scenario in "$repo"/bench/audio*.yaml; do
    counts=$(hosting_yq -o json '.' "$scenario" | jq -c --argjson clips "$librispeech_dummy_clips" \
      '[(.spec.data[0].data.prompt | length), $clips * (.spec.data[1].load_kwargs.split | split("+") | length)]')
    assert_equal "${scenario##*/} prompts and clip rows" "$(jq '.[0]' <<<"$counts")" \
      "$(jq '.[1]' <<<"$counts")"
  done
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
  assert_equal levels "$(cut -d '|' -f 1-3,15 <<<"$out")" "## sweep-result.json
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

test_levels_judges_each_vision_level_by_its_latency_median() {
  run jq -r --arg purpose vision -f "$repo/bench/levels.jq" "$fixtures/vision-result.json"
  assert_equal status "$status" 0
  assert_equal levels "$(cut -d '|' -f 1,2,4-9,15 <<<"$out")" "## vision-result.json
level | ok/err/inc | TTFT med ms | ITL med ms | lat med s | lat p90 s | lat min s | lat<=10s | floor
4 | 3/0/4 | 812 | 31.26 | 4.00 | 4.80 | 3.00 | 3/3 | meets
8 | 3/1/8 | 2400 | 70.00 | 9.50 | 11.50 | 8.00 | 2/3 | meets
16 | 2/0/16 | 6100 | 95.50 | 11.00 | 12.60 | 9.00 | 1/2 | MISSES"
}

test_levels_refuses_an_unknown_purpose() {
  run jq -r --arg purpose agent -f "$repo/bench/levels.jq" "$fixtures/vision-result.json"
  assert_equal status "$status" 5
  assert_contains stderr "$err" "purpose must be vision, audio or embed"
}

run_tests
