#!/usr/bin/env bash
# Tests for bench/retrieval.sh, the BelebeleRetrieval runner's argument handling, with mteb and its
# Python stubbed: what it hands the Python, and what it refuses before running anything.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

run_retrieval() {
  write_stub mteb
  write_stub python
  run "$repo/bench/retrieval.sh" "$@"
}

subsets_run() {
  calls | grep '^python ' | tr ' ' '\n' | sed -n '/^--$/,$p' | sed 1d
}

test_no_subset_runs_the_37_for_the_13_languages() {
  run_retrieval --endpoint framework:8003 --query-prefix 'query: ' --passage-prefix 'passage: '
  assert_equal status "$status" 0
  assert_equal "subsets" "$(subsets_run | wc -l)" 37
  assert_equal "distinct subsets" "$(subsets_run | sort -u | wc -l)" 37
  assert_equal "same-language subsets" "$(subsets_run | grep -cE '^([a-z]{3}_[A-Za-z]{4})-\1$')" 13
  assert_equal "subsets into English" "$(subsets_run | grep -v '^eng_Latn-' | grep -c -e '-eng_Latn$')" 12
  assert_equal "subsets from English" "$(subsets_run | grep '^eng_Latn-' | grep -vc -e '-eng_Latn$')" 12
  local subset
  for subset in eng_Latn-eng_Latn zho_Hans-zho_Hans eng_Latn-zho_Hans zho_Hans-eng_Latn \
    arb_Arab-eng_Latn eng_Latn-kor_Hang heb_Hebr-heb_Hebr; do
    assert_contains "subsets" "$(subsets_run)" "$subset"
  done
}

test_given_subsets_run_alone() {
  run_retrieval --endpoint framework:8003 --query-prefix '' --passage-prefix '' \
    eng_Latn-eng_Latn rus_Cyrl-eng_Latn
  assert_equal status "$status" 0
  assert_equal "subsets" "$(subsets_run | paste -sd ' ')" "eng_Latn-eng_Latn rus_Cyrl-eng_Latn"
}

test_the_arguments_reach_the_python_beside_mteb() {
  run_retrieval --endpoint framework:8003 --query-prefix 'query: ' --passage-prefix 'passage: ' \
    --output "$tmp/out" eng_Latn-eng_Latn
  assert_equal status "$status" 0
  assert_equal calls "$(calls)" "python $repo/bench/retrieval.py --endpoint framework:8003 --query-prefix=query:  --passage-prefix=passage:  --output=$tmp/out -- eng_Latn-eng_Latn"
}

test_the_output_defaults_to_the_untracked_state_directory() {
  run_retrieval --endpoint framework:8003 --query-prefix '' --passage-prefix '' eng_Latn-eng_Latn
  assert_contains calls "$(calls)" "--output=$repo/.state/bench/retrieval "
}

test_a_missing_endpoint_is_refused() {
  run_retrieval --query-prefix '' --passage-prefix '' eng_Latn-eng_Latn
  assert_equal status "$status" 2
  assert_contains stderr "$err" "retrieval: no --endpoint"
  assert_equal calls "$(calls)" ""
}

test_an_endpoint_that_is_not_host_and_port_is_refused() {
  local endpoint
  for endpoint in framework http://framework:8003 framework:port ''; do
    run_retrieval --endpoint "$endpoint" --query-prefix '' --passage-prefix ''
    assert_equal "status for [$endpoint]" "$status" 2
    assert_contains "stderr for [$endpoint]" "$err" "is not <host>:<port>"
  done
  assert_equal calls "$(calls)" ""
}

test_a_missing_prefix_is_refused() {
  run_retrieval --endpoint framework:8003 --passage-prefix 'passage: '
  assert_equal status "$status" 2
  assert_contains stderr "$err" "retrieval: no --query-prefix"
  run_retrieval --endpoint framework:8003 --query-prefix 'query: '
  assert_equal status "$status" 2
  assert_contains stderr "$err" "retrieval: no --passage-prefix"
  assert_equal calls "$(calls)" ""
}

test_a_malformed_subset_is_refused() {
  run_retrieval --endpoint framework:8003 --query-prefix '' --passage-prefix '' \
    eng_Latn-eng_Latn eng-rus
  assert_equal status "$status" 2
  assert_contains stderr "$err" "retrieval: subset eng-rus is not <lang>_<Script>-<lang>_<Script>"
  assert_equal calls "$(calls)" ""
}

test_an_unknown_option_is_refused() {
  run_retrieval --endpoint framework:8003 --query-prefix '' --passage-prefix '' --batch 8
  assert_equal status "$status" 2
  assert_contains stderr "$err" "retrieval: unknown option --batch"
  assert_equal calls "$(calls)" ""
}

test_an_option_without_its_value_is_refused() {
  run_retrieval --query-prefix '' --passage-prefix '' --endpoint
  assert_equal status "$status" 2
  assert_contains stderr "$err" "retrieval: --endpoint needs a value"
  assert_equal calls "$(calls)" ""
}

test_outside_the_bench_environment_it_refuses() {
  PATH=$stubs:/usr/bin:/bin run "$repo/bench/retrieval.sh" --endpoint framework:8003 \
    --query-prefix '' --passage-prefix ''
  assert_equal status "$status" 2
  assert_contains stderr "$err" "retrieval: mteb is not on PATH"
}

run_tests
