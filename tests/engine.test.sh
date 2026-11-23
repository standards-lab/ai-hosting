#!/usr/bin/env bash
# Tests for hosting engine install, update, and uninstall (lib/engine.sh), with docker, hf, and
# tailscale stubbed to log their calls, docker answering from a fake Docker state, and a fake system
# tree holding the sysctl and the CDI spec: each refusal comes before any docker call, and each
# command issues the docker calls its row needs and keeps the install record.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

# Stubs the commands the engine verbs run, on a host that passes the preflight: docker answering
# from the fake Docker state under HOSTING_TEST_DOCKER (container_of and image_of write it), hf
# signed in, tailscale giving 192.0.2.10, net.ipv4.ip_nonlocal_bind at 1, and a CDI spec whose
# every file is present.
ready_host() {
  export HOSTING_TEST_DOCKER=$tmp/docker
  mkdir -p "$HOSTING_TEST_DOCKER"/{ls,container,image}
  write_stub docker "$(
    cat <<'EOF'
key=${*: -1}
key=${key//\//_}
case "$1 $2" in
  "container ls") cat "$HOSTING_TEST_DOCKER/ls/$key" 2>/dev/null || true ;;
  "container inspect") cat "$HOSTING_TEST_DOCKER/container/$key" ;;
  "image inspect") cat "$HOSTING_TEST_DOCKER/image/$key" ;;
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

# Sets net.ipv4.ip_nonlocal_bind in the fake system tree.
nonlocal_bind() {
  mkdir -p "$sysroot/proc/sys/net/ipv4"
  echo "$1" >"$sysroot/proc/sys/net/ipv4/ip_nonlocal_bind"
}

# Gives the fake Docker state a container with the row label of the alias given:
# container_of <alias> <container id> <image id> <command as JSON>.
container_of() {
  echo "$2" >"$HOSTING_TEST_DOCKER/ls/label=ai-hosting.row=$1"
  echo "$2" >>"$HOSTING_TEST_DOCKER/ls/ancestor=$3"
  printf '%s\n%s\n' "$3" "$4" >"$HOSTING_TEST_DOCKER/container/$2"
}

# Gives the fake Docker state an image: image_of <reference> <image id>.
image_of() {
  echo "$2" >"$HOSTING_TEST_DOCKER/image/${1//\//_}"
}

# Writes the install record, one alias given a line.
record() {
  mkdir -p "$XDG_STATE_HOME/hosting"
  printf '%s\n' "$@" >"$XDG_STATE_HOME/hosting/aliases"
}

recorded() {
  cat "$XDG_STATE_HOME/hosting/aliases" 2>/dev/null
}

docker_calls() {
  calls | grep '^docker' || true
}

# Prints the docker run command hosting profile render prints for the row given, on one line, as
# the docker stub logs it: rendered <class> <alias>.
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
  assert_equal "docker calls" "$(docker_calls)" "docker container ls --all --quiet --filter label=ai-hosting.row=agent
docker pull vllm/vllm-openai:v0.34.0
$(rendered gb10 agent)"
  assert_equal record "$(recorded)" agent
}

test_install_builds_a_rows_own_image() {
  ready_host
  engine strix-halo install audio
  assert_equal status "$status" 0
  assert_contains "docker calls" "$(docker_calls)" \
    "docker build --tag ai-hosting/vllm-openai-rocm-audio:v0.34.0 $clone/images/vllm-openai-rocm-audio"
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
  assert_equal "docker calls" "$(docker_calls)" "docker container ls --all --quiet --filter label=ai-hosting.row=agent"
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
  assert_equal stderr "$err" "hosting: the rows that would stand on this host reserve more than all its GPU's memory: agent 0.80, vision 0.40 sum to 1.2, over 1"
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
  hosting_yq_in_clone '.rows[0].fraction = 1.5' gb10
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

# Edits the clone's profile of the class given with the yq expression given:
# hosting_yq_in_clone <expression> <class>.
hosting_yq_in_clone() {
  (
    # shellcheck source=lib/hosting.sh
    source "$clone/lib/hosting.sh"
    hosting_yq -p toml -o toml -i "$1" "$clone/classes/$2/profile.toml"
  )
}

run_tests
