#!/usr/bin/env bash
# Tests for bench/audio-clips.sh, the audio bench's speech writer's argument handling, with
# guidellm and its Python stubbed: what it hands the Python, and what it refuses before running
# anything.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

run_clips() {
  write_stub guidellm
  write_stub python
  run "$repo/bench/audio-clips.sh" "$@"
}

test_scenarios_write_into_the_untracked_state_directory() {
  run_clips scenarios
  assert_equal status "$status" 0
  assert_equal calls "$(calls)" "python $repo/bench/audio-clips.py scenarios --output=$repo/.state/bench/audio"
}

test_scenarios_take_another_output_directory() {
  run_clips scenarios --output "$tmp/audio"
  assert_equal status "$status" 0
  assert_equal calls "$(calls)" "python $repo/bench/audio-clips.py scenarios --output=$tmp/audio"
}

test_the_probe_writes_into_the_directory_given() {
  run_clips probe "$tmp/probe"
  assert_equal status "$status" 0
  assert_equal calls "$(calls)" "python $repo/bench/audio-clips.py probe --output=$tmp/probe"
}

test_the_probe_without_a_directory_is_refused() {
  run_clips probe
  assert_equal status "$status" 2
  assert_contains stderr "$err" "audio-clips: probe takes one directory"
  assert_equal calls "$(calls)" ""
}

test_an_empty_directory_is_refused() {
  run_clips probe ''
  assert_equal status "$status" 2
  assert_contains stderr "$err" "audio-clips: the output directory is empty"
  assert_equal calls "$(calls)" ""
}

test_scenarios_refuse_any_other_argument() {
  local args
  for args in "--rows 10" "--output" "--output a b" "extra"; do
    # shellcheck disable=SC2086 # Each case is split into its arguments.
    run_clips scenarios $args
    assert_equal "status for $args" "$status" 2
    assert_contains "stderr for $args" "$err" "audio-clips: scenarios takes only --output <dir>"
  done
  assert_equal calls "$(calls)" ""
}

test_no_or_an_unknown_command_is_refused() {
  run_clips
  assert_equal status "$status" 2
  assert_contains stderr "$err" "audio-clips: no scenarios or probe"
  run_clips windows
  assert_equal status "$status" 2
  assert_contains stderr "$err" "audio-clips: unknown windows"
  assert_contains stderr "$err" "usage: bench/audio-clips.sh"
  assert_equal calls "$(calls)" ""
}

test_outside_the_bench_environment_it_refuses() {
  PATH=$stubs:/usr/bin:/bin run "$repo/bench/audio-clips.sh" scenarios
  assert_equal status "$status" 2
  assert_contains stderr "$err" "audio-clips: guidellm is not on PATH"
}

run_tests
