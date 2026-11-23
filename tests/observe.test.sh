#!/usr/bin/env bash
# Tests for hosting engine status, models, metrics, and memory (lib/observe.sh), with docker, curl,
# nvidia-smi, and amdgpu_top stubbed to log their calls and answer from a fake Docker state and
# fake row answers, and a fake system tree holding /proc/meminfo and amdgpu's GTT: each reads the
# rows by their label, and none issues a docker call that changes anything.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

observed_host() {
  export HOSTING_TEST_DOCKER=$tmp/docker HOSTING_TEST_CURL=$tmp/curl
  mkdir -p "$HOSTING_TEST_DOCKER"/{inspect,top} "$HOSTING_TEST_CURL"
  write_stub docker "$(
    cat <<'EOF'
case "$1 $2" in
  "container ls") cat "$HOSTING_TEST_DOCKER/ids" 2>/dev/null || true ;;
  "container inspect")
    for id in "${@:3}"; do cat "$HOSTING_TEST_DOCKER/inspect/$id"; done | jq -s .
    ;;
  "top "*) cat "$HOSTING_TEST_DOCKER/top/$2" ;;
esac
EOF
  )"
  write_stub curl "$(
    cat <<'EOF'
url=${*: -1}
url=${url#http://}
cat "$HOSTING_TEST_CURL/${url//\//_}" 2>/dev/null || exit 22
EOF
  )"
  mkdir -p "$sysroot/proc"
  printf '%s\n' 'MemTotal:       127535100 kB' 'MemAvailable:   13589544 kB' \
    >"$sysroot/proc/meminfo"
}

row_container() {
  echo "$2" >>"$HOSTING_TEST_DOCKER/ids"
  jq -n --arg alias "$1" --arg id "$2" --arg name "$3" --arg state "$4" --arg bind "$5" \
    --argjson published "$6" --argjson networks "$7" '
    ($bind | split(":")) as $b
    | (if $bind == "-" then {} else {"\($b[1])/tcp": [{HostIp: $b[0], HostPort: $b[1]}]} end) as $binds
    | {Id: ($id + "0123456789abcdef"), Name: "/\($name)", State: {Status: $state},
        Config: {Labels: {"ai-hosting.row": $alias}}, HostConfig: {PortBindings: $binds},
        NetworkSettings: {
          Ports: (if $published > 0 then $binds else ($binds | map_values(null)) end),
          Networks: (if $networks > 0 then {bridge: {}} else {} end)}}' \
    >"$HOSTING_TEST_DOCKER/inspect/$2"
}

running_row() {
  row_container "$1" "$2" "vllm-$1" running "192.0.2.10:$3" 1 1
}

processes() {
  printf '%s\n' PID "${@:2}" >"$HOSTING_TEST_DOCKER/top/$1"
}

answer() {
  cat >"$HOSTING_TEST_CURL/${1//\//_}"
}

engine() {
  HOSTING_CLASS=${class:-} run_hosting engine "$@"
}

assert_read_only() {
  local writes
  writes=$(calls | grep '^docker' | grep -Ev '^docker (container (ls|inspect)|top) ' || true)
  assert_equal "docker calls that change something" "$writes" ""
}

test_status_shows_each_rows_state_and_health() {
  observed_host
  running_row agent c00000000001 8000
  running_row vision c00000000002 8001
  echo '{}' | answer 192.0.2.10:8000/health
  echo '{}' | answer 192.0.2.10:8001/health
  engine status
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "ROW          CONTAINER            STATE      HEALTH     ADDRESS
agent        vllm-agent           running    healthy    192.0.2.10:8000
vision       vllm-vision          running    healthy    192.0.2.10:8001"
  assert_equal "docker calls" "$(calls | grep '^docker')" \
    "docker container ls --all --quiet --filter label=ai-hosting.row
docker container inspect c00000000001 c00000000002"
}

test_status_flags_a_container_on_no_network_with_the_reconnect_command() {
  observed_host
  row_container agent c00000000001 vllm-agent running 192.0.2.10:8000 0 0
  engine status
  assert_equal status "$status" 1
  assert_contains stdout "$out" "agent        vllm-agent           running    unhealthy  192.0.2.10:8000"
  assert_contains stdout "$out" "vllm-agent is stranded: it is on no network, so 192.0.2.10:8000 is published nowhere; docker network connect bridge vllm-agent reattaches it"
  assert_contains stdout "$out" "net.ipv4.ip_nonlocal_bind = 1"
  assert_read_only
}

test_status_flags_a_networked_container_publishing_no_port_with_a_restart() {
  observed_host
  row_container vision c00000000002 vllm-vision running 192.0.2.10:8001 0 1
  engine status
  assert_equal status "$status" 1
  assert_contains stdout "$out" "vllm-vision is stranded: its start couldn't bind 192.0.2.10:8001, so it publishes no port; docker restart vllm-vision binds it, once the host holds the address"
  assert_read_only
}

test_status_never_flags_a_stopped_container_and_lists_a_recorded_alias_with_none() {
  observed_host
  row_container agent c00000000001 vllm-agent exited 192.0.2.10:8000 0 0
  record agent vision
  engine status
  assert_equal status "$status" 1
  assert_equal stdout "$out" "ROW          CONTAINER            STATE      HEALTH     ADDRESS
agent        vllm-agent           exited     -          192.0.2.10:8000
vision       -                    none       -          -"
  assert_read_only
}

test_status_refuses_an_argument() {
  observed_host
  engine status agent
  assert_equal status "$status" 2
  assert_equal calls "$(calls)" ""
}

test_models_prints_each_rows_served_model() {
  observed_host
  running_row agent c00000000001 8000
  running_row vision c00000000002 8001
  echo '{"data":[{"id":"agent","root":"openai/gpt-oss-120b","max_model_len":131072}]}' |
    answer 192.0.2.10:8000/v1/models
  echo '{"data":[{"id":"vision","root":"nvidia/Gemma-4-26B-A4B-NVFP4","max_model_len":8192}]}' |
    answer 192.0.2.10:8001/v1/models
  engine models
  assert_equal status "$status" 0
  assert_equal stdout "$out" "ROW          MODEL        ROOT                                     CONTEXT
agent        agent        openai/gpt-oss-120b                      131072
vision       vision       nvidia/Gemma-4-26B-A4B-NVFP4             8192"
  assert_read_only
}

test_models_marks_a_row_that_gives_none() {
  observed_host
  running_row agent c00000000001 8000
  engine models
  assert_equal status "$status" 1
  assert_contains stdout "$out" "agent        - (vllm-agent is running and gave no /v1/models)"
  assert_read_only
}

test_metrics_summarizes_a_rows_vllm_metrics() {
  observed_host
  running_row agent c00000000001 8000
  answer 192.0.2.10:8000/metrics <<'EOF'
# HELP vllm:num_requests_running Number of requests in model execution batches.
# TYPE vllm:num_requests_running gauge
vllm:num_requests_running{engine="0",model_name="agent"} 3.0
vllm:num_requests_waiting{engine="0",model_name="agent"} 1.0
vllm:kv_cache_usage_perc{engine="0",model_name="agent"} 0.25
vllm:prompt_tokens_total{engine="0",model_name="agent"} 120000.0
vllm:generation_tokens_total{engine="0",model_name="agent"} 4500.0
vllm:request_success_total{engine="0",finished_reason="stop",model_name="agent"} 40.0
vllm:request_success_total{engine="0",finished_reason="length",model_name="agent"} 2.0
python_gc_objects_collected_total{generation="0"} 12.0
EOF
  engine metrics agent
  assert_equal status "$status" 0
  assert_equal stdout "$out" "row:                 agent (vllm-agent at 192.0.2.10:8000)
requests running:    3
requests waiting:    1
KV cache usage:      25%
prompt tokens:       120000
generation tokens:   4500
requests finished:   42
preemptions:         -"
  assert_read_only
}

test_metrics_refuses_an_alias_no_container_carries() {
  observed_host
  running_row agent c00000000001 8000
  engine metrics vision
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: no container carries the row label ai-hosting.row=vision; hosting engine status lists the rows"
  assert_equal "curl calls" "$(calls | grep '^curl' || true)" ""
}

test_metrics_refuses_a_row_without_vllm_metrics() {
  observed_host
  running_row agent c00000000001 8000
  engine metrics agent
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: vllm-agent gave no vLLM metrics at http://192.0.2.10:8000/metrics"
}

test_metrics_takes_one_alias() {
  observed_host
  engine metrics
  assert_equal status "$status" 2
  assert_equal calls "$(calls)" ""
}

test_memory_on_gb10_joins_nvidia_smis_processes_to_each_row_by_pid() {
  observed_host
  running_row agent c00000000001 8000
  running_row vision c00000000002 8001
  processes c00000000001 4101 4102
  processes c00000000002 4201
  write_stub nvidia-smi 'printf "%s\n" "4102, 98304" "4201, 40960" "4101, 512" "999, 100"'
  class=gb10 engine memory
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "ROW          CONTAINER               GPU MiB
agent        vllm-agent                98816
vision       vllm-vision               40960
pid 999      -                           100
pool: MemAvailable 12.96 GiB"
  assert_contains calls "$(calls)" \
    "nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits"
  assert_read_only
}

test_memory_on_strix_halo_reads_amdgpu_top_with_gtt() {
  observed_host
  row_container audio c00000000003 vllm-audio running 192.0.2.10:8002 1 1
  row_container embedding c00000000004 vllm-embedding exited 192.0.2.10:8003 0 0
  processes c00000000003 5101 5102
  write_stub amdgpu_top "$(
    cat <<'EOF'
cat <<'OUT'
--- AMD Radeon 8060S Graphics ---
 VRAM 512/512 MiB, GTT 30720/98304 MiB
 python3 (  5101), ctxs   1, VRAM     8 MiB (  1.5%), GTT 20480 MiB, CPU   0%
 python3 (  5102), ctxs   1, VRAM     4 MiB (  0.8%), GTT  2048 MiB, CPU   0%
OUT
EOF
  )"
  mkdir -p "$sysroot/sys/class/drm/card0/device"
  echo $((30 * 2 ** 30)) >"$sysroot/sys/class/drm/card0/device/mem_info_gtt_used"
  echo $((96 * 2 ** 30)) >"$sysroot/sys/class/drm/card0/device/mem_info_gtt_total"
  class=strix-halo engine memory
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "ROW          CONTAINER              VRAM MiB    GTT MiB
audio        vllm-audio                   12      22528
embedding    vllm-embedding                -          -
pool: GTT used 30.00 GiB of 96.00 GiB; MemAvailable 12.96 GiB"
  assert_contains calls "$(calls)" "amdgpu_top -p --no-pc"
  assert_read_only
}

test_memory_refuses_an_unknown_class_before_docker() {
  observed_host
  class=tpu engine memory
  assert_equal status "$status" 1
  assert_contains stderr "$err" "HOSTING_CLASS is tpu"
  assert_equal calls "$(calls)" ""
}

run_tests
