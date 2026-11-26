#!/usr/bin/env bash
# Tests for scripts/lint-bench.sh, the bench scenarios' lint, against the committed scenarios and
# profiles and against the fixtures in tests/bench/: a 512-token embedding context and a 1,024-token
# agent context, each with a scenario within it and one over it, a stream sweep and a rate sweep
# among them, and bench/agent-sessions.yaml's 4-turn session against agent contexts of its own
# length and one token less. Tests too that each committed audio
# scenario reading LibriSpeech from Hugging Face lists one prompt per clip row, for
# bench/audio-windows.jq's windows against toy clips and the LibriSpeech dummy set's clip lengths,
# and for bench/levels.jq's level names and the agent and vision figures and floors against the
# result fixtures there: a rate sweep's, a stream sweep's, an agent stream sweep's, and a vision
# stream sweep's.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/profile.sh
source "$repo/lib/profile.sh"

fixtures=$repo/tests/bench
librispeech_dummy_clips=73

run_lint() {
  run "$repo/scripts/lint-bench.sh" "$@"
}

test_the_committed_scenarios_fit_the_strix_halo_and_gb10_profiles() {
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
    [[ $(hosting_yq '.spec.data[1].kind' "$scenario") == huggingface ]] || continue
    counts=$(hosting_yq -o json '.' "$scenario" | jq -c --argjson clips "$librispeech_dummy_clips" \
      '[(.spec.data[0].data.prompt | length), $clips * (.spec.data[1].load_kwargs.split | split("+") | length)]')
    assert_equal "${scenario##*/} prompts and clip rows" "$(jq '.[0]' <<<"$counts")" \
      "$(jq '.[1]' <<<"$counts")"
  done
}

run_windows() {
  run jq -c --argjson rate "$1" --argjson lo "$2" --argjson hi "$3" \
    -f "$repo/bench/audio-windows.jq" "$4"
}

test_windows_join_consecutive_clips_and_drop_a_clip_that_overshoots() {
  echo '[100, 200, 150, 400, 50, 300, 290, 100]' >"$tmp/clips.json"
  run_windows 1 280 300 "$tmp/clips.json"
  assert_equal status "$status" 0
  assert_equal windows "$out" "[[0,1],[5],[6]]"
}

test_windows_scale_their_bounds_by_the_sample_rate() {
  echo '[16000, 16000, 16000]' >"$tmp/clips.json"
  run_windows 16000 2 2 "$tmp/clips.json"
  assert_equal windows "$out" "[[0,1]]"
}

test_no_clips_make_no_windows() {
  echo '[]' >"$tmp/clips.json"
  run_windows 16000 28 30 "$tmp/clips.json"
  assert_equal status "$status" 0
  assert_equal windows "$out" "[]"
}

test_the_dummy_sets_30_s_windows_each_last_28_to_30_s() {
  run_windows 16000 28 30 "$fixtures/librispeech-dummy-samples.json"
  assert_equal status "$status" 0
  assert_equal "window count" "$(jq length <<<"$out")" 11
  assert_equal "windows outside 28 to 30 s" "$(jq --slurpfile s \
    "$fixtures/librispeech-dummy-samples.json" \
    '[.[] | [.[] as $i | $s[0][$i]] | add / 16000 | select(. < 28 or . > 30)] | length' <<<"$out")" 0
}

test_the_dummy_set_holds_a_probe_clip_of_about_each_length() {
  local seconds
  for seconds in 10 30 60 120; do
    run_windows 16000 "$(jq -n "$seconds * 14 / 15")" "$seconds" \
      "$fixtures/librispeech-dummy-samples.json"
    assert_equal "windows of about $seconds s" "$(jq 'length > 0' <<<"$out")" true
  done
}

test_an_agent_session_of_the_agent_rows_context_fits() {
  run_lint "$fixtures/context-512.toml" "$fixtures/agent-session-1024.yaml"
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
}

test_an_agent_session_over_the_agent_rows_context_fails() {
  run_lint "$fixtures/context-512.toml" "$fixtures/agent-session-1024.yaml" \
    "$fixtures/agent-session-1025.yaml"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "FAIL: $fixtures/agent-session-1025.yaml: a session of 1025 tokens exceeds the agent row's context in $fixtures/context-512.toml, 1024"
}

test_the_session_scenario_fits_an_agent_context_of_its_11776_tokens() {
  printf '[[rows]]\nalias = "agent"\ncontext = 11776\n' >"$tmp/agent.toml"
  run_lint "$tmp/agent.toml" "$repo/bench/agent-sessions.yaml"
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
}

test_the_session_scenario_over_an_agent_context_of_11775_fails() {
  printf '[[rows]]\nalias = "agent"\ncontext = 11775\n' >"$tmp/agent.toml"
  run_lint "$tmp/agent.toml" "$repo/bench/agent-sessions.yaml"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "FAIL: $repo/bench/agent-sessions.yaml: a session of 11776 tokens exceeds the agent row's context in $tmp/agent.toml, 11775"
}

test_an_agent_scenario_against_a_profile_with_no_agent_row_fails() {
  run_lint "$fixtures/no-embedding-row.toml" "$fixtures/agent-session-1024.yaml" \
    "$fixtures/agent-session-1025.yaml"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "FAIL: $fixtures/no-embedding-row.toml has no agent row with a numeric context"
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
  run_lint "$fixtures/no-embedding-row.toml" "$fixtures/embedding-510.yaml" \
    "$fixtures/embedding-511.yaml"
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
  assert_equal levels "$(cut -d '|' -f 1-3,18 <<<"$out")" "## sweep-result.json
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
  assert_equal levels "$(cut -d '|' -f 1,2,5-10,18 <<<"$out")" "## vision-result.json
level | ok/err/inc | TTFT med ms | ITL med ms | lat med s | lat p90 s | lat min s | lat<=10s | floor
4 | 3/0/4 | 812 | 31.26 | 4.00 | 4.80 | 3.00 | 3/3 | meets
8 | 3/1/8 | 2400 | 70.00 | 9.50 | 11.50 | 8.00 | 2/3 | meets
16 | 2/0/16 | 6100 | 95.50 | 11.00 | 12.60 | 9.00 | 1/2 | MISSES"
}

test_levels_gives_a_vision_levels_images_a_minute_from_its_second_half_and_no_other_purposes() {
  run jq -r --arg purpose vision -f "$repo/bench/levels.jq" "$fixtures/vision-result.json"
  assert_equal status "$status" 0
  assert_equal "vision" "$(cut -d '|' -f 1,4,11 <<<"$out")" "## vision-result.json
level | 2nd half req/s | img/min 
4 | 0.067 | 4.00 
8 | 0.044 | 2.67 
16 | - | - "
  run_levels "$fixtures/streams-result.json"
  assert_equal "embed" "$(sed -n 3p <<<"$out" | cut -d '|' -f 11)" " - "
}

test_levels_rates_each_level_on_the_requests_finished_in_its_second_half() {
  run jq -r --arg purpose vision -f "$repo/bench/levels.jq" "$fixtures/vision-result.json"
  assert_equal status "$status" 0
  assert_equal levels "$(cut -d '|' -f 1,3,4 <<<"$out")" "## vision-result.json
level | req/s | 2nd half req/s 
4 | 0.950 | 0.067 
8 | 0.800 | 0.044 
16 | 0.600 | - "
}

test_levels_judges_each_agent_level_by_its_itl_median() {
  run jq -r --arg purpose agent -f "$repo/bench/levels.jq" "$fixtures/agent-result.json"
  assert_equal status "$status" 0
  assert_equal levels "$(cut -d '|' -f 1,2,5,6,13,18 <<<"$out")" "## agent-result.json
level | ok/err/inc | TTFT med ms | ITL med ms | out tok/s | floor
4 | 4/0/0 | 61235 | 49.13 | 5.61 | meets
12 | 2/0/10 | 250000 | 100.50 | 0.90 | MISSES
16 | 0/0/16 | - | - | 0.00 | MISSES"
}

test_levels_refuses_an_unknown_purpose() {
  run jq -r --arg purpose client -f "$repo/bench/levels.jq" "$fixtures/vision-result.json"
  assert_equal status "$status" 5
  assert_contains stderr "$err" "purpose must be agent, vision, audio or embed"
}

run_tests
