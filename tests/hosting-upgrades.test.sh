#!/usr/bin/env bash
# Tests for the hosting-upgrades skill's scripts, on a copy of the skill and the host descriptors
# with ssh stubbed: what probe.sh refuses before it reaches a host, the ssh command it runs and the
# tailnet identifiers it redacts, what probe-host.sh reads with docker and the GPU tools stubbed,
# and how setup.sh marks each mode's rules present or missing against the settings files without
# writing any.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

skill=.claude/skills/hosting-upgrades

copy_skill() {
  mkdir -p "$clone/.claude/skills" "$clone/docs"
  cp -R "$repo/$skill" "$clone/.claude/skills/"
  cp -R "$repo/docs/hosts" "$clone/docs/"
}

probe() {
  copy_skill
  write_stub ssh "cat >$(printf %q "$tmp/stdin"); ${ssh_body:-}"
  run "$clone/$skill/scripts/probe.sh" "$@"
}

probe_host() {
  write_stub docker "${docker_body:-exit 1}"
  write_stub apt
  write_stub checkupdates 'exit 2'
  write_stub fwupdmgr
  write_stub systemctl
  write_stub mise 'shift 2; exec "$@"'
  run bash "$repo/$skill/scripts/probe-host.sh"
}

setup() {
  copy_skill
  run "$clone/$skill/scripts/setup.sh" "$@"
}

allow() {
  local file=$clone/.claude/$1
  shift
  jq -n '{permissions: {allow: $ARGS.positional}}' --args "$@" >"$file"
}

test_probe_refuses_no_host_and_lists_the_descriptors() {
  probe
  assert_equal status "$status" 2
  assert_contains stderr "$err" "usage: probe.sh <host>"
  assert_contains stderr "$err" "framework-2 framework gb10-1 gb10-2"
  assert_equal "ssh calls" "$(calls)" ""
}

test_probe_refuses_two_hosts() {
  probe gb10-1 gb10-2
  assert_equal status "$status" 2
  assert_equal "ssh calls" "$(calls)" ""
}

test_probe_refuses_an_ssh_option() {
  probe -oProxyCommand=true
  assert_equal status "$status" 2
  assert_contains stderr "$err" "is not a short host name"
  assert_equal "ssh calls" "$(calls)" ""
}

test_probe_refuses_a_magicdns_name() {
  probe gb10-1.example-tailnet.ts.net
  assert_equal status "$status" 2
  assert_contains stderr "$err" "is not a short host name"
  assert_equal "ssh calls" "$(calls)" ""
}

test_probe_refuses_the_template() {
  probe template
  assert_equal status "$status" 2
  assert_contains stderr "$err" "template.md is the descriptor template"
  assert_equal "ssh calls" "$(calls)" ""
}

test_probe_refuses_a_host_with_no_descriptor() {
  probe gb10-3
  assert_equal status "$status" 2
  assert_contains stderr "$err" "no descriptor docs/hosts/gb10-3.md"
  assert_equal "ssh calls" "$(calls)" ""
}

test_probe_refuses_a_descriptor_whose_short_name_is_not_short() {
  copy_skill
  # shellcheck disable=SC2016 # The backticks are the descriptor's, matched literally.
  sed -i 's/^`gb10-1`$/`gb10-1.example-tailnet.ts.net`/' "$clone/docs/hosts/gb10-1.md"
  write_stub ssh
  run "$clone/$skill/scripts/probe.sh" gb10-1
  assert_equal status "$status" 2
  assert_contains stderr "$err" "is not a short host name"
  assert_equal "ssh calls" "$(calls)" ""
}

test_probe_runs_the_host_probe_over_ssh_by_short_name() {
  probe gb10-1
  assert_equal status "$status" 0
  assert_equal "ssh calls" "$(calls)" "ssh -o BatchMode=yes -- gb10-1 bash -s"
  assert_equal "the script ssh reads" "$(<"$tmp/stdin")" \
    "$(<"$repo/$skill/scripts/probe-host.sh")"
}

test_probe_redacts_tailnet_addresses_and_magicdns_names() {
  ssh_body='echo "bind 100.101.2.3:8000,100.64.0.1 and fd7a:115c:a1e0::7 at gb10-1.example-tailnet.ts.net; lan 192.168.1.4 kept"'
  probe gb10-1
  assert_equal stdout "$out" \
    "bind [tailnet-ipv4]:8000,[tailnet-ipv4] and [tailnet-ipv6] at [magicdns-name]; lan 192.168.1.4 kept"
}

test_probe_exits_with_ssh_status() {
  ssh_body='exit 255'
  probe gb10-1
  assert_equal status "$status" 255
}

test_probe_host_lists_the_images_no_container_uses_by_image_id() {
  docker_body='case "$*" in
    "version --format"*) echo "docker: 29.0.0" ;;
    "ps -aq") printf "%s\n" c1 c2 ;;
    "inspect --format {{.Image}} c1 c2") printf "%s\n" sha256:aaa sha256:bbb ;;
    "image ls -f dangling=false --no-trunc"*)
      printf "%s\n" "sha256:aaa gateway-grafana:latest 1.89GB" \
        "sha256:bbb vllm/vllm-openai:v0.34.0 20GB" \
        "sha256:ccc cr.agentgateway.dev/agentgateway:v1.7.0 142MB" ;;
  esac'
  probe_host
  assert_contains stdout "$out" "images no container uses:
  cr.agentgateway.dev/agentgateway:v1.7.0 142MB"
  [[ $out != *gateway-grafana* && $out != *"vllm/vllm-openai:v0.34.0 20GB"* ]] ||
    fail "an image a container uses is listed: $out"
}

test_probe_host_prints_each_rows_start_warnings_without_health() {
  mkdir -p "$HOME/ai-hosting/bin"
  printf '#!/usr/bin/env bash\necho "hosting $*"\n' >"$HOME/ai-hosting/bin/hosting"
  chmod +x "$HOME/ai-hosting/bin/hosting"
  docker_body='case "$*" in
    "version --format"*) echo "docker: 29.0.0" ;;
    "ps -a --filter label=ai-hosting.row"*) echo "vision vllm-vision" ;;
    "inspect vllm-vision --format"*) echo "container /vllm-vision: running" ;;
    "inspect --format {{.Image}} vllm-vision") echo sha256:aaa ;;
    "inspect --format {{.State.StartedAt}} vllm-vision") echo 2026-11-25T00:00:00Z ;;
    "logs --since 2026-11-25T00:00:00Z vllm-vision")
      printf "%s\n" "INFO starting" "WARNING the cache is cold" \
        "INFO Application startup complete." "ERROR after the start" ;;
  esac'
  probe_host
  assert_contains stdout "$out" "-- row vision --"
  assert_contains stdout "$out" "  start warnings:
    WARNING the cache is cold"
  [[ $out != *"ERROR after the start"* ]] || fail "a warning after the start is listed: $out"
  [[ $out != *"  health "* ]] || fail "the probe prints docker's health: $out"
}

test_probe_host_prints_the_nvidia_driver_and_cuda_version() {
  write_stub nvidia-smi 'case "$*" in
    *--query-gpu*) echo 580.95.05 ;;
    *) echo "| NVIDIA-SMI 580.95.05   Driver Version: 580.95.05   CUDA Version: 13.0 |" ;;
  esac'
  probe_host
  assert_contains stdout "$out" "== gpu ==
driver: 580.95.05
cuda: 13.0"
}

test_setup_marks_rules_present_by_exact_prefix_glob_and_bare_tool() {
  copy_skill
  allow settings.json "Bash(mise run:*)" "Edit(.state/**)"
  allow settings.local.json "WebFetch" "Bash(gh release view *)" \
    "Bash(.claude/skills/hosting-upgrades/scripts/probe.sh gb10-1)"
  setup survey
  assert_equal status "$status" 0
  assert_contains stdout "$out" "Survey's rules: 6 of 25 present."
  assert_contains stdout "$out" '  present  "Bash(mise run currency)"'
  assert_contains stdout "$out" '  present  "Edit(.state/upgrades/**)"'
  assert_contains stdout "$out" '  present  "WebFetch"'
  assert_contains stdout "$out" '  present  "Bash(gh release view *)"'
  assert_contains stdout "$out" '  present  "Bash(.claude/skills/hosting-upgrades/scripts/probe.sh gb10-1)"'
  assert_contains stdout "$out" '  missing  "Bash(.claude/skills/hosting-upgrades/scripts/probe.sh gb10-2)"'
  assert_contains stdout "$out" '  missing  "WebSearch"'
  assert_contains stdout "$out" '  missing  "Bash(gh release list *)"'
  assert_contains stdout "$out" "Add to .claude/settings.json, under permissions.allow:"
  assert_contains stdout "$out" '  "WebSearch"'
}

test_setup_skips_the_template_and_names_hosts_by_short_name() {
  setup measure
  assert_contains stdout "$out" '"Bash(tailscale ping -c 1 framework)"'
  assert_contains stdout "$out" '"Bash(tailscale ping -c 1 gb10-2)"'
  [[ $out != *template* ]] || fail "setup names the template as a host: $out"
}

test_setup_measure_prints_survey_rules_then_its_own() {
  setup measure
  assert_contains stdout "$out" "Survey's rules, which measure needs too: 0 of 25 present."
  assert_contains stdout "$out" "Measure's own rules: 0 of 5 present."
}

test_setup_with_every_rule_present_says_so() {
  copy_skill
  allow settings.json "Bash" "WebFetch" "WebSearch" "Edit"
  setup
  assert_contains stdout "$out" "Every rule is present."
  [[ $out != *missing* ]] || fail "a rule is marked missing: $out"
}

test_setup_writes_no_settings() {
  setup
  assert_equal status "$status" 0
  [[ ! -e $clone/.claude/settings.json && ! -e $clone/.claude/settings.local.json ]] ||
    fail "setup wrote a settings file"
}

test_setup_refuses_an_unknown_mode() {
  setup apply
  assert_equal status "$status" 2
  assert_contains stderr "$err" "unknown mode apply"
  assert_equal stdout "$out" ""
}

run_tests
