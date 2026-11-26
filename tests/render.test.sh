#!/usr/bin/env bash
# Tests for hosting profile render (hosting_row in lib/row.sh): each standing row renders exactly
# its tests/render/<alias>.args, the docker command one argument a line, with tailscale and id
# stubbed and HOME at /home/operator; and render refuses before it reads the address or the user.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/hosting.sh
source "$repo/lib/hosting.sh"

goldens=$repo/tests/render

stub_host() {
  write_stub tailscale 'echo 192.0.2.10'
  write_stub id "case \$1 in -u | -g) echo 1000 ;; -un) echo operator ;; esac"
  write_stub docker
}

render() {
  HOME=/home/operator HOSTING_CLASS=$1 run_hosting profile render "${@:2}"
}

test_each_standing_row_renders_its_golden_command() {
  local class alias rendered=()
  stub_host
  for class in gb10 strix-halo; do
    for alias in $(hosting_yq -p toml -o json '.' "$clone/classes/$class/profile.toml" |
      jq -r '.rows[].alias'); do
      render "$class" "$alias"
      assert_equal "$alias status" "$status" 0
      assert_equal "$alias stdout" "$out" "$(<"$goldens/$alias.args")"
      assert_equal "$alias stderr" "$err" ""
      rendered+=("$class:$alias")
    done
  done
  assert_equal "rendered rows" "${rendered[*]}" \
    "gb10:agent gb10:vision strix-halo:audio strix-halo:embedding"
  assert_equal goldens "$(cd "$goldens" && echo *.args)" \
    "agent.args audio.args embedding.args vision.args"
}

test_render_publishes_on_the_tailnet_address_and_touches_no_docker() {
  stub_host
  render gb10 vision
  assert_contains stdout "$out" $'--publish\n192.0.2.10:8001:8001'
  assert_equal calls "$(calls | grep -v '^id ')" "tailscale ip -4"
}

test_a_row_with_a_queue_limit_and_sampling_renders_both_flags() {
  stub_host
  hosting_yq -p toml -o toml -i '(.rows[] | select(.alias == "vision")) |=
    (.sampling = {"source": "The card.", "temperature": 1.0, "top_k": 64} | del(.source.generation_config))' \
    "$clone/classes/gb10/profile.toml"
  render gb10 vision
  assert_equal status "$status" 0
  assert_contains stdout "$out" $'--max-num-queued-reqs\n64\n'
  assert_contains stdout "$out" \
    $'--mm-processor-kwargs.max_soft_tokens\n1120\n--override-generation-config\n{"temperature":1.0,"top_k":64}'
}

test_an_alias_the_class_has_no_row_for_is_refused_before_the_address_is_read() {
  stub_host
  render gb10 audio
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: classes/gb10/profile.toml has no row audio; its aliases are agent vision"
  assert_equal calls "$(calls)" ""
}

test_an_invalid_profile_is_refused_before_the_address_is_read() {
  stub_host
  hosting_yq -p toml -o toml -i '.rows[0].fraction = 1.5' "$clone/classes/gb10/profile.toml"
  render gb10 agent
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: classes/gb10/profile.toml: rows[0].fraction: 1.5 is over 1"
  assert_equal calls "$(calls)" ""
}

test_an_unknown_host_class_is_refused() {
  stub_host
  render gb20 agent
  assert_equal status "$status" 1
  assert_contains stderr "$err" "HOSTING_CLASS is gb20"
  assert_equal calls "$(calls)" ""
}

test_a_host_without_a_tailnet_address_is_refused() {
  stub_host
  write_stub tailscale 'exit 1'
  render gb10 agent
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_contains stderr "$err" "no tailnet IPv4 address"
}

test_render_takes_exactly_one_alias() {
  stub_host
  render gb10
  assert_equal status "$status" 2
  assert_equal stderr "$err" "hosting: profile render takes one alias
usage: hosting profile render <alias>"
  render gb10 agent vision
  assert_equal status "$status" 2
}

run_tests
