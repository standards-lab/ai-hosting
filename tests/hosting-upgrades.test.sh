#!/usr/bin/env bash
# Tests for the hosting-upgrades skill's scripts, on a copy of the skill and the host descriptors
# with ssh stubbed: what probe.sh refuses before it reaches a host, the ssh command it runs and the
# tailnet identifiers it redacts, what probe-host.sh reads with docker, apt, and the GPU tools
# stubbed and a fake system tree, and how setup.sh marks each mode's rules present or missing
# against the settings files, for every host or one, without writing any.
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

rename_short_name() {
  sed -i "s/^\`$1\`\$/\`$2\`/" "$clone/docs/hosts/$1.md"
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
  rename_short_name gb10-1 gb10-1.example-tailnet.ts.net
  write_stub ssh
  run "$clone/$skill/scripts/probe.sh" gb10-1
  assert_equal status "$status" 2
  assert_contains stderr "$err" "is not a short host name"
  assert_equal "ssh calls" "$(calls)" ""
}

test_probe_runs_the_host_probe_over_ssh_by_short_name() {
  copy_skill
  rename_short_name gb10-1 spark-1
  write_stub ssh "cat >$(printf %q "$tmp/stdin")"
  run "$clone/$skill/scripts/probe.sh" gb10-1
  assert_equal status "$status" 0
  assert_equal "ssh calls" "$(calls)" "ssh -o BatchMode=yes -- spark-1 bash -s"
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
        "INFO JIT monitor will use mode=warn." "INFO config: on_error=raise" \
        "warning: lowercase" "INFO Application startup complete." "ERROR after the start" ;;
  esac'
  probe_host
  assert_contains stdout "$out" "-- row vision --"
  assert_contains stdout "$out" "  start warnings:
    WARNING the cache is cold
"
  [[ $out != *"ERROR after the start"* ]] || fail "a warning after the start is listed: $out"
  [[ $out != *mode=warn* && $out != *on_error* && $out != *lowercase* ]] ||
    fail "a line that is not at WARNING or ERROR is listed: $out"
  [[ $out != *dropped* ]] || fail "the probe says it dropped a line: $out"
  [[ $out != *"  health "* ]] || fail "the probe prints docker's health: $out"
}

test_probe_host_says_how_many_start_warnings_it_dropped() {
  mkdir -p "$HOME/ai-hosting/bin"
  printf '#!/usr/bin/env bash\n' >"$HOME/ai-hosting/bin/hosting"
  chmod +x "$HOME/ai-hosting/bin/hosting"
  docker_body='case "$*" in
    "version --format"*) echo "docker: 29.0.0" ;;
    "ps -a --filter label=ai-hosting.row"*) echo "agent vllm-agent" ;;
    "inspect --format {{.State.StartedAt}} vllm-agent") echo 2026-11-25T00:00:00Z ;;
    "logs --since"*) printf "ERROR line %s\n" {1..13} ;;
  esac'
  probe_host
  assert_contains stdout "$out" "  start warnings:
    (3 earlier lines dropped, the last 10 shown)
    ERROR line 4
"
  assert_contains stdout "$out" "    ERROR line 13"
  [[ $out != *"ERROR line 3"$'\n'* ]] || fail "a dropped line is listed: $out"
}

test_probe_host_prints_the_nvidia_driver_and_cuda_version() {
  write_stub nvidia-smi 'case "$*" in
    *--query-gpu*) echo 580.95.05 ;;
    *) echo "| NVIDIA-SMI 580.95.05   Driver Version: 580.95.05   CUDA Version: 13.0 |" ;;
  esac'
  mkdir -p "$sysroot/proc"
  printf '%s\n' "MemTotal:       127535356 kB" "MemFree: 1 kB" "MemAvailable:    65524180 kB" \
    >"$sysroot/proc/meminfo"
  probe_host
  assert_contains stdout "$out" "== gpu ==
driver: 580.95.05
cuda, the highest the driver supports, not the image's: 13.0
memory: MemTotal 121.63 GiB
memory: MemAvailable 62.49 GiB
skipped: memory: nvidia-smi gives no memory.total [580.95.05]"
}

test_probe_host_reads_strix_halo_rocm_gfx_target_and_gtt_and_skips_what_it_lacks() {
  mkdir -p "$sysroot/sys/module/amdgpu" "$sysroot/sys/class/drm/card1/device" \
    "$sysroot/sys/class/drm/card1-DP-1/device" \
    "$sysroot/sys/class/kfd/kfd/topology/nodes/0" "$sysroot/sys/class/kfd/kfd/topology/nodes/1"
  echo 120259084288 >"$sysroot/sys/class/drm/card1/device/mem_info_gtt_total"
  echo 536870912 >"$sysroot/sys/class/drm/card1/device/mem_info_vram_total"
  echo 1 >"$sysroot/sys/class/drm/card1-DP-1/device/mem_info_gtt_total"
  printf '%s\n' "cpu_cores_count 32" "gfx_target_version 0" \
    >"$sysroot/sys/class/kfd/kfd/topology/nodes/0/properties"
  printf '%s\n' "simd_count 80" "gfx_target_version 110501" \
    >"$sysroot/sys/class/kfd/kfd/topology/nodes/1/properties"
  write_stub pacman 'case "$*" in
    "-Q linux-firmware-amdgpu") echo "linux-firmware-amdgpu 20260916-1" ;;
    *) exit 1 ;;
  esac'
  probe_host
  assert_contains stdout "$out" "gfx target: gfx1151 (gfx_target_version 110501)
the row runs its image's ROCm SDK; the host's ROCm is read below
skipped: host's rocm: no /opt/rocm/.info/version
skipped: host's package: rocm-core not installed
skipped: host's package: hip-runtime-amd not installed
host's package: linux-firmware-amdgpu 20260916-1"
  assert_contains stdout "$out" "memory: amdgpu GTT total 112.00 GiB (/sys/class/drm/card1/device)
memory: amdgpu VRAM total 0.50 GiB (/sys/class/drm/card1/device)"
  [[ $out != *card1-DP-1* ]] || fail "a connector is read as a card: $out"
  assert_contains stdout "$out" "== skipped ==
host's rocm: no /opt/rocm/.info/version
host's package: rocm-core not installed
host's package: hip-runtime-amd not installed
memory: no MemTotal in /proc/meminfo"
}

test_probe_host_names_each_apt_updates_source_package() {
  write_stub apt 'printf "%s\n" "Listing..." \
    "libexpat1/noble-updates,noble-security 2.6.1-2ubuntu0.7 arm64 [upgradable from: 2.6.1-2ubuntu0.6]" \
    "libudev1/noble-updates 255.4-1ubuntu8.19 arm64 [upgradable from: 255.4-1ubuntu8.18]"'
  write_stub dpkg-query 'printf "%s\n" "libexpat1 expat" "libudev1 systemd" "libudev1 systemd"'
  run bash "$repo/$skill/scripts/probe-host.sh"
  assert_contains stdout "$out" "pending: 2 packages (apt, from the cached lists)
update: libexpat1/noble-updates,noble-security 2.6.1-2ubuntu0.7 arm64 [upgradable from: 2.6.1-2ubuntu0.6]; source package expat
update: libudev1/noble-updates 255.4-1ubuntu8.19 arm64 [upgradable from: 255.4-1ubuntu8.18]; source package systemd"
  assert_contains "dpkg-query call" "$(calls)" "dpkg-query -W -f=\${Package} \${source:Package}\n libexpat1 libudev1"
}

test_setup_marks_rules_present_by_exact_prefix_glob_and_bare_tool() {
  copy_skill
  allow settings.json "Bash(mise run:*)" "Edit(.state/**)"
  allow settings.local.json "WebFetch" "Bash(gh release view *)" \
    "Bash(.claude/skills/hosting-upgrades/scripts/probe.sh gb10-1)"
  setup survey
  assert_equal status "$status" 0
  assert_contains stdout "$out" "Survey's rules: 6 of 25 present."
  assert_contains stdout "$out" '  present  "Bash(mise run currency)"  granted in .claude/settings.json: "Bash(mise run:*)"'
  assert_contains stdout "$out" '  present  "Edit(.state/upgrades/**)"  granted in .claude/settings.json: "Edit(.state/**)"'
  assert_contains stdout "$out" '  present  "WebFetch"  granted in .claude/settings.local.json: "WebFetch"'
  assert_contains stdout "$out" '  present  "Bash(gh release view *)"'
  assert_contains stdout "$out" '  present  "Bash(.claude/skills/hosting-upgrades/scripts/probe.sh gb10-1)"'
  assert_contains stdout "$out" '  missing  "Bash(.claude/skills/hosting-upgrades/scripts/probe.sh gb10-2)"'
  assert_contains stdout "$out" '  missing  "WebSearch"'
  assert_contains stdout "$out" '  missing  "Bash(gh release list *)"'
  assert_contains stdout "$out" "Add to .claude/settings.json, under permissions.allow:"
  assert_contains stdout "$out" '  "WebSearch"'
}

test_setup_reads_the_user_settings_and_names_them() {
  copy_skill
  mkdir -p "$HOME/.claude"
  jq -n '{permissions: {allow: ["WebSearch"]}}' >"$HOME/.claude/settings.json"
  setup survey
  assert_contains stdout "$out" '  present  "WebSearch"  granted in ~/.claude/settings.json: "WebSearch"'
}

test_setup_given_a_host_counts_only_its_probe_and_ping_rules() {
  copy_skill
  rename_short_name gb10-2 spark-2
  run "$clone/$skill/scripts/setup.sh" measure gb10-2
  assert_equal status "$status" 0
  assert_contains stdout "$out" "Survey's rules, which measure needs too: 0 of 22 present."
  assert_contains stdout "$out" "Measure's own rules: 0 of 2 present."
  assert_contains stdout "$out" '"Bash(.claude/skills/hosting-upgrades/scripts/probe.sh gb10-2)"'
  assert_contains stdout "$out" '"Bash(tailscale ping -c 1 spark-2)"'
  [[ $out != *gb10-1* && $out != *framework* ]] || fail "setup names another host's rule: $out"
}

test_setup_refuses_a_host_with_no_descriptor_before_reading_the_settings() {
  copy_skill
  echo 'not json' >"$clone/.claude/settings.json"
  for host in gb10-3 template -oProxyCommand=true; do
    run "$clone/$skill/scripts/setup.sh" survey "$host"
    assert_equal "$host status" "$status" 2
    assert_contains "$host stderr" "$err" "the hosts with a descriptor are: framework-2 framework gb10-1 gb10-2"
    [[ $err != *jq* && $err != *parse* ]] || fail "setup read the settings for $host: $err"
    assert_equal "$host stdout" "$out" ""
  done
}

test_setup_skips_the_template_and_names_hosts_by_short_name() {
  copy_skill
  rename_short_name gb10-2 spark-2
  run "$clone/$skill/scripts/setup.sh" measure
  assert_contains stdout "$out" '"Bash(tailscale ping -c 1 framework)"'
  assert_contains stdout "$out" '"Bash(tailscale ping -c 1 spark-2)"'
  [[ $out != *"tailscale ping -c 1 gb10-2"* ]] || fail "setup pings a descriptor by file name: $out"
  [[ $out != *template* ]] || fail "setup names the template as a host: $out"
}

test_setup_names_the_probe_by_descriptor_file_name() {
  copy_skill
  rename_short_name gb10-2 spark-2
  run "$clone/$skill/scripts/setup.sh" survey
  assert_contains stdout "$out" '"Bash(.claude/skills/hosting-upgrades/scripts/probe.sh gb10-2)"'
  [[ $out != *"probe.sh spark-2"* ]] || fail "setup names the probe by short name: $out"
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
