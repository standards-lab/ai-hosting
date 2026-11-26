#!/usr/bin/env bash
# Tests for hosting engine install, update, and uninstall (lib/engine.sh), with docker, hf, and
# tailscale stubbed to log their calls, docker answering from a fake Docker state, and a fake system
# tree holding the sysctl and the CDI spec: each refusal comes before any docker call that changes
# anything, and each command issues the docker calls its row needs and keeps the install record.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/hosting.sh
source "$repo/lib/hosting.sh"

ready_host() {
  export HOSTING_TEST_DOCKER=$tmp/docker
  mkdir -p "$HOSTING_TEST_DOCKER"/{ls,container,image}
  write_stub docker "$(
    cat <<'EOF'
key=${*: -1}
key=${key//\//_}
case "$1 $2" in
  "container ls")
    if [[ $* == *--format* ]]; then
      cat "$HOSTING_TEST_DOCKER/ps" 2>/dev/null || true
    else
      cat "$HOSTING_TEST_DOCKER/ls/$key" 2>/dev/null || true
    fi
    ;;
  "container inspect") cat "$HOSTING_TEST_DOCKER/container/$key" ;;
  "image inspect") cat "$HOSTING_TEST_DOCKER/image/$key" ;;
  "image ls") cat "$HOSTING_TEST_DOCKER/images" 2>/dev/null || true ;;
  "image rm")
    if ! grep -qxF -- "$3" "$HOSTING_TEST_DOCKER/images" 2>/dev/null; then
      echo "Error response from daemon: No such image: $3" >&2
      exit 1
    fi
    ;;
  build\ *)
    if [[ $* != *--provenance=false* ]]; then
      args=$*
      tag=${args#*--tag }
      tag=${tag%% *}
      echo "sha256:index$RANDOM" | tee "$HOSTING_TEST_DOCKER/image/${tag//\//_}" \
        >>"$HOSTING_TEST_DOCKER/images"
    fi
    ;;
  "rm --force")
    for users in "$HOSTING_TEST_DOCKER"/ls/ancestor=*; do
      [[ ! -e $users ]] || sed -i "/^$3\$/d" "$users"
    done
    ;;
esac
EOF
  )"
  write_stub hf
  write_stub tailscale 'echo 192.0.2.10'
  nonlocal_bind 1
  mkdir -p "$sysroot/var/run/cdi" "$sysroot/usr/lib/aarch64-linux-gnu"
  touch "$sysroot/usr/lib/aarch64-linux-gnu/libcuda.so.580.95.05"
  printf '%s\n' 'cdiVersion: 0.5.0' 'containerEdits:' '  mounts:' \
    '  - hostPath: /usr/lib/aarch64-linux-gnu/libcuda.so.580.95.05' \
    '    containerPath: /usr/lib/aarch64-linux-gnu/libcuda.so.580.95.05' \
    >"$sysroot/var/run/cdi/nvidia.yaml"
}

nonlocal_bind() {
  mkdir -p "$sysroot/proc/sys/net/ipv4"
  echo "$1" >"$sysroot/proc/sys/net/ipv4/ip_nonlocal_bind"
}

container_of() {
  echo "$2" >"$HOSTING_TEST_DOCKER/ls/label=ai-hosting.row=$1"
  echo "$2" >>"$HOSTING_TEST_DOCKER/ls/ancestor=$3"
  echo "$3 $4" >"$HOSTING_TEST_DOCKER/container/$2"
  echo "$3" >>"$HOSTING_TEST_DOCKER/images"
}

listed() {
  local IFS=$'\t'
  echo "$*" >>"$HOSTING_TEST_DOCKER/ps"
}

ps_call="docker container ls --all --format {{.Names}}"$'\t'"{{.State}}"$'\t'"{{.Label \"ai-hosting.row\"}}"$'\t'"{{.Ports}}"

image_of() {
  echo "$2" >"$HOSTING_TEST_DOCKER/image/${1//\//_}"
  echo "$2" >>"$HOSTING_TEST_DOCKER/images"
}

image_gone() {
  sed -i "/^$1\$/d" "$HOSTING_TEST_DOCKER/images"
}

recorded() {
  cat "$XDG_STATE_HOME/hosting/aliases" 2>/dev/null
}

docker_calls() {
  calls | grep '^docker' || true
}

rendered() {
  HOSTING_CLASS=$1 run_hosting profile render "$2"
  tr '\n' ' ' <<<"$out" | sed 's/ $//'
}

engine() {
  HOSTING_CLASS=$1 run_hosting engine "${@:2}"
}

test_install_pulls_the_model_and_image_runs_the_rendered_row_and_records_it() {
  ready_host
  engine gb10 install agent
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_contains stdout "$out" "agent runs vllm/vllm-openai:v0.34.0 in vllm-agent"
  assert_contains calls "$(calls)" "hf download openai/gpt-oss-120b --cache-dir /srv/models"
  assert_equal "docker calls" "$(docker_calls)" "$ps_call
docker container ls --all --quiet --filter label=ai-hosting.row=agent
docker pull vllm/vllm-openai:v0.34.0
$(rendered gb10 agent)"
  assert_equal record "$(recorded)" agent
}

test_install_builds_a_rows_own_image() {
  ready_host
  engine strix-halo install audio
  assert_equal status "$status" 0
  assert_contains "docker calls" "$(docker_calls)" \
    "docker build --provenance=false --tag ai-hosting/vllm-openai-rocm-audio:v0.34.0 $clone/images/vllm-openai-rocm-audio"
  assert_contains "docker calls" "$(docker_calls)" "$(rendered strix-halo audio)"
}

test_install_of_two_rows_appends_each_to_the_record() {
  ready_host
  record embedding
  engine strix-halo install audio
  assert_equal status "$status" 0
  assert_equal record "$(recorded)" "embedding
audio"
}

test_install_leaves_an_installed_row_and_records_it() {
  ready_host
  container_of agent c1 sha256:old '[]'
  engine gb10 install agent
  assert_equal status "$status" 0
  assert_equal stdout "$out" "agent is already installed; hosting engine update agent moves it to the profile"
  assert_equal "docker calls" "$(docker_calls)" "$ps_call
docker container ls --all --quiet --filter label=ai-hosting.row=agent"
  assert_equal record "$(recorded)" agent
}

test_install_refuses_an_unknown_alias_before_docker() {
  ready_host
  engine gb10 install agent audio
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: classes/gb10/profile.toml has no row audio; its aliases are agent vision"
  assert_equal calls "$(calls)" ""
  assert_equal record "$(recorded)" ""
}

test_install_refuses_fractions_over_one_with_the_record_before_docker() {
  ready_host
  record agent
  engine gb10 install vision
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: the rows that would stand on this host reserve more than all its GPU's memory: agent 0.80, vision 0.55 sum to 1.35, over 1"
  assert_equal calls "$(calls)" ""
  assert_equal record "$(recorded)" agent
}

test_install_refuses_a_recorded_alias_the_profile_lacks_before_docker() {
  ready_host
  record audio
  engine gb10 install agent
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: the record $XDG_STATE_HOME/hosting/aliases holds audio, which classes/gb10/profile.toml has no row for; hosting engine uninstall audio removes it"
  assert_equal calls "$(calls)" ""
}

test_install_refuses_nonlocal_bind_off_before_docker() {
  ready_host
  nonlocal_bind 0
  engine strix-halo install audio
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: net.ipv4.ip_nonlocal_bind is 0, not 1; the root step in classes/strix-halo/runbook.md, \"Root steps\", sets it"
  assert_equal calls "$(calls)" ""
}

test_install_refuses_an_unreadable_nonlocal_bind_before_docker() {
  ready_host
  rm "$sysroot/proc/sys/net/ipv4/ip_nonlocal_bind"
  engine gb10 install agent
  assert_equal status "$status" 1
  assert_contains stderr "$err" "net.ipv4.ip_nonlocal_bind is unreadable, not 1"
  assert_equal calls "$(calls)" ""
}

test_install_on_gb10_refuses_a_cdi_spec_naming_a_missing_library_before_docker() {
  ready_host
  mkdir -p "$sysroot/etc/cdi"
  printf '%s\n' 'containerEdits:' '  mounts:' \
    "  - hostPath: \"/usr/lib/aarch64-linux-gnu/libnvidia-ml.so.580.82.07\"" \
    '  - hostPath: /usr/lib/aarch64-linux-gnu/libcuda.so.580.95.05' >"$sysroot/etc/cdi/nvidia.yaml"
  engine gb10 install agent
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: the CDI spec /etc/cdi/nvidia.yaml names /usr/lib/aarch64-linux-gnu/libnvidia-ml.so.580.82.07, which this host no longer has; sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml regenerates it (classes/gb10/runbook.md, \"Root steps\")"
  assert_equal calls "$(calls)" ""
}

test_install_on_strix_halo_reads_no_cdi_spec() {
  ready_host
  rm "$sysroot/usr/lib/aarch64-linux-gnu/libcuda.so.580.95.05"
  engine strix-halo install audio
  assert_equal status "$status" 0
}

test_install_refuses_an_invalid_profile_before_docker() {
  ready_host
  hosting_yq -p toml -o toml -i '.rows[0].fraction = 1.5' "$clone/classes/gb10/profile.toml"
  engine gb10 install agent
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: classes/gb10/profile.toml: rows[0].fraction: 1.5 is over 1"
  assert_equal calls "$(calls)" ""
}

test_install_takes_at_least_one_alias() {
  ready_host
  engine gb10 install
  assert_equal status "$status" 2
  assert_equal stderr "$err" "hosting: engine install takes at least one alias
usage: hosting engine install <alias>..."
}

test_install_refuses_an_unlabeled_container_holding_the_rows_name() {
  ready_host
  listed vllm-agent exited "" ""
  engine gb10 install agent
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: the container vllm-agent, without the ai-hosting.row label, holds agent's container name; docker rm -f vllm-agent removes it"
  assert_equal calls "$(calls)" "tailscale ip -4
$ps_call"
  assert_equal record "$(recorded)" ""
}

test_install_refuses_a_running_unlabeled_container_publishing_the_rows_port() {
  ready_host
  listed llama running "" "0.0.0.0:8000->8080/tcp, [::]:8000->8080/tcp"
  listed stopped exited "" ""
  engine gb10 install agent
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: the running container llama, without the ai-hosting.row label, publishes agent's port 8000; docker rm -f llama removes it"
  assert_equal calls "$(calls)" "tailscale ip -4
$ps_call"
  assert_equal record "$(recorded)" ""
}

test_install_refuses_a_running_unlabeled_container_publishing_a_range_over_the_rows_port() {
  ready_host
  listed ranged running "" "0.0.0.0:7999-8001->7999-8001/tcp"
  engine gb10 install agent
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: the running container ranged, without the ai-hosting.row label, publishes agent's port 8000; docker rm -f ranged removes it"
  assert_equal calls "$(calls)" "tailscale ip -4
$ps_call"
  assert_equal record "$(recorded)" ""
}

test_install_leaves_a_range_beside_the_rows_port_unrefused() {
  ready_host
  listed ranged running "" "0.0.0.0:8100-8102->8000-8002/tcp, 0.0.0.0:7990-7999->7990-7999/tcp"
  container_of agent c1 sha256:old '[]'
  engine gb10 install agent
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "agent is already installed; hosting engine update agent moves it to the profile"
}

test_install_leaves_the_rows_own_labeled_container_unrefused() {
  ready_host
  listed vllm-agent running agent "192.0.2.10:8000->8000/tcp"
  listed llama exited "" "0.0.0.0:8000->8080/tcp"
  listed other running "" "0.0.0.0:18000->8000/tcp"
  container_of agent c1 sha256:old '[]'
  engine gb10 install agent
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "agent is already installed; hosting engine update agent moves it to the profile"
  assert_equal "docker calls" "$(docker_calls)" "$ps_call
docker container ls --all --quiet --filter label=ai-hosting.row=agent"
  [[ $(calls) != *"hf download"* ]] || fail "pulled the model: $(calls)"
  assert_equal record "$(recorded)" agent
}

command_of() {
  HOSTING_CLASS=$1 run_hosting profile render "$2"
  sed -n "/^\(vllm\|ai-hosting\)\/.*:v[0-9]/,\$p" <<<"$out" | tail -n +2 | jq -Rnc '[inputs]'
}

agent_as_profiled() {
  image_of vllm/vllm-openai:v0.34.0 sha256:pinned
  container_of agent c1 sha256:pinned "$(command_of gb10 agent)"
}

test_update_with_nothing_changed_does_nothing() {
  ready_host
  record agent
  agent_as_profiled
  : >"$tmp/calls"
  engine gb10 update agent
  assert_equal status "$status" 0
  assert_equal stdout "$out" "agent already runs vllm/vllm-openai:v0.34.0 as its row; nothing changed"
  assert_equal "docker calls" "$(docker_calls)" "$ps_call
docker pull vllm/vllm-openai:v0.34.0
docker image inspect --format {{.Id}} vllm/vllm-openai:v0.34.0
docker container ls --all --quiet --filter label=ai-hosting.row=agent
docker container inspect --format {{.Image}} {{json .Config.Cmd}} c1"
  assert_equal record "$(recorded)" agent
}

test_update_replaces_a_row_whose_image_differs_and_removes_the_superseded_image() {
  ready_host
  record agent
  agent_as_profiled
  image_of vllm/vllm-openai:v0.34.0 sha256:newer
  : >"$tmp/calls"
  engine gb10 update agent
  assert_equal status "$status" 0
  assert_equal stdout "$out" "agent was replaced; it runs vllm/vllm-openai:v0.34.0 in vllm-agent
removed image sha256:pinned"
  assert_contains "docker calls" "$(docker_calls)" "docker rm --force c1
$(rendered gb10 agent)"
  assert_contains "docker calls" "$(docker_calls)" "docker image rm sha256:pinned"
}

test_update_rebuilds_a_rows_own_image_and_removes_the_superseded_build() {
  ready_host
  record audio
  image_of ai-hosting/vllm-openai-rocm-audio:v0.34.0 sha256:rebuilt
  container_of audio c1 sha256:built "$(command_of strix-halo audio)"
  : >"$tmp/calls"
  engine strix-halo update
  assert_equal status "$status" 0
  assert_contains "docker calls" "$(docker_calls)" \
    "docker build --provenance=false --tag ai-hosting/vllm-openai-rocm-audio:v0.34.0 $clone/images/vllm-openai-rocm-audio"
  assert_contains "docker calls" "$(docker_calls)" "docker rm --force c1"
  assert_contains "docker calls" "$(docker_calls)" "docker image rm sha256:built"
}

test_update_with_a_cached_rebuild_of_a_rows_own_image_does_nothing() {
  ready_host
  record audio
  image_of ai-hosting/vllm-openai-rocm-audio:v0.34.0 sha256:built
  container_of audio c1 sha256:built "$(command_of strix-halo audio)"
  : >"$tmp/calls"
  engine strix-halo update
  assert_equal status "$status" 0
  assert_equal stdout "$out" "audio already runs ai-hosting/vllm-openai-rocm-audio:v0.34.0 as its row; nothing changed"
  [[ $(docker_calls) != *"docker rm"* && $(docker_calls) != *"docker run"* ]] ||
    fail "replaced the row: $(docker_calls)"
}

test_update_replaces_a_row_whose_superseded_image_is_already_gone() {
  ready_host
  record audio
  image_of ai-hosting/vllm-openai-rocm-audio:v0.34.0 sha256:rebuilt
  container_of audio c1 sha256:built "$(command_of strix-halo audio)"
  image_gone sha256:built
  : >"$tmp/calls"
  engine strix-halo update
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "audio was replaced; it runs ai-hosting/vllm-openai-rocm-audio:v0.34.0 in vllm-audio"
  [[ $(docker_calls) != *"image rm"* ]] || fail "removed an image the host no longer has: $(docker_calls)"
}

test_update_keeps_a_superseded_image_another_container_uses() {
  ready_host
  record agent
  agent_as_profiled
  echo c9 >>"$HOSTING_TEST_DOCKER/ls/ancestor=sha256:pinned"
  image_of vllm/vllm-openai:v0.34.0 sha256:newer
  engine gb10 update agent
  assert_equal status "$status" 0
  assert_contains "docker calls" "$(docker_calls)" "docker rm --force c1"
  [[ $(docker_calls) != *"image rm"* ]] || fail "removed an image a container uses: $(docker_calls)"
}

test_update_replaces_a_row_whose_command_differs_and_keeps_its_image() {
  ready_host
  record agent
  agent_as_profiled
  hosting_yq -p toml -o toml -i '(.rows[] | select(.alias == "agent")).fraction = 0.75' "$clone/classes/gb10/profile.toml"
  : >"$tmp/calls"
  engine gb10 update agent
  assert_equal status "$status" 0
  assert_equal stdout "$out" "agent was replaced; it runs vllm/vllm-openai:v0.34.0 in vllm-agent"
  assert_contains "docker calls" "$(docker_calls)" "docker rm --force c1
$(rendered gb10 agent)"
  [[ $(docker_calls) != *"image rm"* ]] || fail "removed the image it runs: $(docker_calls)"
}

test_update_installs_an_absent_recorded_row() {
  ready_host
  record agent
  image_of vllm/vllm-openai:v0.34.0 sha256:pinned
  engine gb10 update
  assert_equal status "$status" 0
  assert_equal stdout "$out" "agent was not installed; it runs vllm/vllm-openai:v0.34.0 in vllm-agent"
  assert_contains "docker calls" "$(docker_calls)" "$(rendered gb10 agent)"
  [[ $(docker_calls) != *"docker rm"* ]] || fail "removed a container: $(docker_calls)"
}

test_update_with_no_alias_acts_on_the_record_alone() {
  ready_host
  record agent
  agent_as_profiled
  : >"$tmp/calls"
  engine gb10 update
  assert_equal status "$status" 0
  assert_equal stdout "$out" "agent already runs vllm/vllm-openai:v0.34.0 as its row; nothing changed"
  [[ $(calls) != *vision* && $(calls) != *Gemma* ]] || fail "touched the unrecorded vision row"
}

test_update_given_an_alias_records_it() {
  ready_host
  image_of vllm/vllm-openai:v0.34.0 sha256:pinned
  engine gb10 update agent
  assert_equal status "$status" 0
  assert_equal record "$(recorded)" agent
}

test_update_with_an_empty_record_does_nothing() {
  ready_host
  engine gb10 update
  assert_equal status "$status" 0
  assert_equal stdout "$out" "the install record $XDG_STATE_HOME/hosting/aliases holds no alias; nothing to update"
  assert_equal calls "$(calls)" ""
}

test_update_refuses_before_docker_as_install_does() {
  ready_host
  record agent
  agent_as_profiled
  nonlocal_bind 0
  : >"$tmp/calls"
  engine gb10 update
  assert_equal status "$status" 1
  assert_contains stderr "$err" "net.ipv4.ip_nonlocal_bind is 0, not 1"
  assert_equal calls "$(calls)" ""
  engine gb10 update audio
  assert_equal status "$status" 1
  assert_contains stderr "$err" "has no row audio"
  assert_equal calls "$(calls)" ""
}

test_update_refuses_an_unlabeled_container_holding_a_recorded_rows_name() {
  ready_host
  record agent
  agent_as_profiled
  listed vllm-agent created "" ""
  : >"$tmp/calls"
  engine gb10 update
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: the container vllm-agent, without the ai-hosting.row label, holds agent's container name; docker rm -f vllm-agent removes it"
  assert_equal calls "$(calls)" "tailscale ip -4
$ps_call"
  assert_equal record "$(recorded)" agent
}

test_update_refuses_a_running_unlabeled_container_publishing_the_rows_port() {
  ready_host
  record audio
  listed whisper running "" "192.0.2.10:8002->9000/tcp"
  : >"$tmp/calls"
  engine strix-halo update audio
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: the running container whisper, without the ai-hosting.row label, publishes audio's port 8002; docker rm -f whisper removes it"
  assert_equal calls "$(calls)" "tailscale ip -4
$ps_call"
  assert_equal record "$(recorded)" audio
}

test_update_leaves_the_rows_own_labeled_container_unrefused() {
  ready_host
  record agent
  agent_as_profiled
  listed vllm-agent running agent "192.0.2.10:8000->8000/tcp"
  : >"$tmp/calls"
  engine gb10 update agent
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "agent already runs vllm/vllm-openai:v0.34.0 as its row; nothing changed"
  assert_contains "docker calls" "$(docker_calls)" "$ps_call
docker pull vllm/vllm-openai:v0.34.0"
  [[ $(docker_calls) != *"docker rm"* && $(docker_calls) != *"docker run"* ]] ||
    fail "replaced the row: $(docker_calls)"
  assert_equal record "$(recorded)" agent
}

test_update_takes_at_most_one_alias() {
  ready_host
  engine gb10 update agent vision
  assert_equal status "$status" 2
  assert_equal stderr "$err" "hosting: engine update takes at most one alias
usage: hosting engine update [<alias>]"
}

uninstall() {
  run_hosting engine uninstall "$@"
}

test_uninstall_removes_the_container_and_its_unused_image_and_drops_the_alias() {
  ready_host
  record agent vision
  container_of agent c1 sha256:pinned '["openai/gpt-oss-120b"]'
  uninstall agent
  assert_equal status "$status" 0
  assert_equal stdout "$out" "removed agent's container c1
removed image sha256:pinned"
  assert_equal "docker calls" "$(docker_calls)" "docker container ls --all --quiet --filter label=ai-hosting.row=agent
docker container inspect --format {{.Image}} {{json .Config.Cmd}} c1
docker rm --force c1
docker container ls --all --quiet --filter ancestor=sha256:pinned
docker image ls --all --quiet --no-trunc
docker image rm sha256:pinned"
  assert_equal record "$(recorded)" vision
}

test_uninstall_keeps_an_image_another_container_uses() {
  ready_host
  record audio embedding
  container_of embedding c1 sha256:rocm '["intfloat/multilingual-e5-large"]'
  container_of audio c2 sha256:audio '["google/gemma-4-E4B-it"]'
  echo c9 >>"$HOSTING_TEST_DOCKER/ls/ancestor=sha256:rocm"
  uninstall embedding
  assert_equal status "$status" 0
  assert_equal stdout "$out" "removed embedding's container c1"
  [[ $(docker_calls) != *"image rm"* ]] || fail "removed an image a container uses: $(docker_calls)"
  assert_equal record "$(recorded)" audio
}

test_uninstall_with_no_alias_acts_on_the_record_and_never_detects_the_class() {
  ready_host
  record agent vision
  container_of agent c1 sha256:pinned '[]'
  container_of vision c2 sha256:pinned '[]'
  write_stub nvidia-smi
  write_stub amdgpu_top
  uninstall
  assert_equal status "$status" 0
  assert_equal stdout "$out" "removed agent's container c1
removed vision's container c2
removed image sha256:pinned"
  assert_equal record "$(recorded)" ""
  [[ $(calls) != *nvidia-smi* && $(calls) != *amdgpu_top* ]] || fail "probed the host: $(calls)"
}

test_uninstall_of_a_row_without_a_container_drops_it_from_the_record() {
  ready_host
  record agent
  uninstall agent
  assert_equal status "$status" 0
  assert_equal stdout "$out" "agent has no container"
  assert_equal record "$(recorded)" ""
}

test_uninstall_refuses_an_alias_neither_recorded_nor_a_rows_before_docker() {
  ready_host
  uninstall chat
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: chat is neither in the install record $XDG_STATE_HOME/hosting/aliases nor a row's alias, agent, vision, audio, embedding"
  assert_equal calls "$(calls)" ""
}

test_uninstall_with_an_empty_record_does_nothing() {
  ready_host
  uninstall
  assert_equal status "$status" 0
  assert_equal stdout "$out" "the install record $XDG_STATE_HOME/hosting/aliases holds no alias; nothing to uninstall"
  assert_equal calls "$(calls)" ""
}

test_uninstall_takes_at_most_one_alias() {
  ready_host
  uninstall agent vision
  assert_equal status "$status" 2
}

test_no_engine_command_uses_sudo() {
  ready_host
  write_stub sudo
  image_of vllm/vllm-openai:v0.34.0 sha256:pinned
  engine gb10 install agent
  assert_equal "install status" "$status" 0
  engine gb10 update
  assert_equal "update status" "$status" 0
  uninstall
  assert_equal "uninstall status" "$status" 0
  [[ $(calls) != *sudo* ]] || fail "ran sudo: $(calls)"
}

run_tests
