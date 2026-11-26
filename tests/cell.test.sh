#!/usr/bin/env bash
# Tests for bench/cell.sh, the bench cell runner, with guidellm and curl stubbed: the GuideLLM run
# it starts for each level, streams or a rate, the rows and seeds each level takes, the duration it
# sets, the row's cache counters it reads before the first level, and what it refuses before any
# request.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

clean_metrics='# HELP vllm:prefix_cache_queries_total Prefix cache queries.
vllm:prefix_cache_queries_total{engine="0",model_name="openai/gpt-oss-120b"} 0.0
vllm:prefix_cache_hits_total{engine="0",model_name="openai/gpt-oss-120b"} 0.0
vllm:mm_cache_queries_total{engine="0",model_name="openai/gpt-oss-120b"} 0.0'

run_cell() {
  write_stub guidellm "${guidellm_body:-}"
  write_stub curl "cat $(printf %q "$tmp/metrics") 2>/dev/null || exit 22"
  run "$repo/bench/cell.sh" "$@"
}

serve_metrics() {
  printf '%s\n' "$1" >"$tmp/metrics"
}

agent_cell() {
  run_cell --host gb10-1 --alias agent --scenario "$repo/bench/agent-capacity.yaml" --cell c \
    --output "$tmp/out" "$@"
}

guidellm_calls() {
  calls | grep '^guidellm '
}

write_rows_scenario() {
  seq 1 "$1" | jq -c '{prompt: "p", audio: "a\(.).wav"}' >"$tmp/rows.jsonl"
  cat >"$tmp/rows.yaml" <<EOF
spec:
  backend:
    kind: openai_http
    request_format: /v1/chat/completions
  profile:
    kind: concurrent
    streams: [2, 4]
  data:
    - kind: json_file
      path: $tmp/rows.jsonl
EOF
}

test_each_level_runs_alone_against_the_rows_port_alias_and_tokenizer() {
  serve_metrics "$clean_metrics"
  agent_cell 4 8
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal calls "$(calls)" "curl --silent --fail --max-time 5 http://gb10-1:8000/metrics
guidellm run -c $repo/bench/agent-capacity.yaml --profile kind=concurrent,streams=4 --data kind=synthetic_text,prompt_tokens=65536,output_tokens=256 --seed kind=static,value=4 --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --output kind=json,path=$tmp/out/c-4.json
guidellm run -c $repo/bench/agent-capacity.yaml --profile kind=concurrent,streams=8 --data kind=synthetic_text,prompt_tokens=65536,output_tokens=256 --seed kind=static,value=8 --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --output kind=json,path=$tmp/out/c-8.json"
}

test_guidellm_runs_against_the_rows_address() {
  serve_metrics "$clean_metrics"
  local guidellm_body
  # shellcheck disable=SC2016 # The stub expands the target when GuideLLM would read it.
  guidellm_body='echo "target $GUIDELLM__SPEC__BACKEND__TARGET" >>'"$(printf %q "$tmp/calls")"
  agent_cell 8
  assert_contains calls "$(calls)" "target http://gb10-1:8000"
}

test_a_vision_level_draws_its_image_from_a_seed_of_its_streams() {
  serve_metrics "$clean_metrics"
  run_cell --host gb10-2 --alias vision --scenario "$repo/bench/vision-capacity.yaml" --cell v \
    --output "$tmp/out" 4 16
  assert_equal status "$status" 0
  assert_contains calls "$(guidellm_calls | sed -n 1p)" "--data kind=synthetic_text,prompt_tokens=200 --data kind=synthetic_image,resolution=1440p,format=jpeg,output_tokens=100,seed=4 --seed kind=static,value=4"
  assert_contains calls "$(guidellm_calls | sed -n 2p)" "seed=16 --seed kind=static,value=16"
  assert_contains calls "$(guidellm_calls)" "--tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it"
  assert_contains calls "$(calls)" "curl --silent --fail --max-time 5 http://gb10-2:8001/metrics"
}

test_each_level_of_a_json_scenario_takes_the_next_rows() {
  serve_metrics "$clean_metrics"
  write_rows_scenario 6
  run_cell --host framework --alias audio --scenario "$tmp/rows.yaml" --cell a --output "$tmp/out" \
    2:2 4:3
  assert_equal status "$status" 0
  assert_contains calls "$(guidellm_calls | sed -n 1p)" "--data kind=json_file,path=$tmp/out/a-2.jsonl --seed"
  assert_contains calls "$(guidellm_calls | sed -n 2p)" "--data kind=json_file,path=$tmp/out/a-4.jsonl --seed"
  assert_equal "level 2 rows" "$(jq -r .audio "$tmp/out/a-2.jsonl" | paste -sd ' ')" "a1.wav a2.wav"
  assert_equal "level 4 rows" "$(jq -r .audio "$tmp/out/a-4.jsonl" | paste -sd ' ')" \
    "a3.wav a4.wav a5.wav"
}

test_a_level_of_a_constant_scenario_is_its_rate() {
  serve_metrics "$clean_metrics"
  run_cell --host framework-2 --alias embedding --scenario "$repo/bench/embedding-rate.yaml" \
    --cell e --output "$tmp/out" 78
  assert_equal status "$status" 0
  assert_equal calls "$(guidellm_calls)" "guidellm run -c $repo/bench/embedding-rate.yaml --profile kind=constant,rate=78 --data kind=synthetic_text,prompt_tokens=510 --seed kind=static,value=78 --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=intfloat/multilingual-e5-large --output kind=json,path=$tmp/out/e-78.json"
}

test_seconds_replaces_the_scenarios_duration_and_keeps_its_other_constraints() {
  serve_metrics "$clean_metrics"
  agent_cell --seconds 600 4
  assert_equal status "$status" 0
  assert_contains calls "$(guidellm_calls)" "--seed kind=static,value=4 --constraint kind=max_requests,count=8 --constraint kind=max_duration,seconds=600 --backend"
  rm -f "$tmp/calls"
  run_cell --host gb10-1 --alias agent --scenario "$repo/bench/agent-sessions.yaml" --cell s \
    --output "$tmp/out" --seconds 900 4
  assert_equal status "$status" 0
  assert_contains calls "$(guidellm_calls)" "--seed kind=static,value=4 --constraint kind=max_duration,seconds=900 --backend"
  assert_equal "constraints" "$(guidellm_calls | grep -o -- '--constraint' | wc -l)" 1
}

test_a_counter_the_row_does_not_expose_counts_as_zero() {
  serve_metrics 'vllm:num_requests_running{engine="0"} 0.0'
  agent_cell 8
  assert_equal status "$status" 0
  assert_equal "guidellm runs" "$(guidellm_calls | wc -l)" 1
}

test_a_row_whose_cache_counters_are_not_zero_is_refused() {
  local counter
  for counter in vllm:prefix_cache_queries_total vllm:mm_cache_queries_total; do
    rm -f "$tmp/calls"
    serve_metrics "$clean_metrics
$counter{engine=\"1\",model_name=\"openai/gpt-oss-120b\"} 2048.0"
    agent_cell 8
    assert_equal "status for $counter" "$status" 2
    assert_contains "stderr for $counter" "$err" "cell: http://gb10-1:8000 reads $counter at 2048, not 0; restart the row"
    assert_equal "guidellm runs for $counter" "$(guidellm_calls)" ""
  done
}

test_a_row_whose_metrics_do_not_answer_is_refused() {
  agent_cell 8
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: http://gb10-1:8000/metrics doesn't answer"
  assert_equal "guidellm runs" "$(guidellm_calls)" ""
}

test_a_failed_level_stops_the_cell() {
  serve_metrics "$clean_metrics"
  local guidellm_body='exit 3'
  agent_cell 4 8
  assert_equal status "$status" 3
  assert_equal "guidellm runs" "$(guidellm_calls | wc -l)" 1
}

test_a_missing_argument_is_refused() {
  local args=(--host gb10-1 --alias agent --scenario "$repo/bench/agent-capacity.yaml" --cell c)
  local i
  for i in 0 2 4 6; do
    run_cell "${args[@]:0:i}" "${args[@]:i+2}" 8
    assert_equal "status without ${args[i]}" "$status" 2
    assert_contains "stderr without ${args[i]}" "$err" "cell: no ${args[i]}"
  done
  run_cell "${args[@]}"
  assert_equal "status without a level" "$status" 2
  assert_contains "stderr without a level" "$err" "cell: no level"
  assert_equal calls "$(calls)" ""
}

test_a_malformed_argument_is_refused() {
  local host level
  for host in gb10-1.example http://gb10-1 gb10-1:8000 ''; do
    run_cell --host "$host" --alias agent --scenario "$repo/bench/agent-capacity.yaml" --cell c 8
    assert_equal "status for host [$host]" "$status" 2
    assert_contains "stderr for host [$host]" "$err" "is not a short host name"
  done
  run_cell --host gb10-1 --alias agent --scenario "$repo/bench/agent-capacity.yaml" --cell ../c 8
  assert_equal "status for cell ../c" "$status" 2
  assert_contains "stderr for cell ../c" "$err" "--cell ../c is not a file name"
  for level in 0 x 8: 8:0 :4 -8; do
    agent_cell "$level"
    assert_equal "status for level [$level]" "$status" 2
  done
  agent_cell 8x
  assert_contains stderr "$err" "cell: level 8x is not <level> or <level>:<rows>"
  agent_cell 4 8 4
  assert_equal "status for a repeated level" "$status" 2
  assert_contains stderr "$err" "cell: level 4 repeats level 4"
  for seconds in 0 -1 1.5 x; do
    agent_cell --seconds "$seconds" 8
    assert_equal "status for --seconds [$seconds]" "$status" 2
    assert_contains "stderr for --seconds [$seconds]" "$err" "cell: --seconds $seconds is not a positive whole number"
  done
  assert_equal calls "$(calls)" ""
}

test_an_unknown_option_or_one_without_its_value_is_refused() {
  agent_cell --rate 8 8
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: unknown option --rate"
  run_cell --host gb10-1 --alias agent --cell
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: --cell needs a value"
  assert_equal calls "$(calls)" ""
}

test_rows_must_match_whether_the_scenario_reads_a_json_file() {
  agent_cell 8:100
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: level 8:100 gives rows; scenario $repo/bench/agent-capacity.yaml reads no JSON file"
  write_rows_scenario 6
  run_cell --host framework --alias audio --scenario "$tmp/rows.yaml" --cell a 2:2 4
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: level 4 gives no rows; scenario $tmp/rows.yaml reads a JSON file"
  assert_equal calls "$(calls)" ""
}

test_levels_taking_more_rows_than_the_file_holds_are_refused() {
  write_rows_scenario 6
  run_cell --host framework --alias audio --scenario "$tmp/rows.yaml" --cell a 2:4 4:3
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: the levels take 7 rows, and $tmp/rows.jsonl holds 6"
  assert_equal calls "$(calls)" ""
}

test_a_scenario_whose_levels_cannot_take_distinct_inputs_is_refused() {
  run_cell --host framework --alias audio --scenario "$repo/bench/audio.yaml" --cell a 4
  assert_equal status "$status" 2
  assert_contains stderr "$err" "reads huggingface"
  run_cell --host framework-2 --alias embedding --scenario "$repo/bench/embedding-rate-sweep.yaml" \
    --cell e 4
  assert_equal status "$status" 2
  assert_contains stderr "$err" "is not a concurrent or constant profile"
  run_cell --host gb10-1 --alias agent --scenario "$tmp/absent.yaml" --cell c 8
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: scenario $tmp/absent.yaml is not a file"
  assert_equal calls "$(calls)" ""
}

test_an_alias_no_class_profile_serves_is_refused() {
  run_cell --host gb10-1 --alias chat --scenario "$repo/bench/agent-capacity.yaml" --cell c 8
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: alias chat is the alias of 0 rows in the class profiles, not 1"
  assert_equal calls "$(calls)" ""
}

test_a_level_whose_result_exists_is_refused() {
  mkdir -p "$tmp/out"
  touch "$tmp/out/c-8.json"
  agent_cell 4 8
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: $tmp/out/c-8.json exists"
  assert_equal calls "$(calls)" ""
}

test_outside_the_bench_environment_it_refuses() {
  local dir dirs path=$stubs
  write_stub curl
  IFS=: read -ra dirs <<<"$base_path"
  for dir in "${dirs[@]}"; do
    [[ -x $dir/guidellm ]] || path+=:$dir
  done
  PATH=$path run "$repo/bench/cell.sh" --host gb10-1 --alias agent \
    --scenario "$repo/bench/agent-capacity.yaml" --cell c --output "$tmp/out" 8
  assert_equal status "$status" 2
  assert_contains stderr "$err" "cell: guidellm is not on PATH"
  assert_equal calls "$(calls)" ""
}

run_tests
