#!/usr/bin/env bash
# probe-host runs on one host, fed over ssh by probe.sh, and prints the host's state in labeled
# sections (== name ==), read-only and without root: the system, the GPU driver and its CUDA or
# ROCm version, the ai-hosting clone, the rows through the suite's read-only verbs, each row
# container's running image and arguments beside the command its profile renders and its start's
# warnings, pending package and firmware updates, failed units, and docker's disk with the images
# no container uses, compared by image ID. It never calls sudo, never installs a tool, and changes
# no system state: apt reads its cached lists, and Arch's checkupdates syncs into a temporary
# database of its own, leaving pacman's untouched. A read whose command is absent prints
# "skipped:", and the last section lists every skip.
# See .claude/skills/hosting-upgrades/survey.md
set -u
export GIT_OPTIONAL_LOCKS=0 MISE_EXEC_AUTO_INSTALL=0
clone=$HOME/ai-hosting
skipped=()
docker_ok=0

section() { printf '\n== %s ==\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
skip() {
  printf 'skipped: %s\n' "$1"
  skipped+=("$1")
}

suite() {
  local mise
  mise=$(command -v mise || echo "$HOME/.local/bin/mise")
  if [[ -x $mise ]]; then
    (cd "$clone" && "$mise" exec -- bin/hosting "$@")
  else
    (cd "$clone" && bin/hosting "$@")
  fi
}

print_system() {
  section system
  grep -E '^(PRETTY_NAME|VERSION_ID|BUILD_ID|IMAGE_VERSION)=' /etc/os-release 2>/dev/null ||
    skip "os-release: /etc/os-release unreadable"
  if [[ -r /etc/dgx-release ]]; then
    grep -v -e '^DGX_SERIAL_NUMBER=' -e '^$' /etc/dgx-release
  fi
  have omarchy-version && printf 'omarchy: %s\n' "$(omarchy-version 2>&1)"
  printf 'kernel: %s, booted %s\n' "$(uname -r)" "$(uptime -s 2>/dev/null || echo unknown)"
  if [[ -e /var/run/reboot-required ]]; then
    echo "reboot: pending (/var/run/reboot-required)"
  elif [[ ! -d /usr/lib/modules/$(uname -r) ]]; then
    echo "reboot: pending (the running kernel's module tree is gone)"
  else
    echo "reboot: none pending"
  fi
  printf 'net.ipv4.ip_nonlocal_bind: %s\n' "$(cat /proc/sys/net/ipv4/ip_nonlocal_bind 2>/dev/null)"
  if have docker && docker version --format 'docker: {{.Server.Version}}' 2>&1; then
    docker_ok=1
  else
    skip "docker: absent or not reachable without root"
  fi
}

print_gpu() {
  section gpu
  if have nvidia-smi; then
    printf 'driver: %s\n' "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1 |
      sort -u | paste -sd ' ')"
    printf 'cuda: %s\n' "$(nvidia-smi 2>/dev/null | grep -o 'CUDA Version: [0-9.]*' |
      head -n 1 | cut -d ' ' -f 3)"
    [[ -r /proc/driver/nvidia/version ]] && head -n 1 /proc/driver/nvidia/version
  elif [[ -d /sys/module/amdgpu ]]; then
    printf 'amdgpu: %s\n' \
      "$(cat /sys/module/amdgpu/version 2>/dev/null || echo "in-tree, kernel $(uname -r)")"
    [[ -r /opt/rocm/.info/version ]] && printf 'rocm: %s\n' "$(</opt/rocm/.info/version)"
    have pacman && pacman -Q rocm-core hip-runtime-amd linux-firmware-amdgpu 2>/dev/null |
      sed 's/^/package: /'
  else
    skip "gpu: no nvidia-smi or amdgpu module"
  fi
}

print_clone() {
  section clone
  if ! git -C "$clone" rev-parse --git-dir >/dev/null 2>&1; then
    skip "clone: $clone is not a git clone"
    return
  fi
  printf 'branch: %s\n' "$(git -C "$clone" branch --show-current)"
  printf 'commit: %s\n' "$(git -C "$clone" log -1 --format='%h %cs %s')"
  printf 'tracked files changed: %s\n' \
    "$(git -C "$clone" status --porcelain --untracked-files=no | wc -l)"
  grep '^VLLM_RELEASE=' "$clone/lib/vllm.env" 2>/dev/null || skip "clone: lib/vllm.env unreadable"
}

print_container() {
  docker inspect "$1" --format 'container {{.Name}}: {{.State.Status}}
  started {{.State.StartedAt}}, restart policy {{.HostConfig.RestartPolicy.Name}}
  image {{.Config.Image}} ({{.Image}})
  args {{json .Args}}' 2>&1
  docker image inspect "$(docker inspect --format '{{.Image}}' "$1")" \
    --format '  image created {{.Created}}, digests {{json .RepoDigests}}' 2>&1
  echo "  start warnings:"
  docker logs --since "$(docker inspect --format '{{.State.StartedAt}}' "$1")" "$1" 2>&1 |
    sed '/Application startup complete/q' | grep -iE 'warn|error' | tail -n 10 | sed 's/^/    /'
}

print_rows() {
  section rows
  local verb alias name state=${XDG_STATE_HOME:-$HOME/.local/state}/hosting/aliases
  if [[ ! -x $clone/bin/hosting ]]; then
    skip "rows: $clone/bin/hosting absent"
    return
  fi
  printf 'recorded aliases: %s\n' "$(paste -sd ' ' "$state" 2>/dev/null || echo none)"
  for verb in "engine status" "engine models" "engine memory" "model list"; do
    printf -- '-- hosting %s --\n' "$verb"
    # shellcheck disable=SC2086 # Each verb is two words, split on purpose.
    suite $verb 2>&1
  done
  ((docker_ok)) || return
  while read -r alias name; do
    [[ -n $alias ]] || continue
    printf -- '-- row %s --\n' "$alias"
    print_container "$name"
    suite engine metrics "$alias" 2>&1 | sed 's/^/  /'
    echo "  profile renders:"
    suite profile render "$alias" 2>&1 | sed 's/^/    /'
  done < <(docker ps -a --filter label=ai-hosting.row \
    --format '{{.Label "ai-hosting.row"}} {{.Names}}' 2>/dev/null)
}

print_updates() {
  section updates
  local lines=() out rc synced='checkupdates, synced into a temporary database'
  if have apt; then
    printf 'apt lists: refreshed %s; the probe never refreshes them\n' \
      "$(date -r /var/lib/apt/lists '+%F %T' 2>/dev/null || echo never)"
    mapfile -t lines < <(apt list --upgradable 2>/dev/null | grep '/')
    printf 'pending: %d packages (apt, from the cached lists)\n' "${#lines[@]}"
    ((${#lines[@]})) && printf 'update: %s\n' "${lines[@]}"
  elif have checkupdates; then
    out=$(timeout 90 checkupdates 2>&1)
    rc=$?
    case $rc in
      0)
        mapfile -t lines <<<"$out"
        printf 'pending: %d packages (%s)\n' "${#lines[@]}" "$synced"
        printf 'update: %s\n' "${lines[@]}"
        ;;
      2) echo "pending: 0 packages ($synced)" ;;
      *) skip "updates: checkupdates failed (exit $rc): $(head -n 1 <<<"$out")" ;;
    esac
  else
    skip "updates: no apt or checkupdates"
  fi
}

print_firmware_updates() {
  section firmware-updates
  if ! have fwupdmgr; then
    skip "firmware updates: fwupdmgr absent"
    return
  fi
  timeout 60 fwupdmgr get-updates --no-unreported-check --no-metadata-check 2>&1 |
    grep -viE 'serial|guid|device ?id|checksum' | sed '/^\s*$/d' | head -n 40
}

print_units() {
  section units
  if ! have systemctl; then
    skip "units: systemctl absent"
    return
  fi
  local scope flag=()
  for scope in system user; do
    [[ $scope == user ]] && flag=(--user)
    printf 'systemd (%s): %s\n' "$scope" "$(systemctl "${flag[@]}" is-system-running 2>&1)"
    systemctl "${flag[@]}" --failed --no-legend --plain 2>/dev/null |
      awk -v s="$scope" 'NF { print "failed (" s "): " $1, $3, $4 }'
  done
}

print_docker_disk() {
  section docker-disk
  if ! ((docker_ok)); then
    skip "docker disk: docker unavailable"
    return
  fi
  docker system df 2>&1
  printf 'dangling images: %s\n' \
    "$(docker image ls -q -f dangling=true 2>/dev/null | sort -u | wc -l)"
  local used
  used=$(docker ps -aq 2>/dev/null | xargs -r docker inspect --format '{{.Image}}' 2>/dev/null |
    sort -u)
  echo "images no container uses:"
  docker image ls -f dangling=false --no-trunc \
    --format '{{.ID}} {{.Repository}}:{{.Tag}} {{.Size}}' 2>/dev/null |
    while read -r id ref size; do
      grep -qxF "$id" <<<"$used" || printf '  %s %s\n' "$ref" "$size"
    done
}

print_skipped() {
  section skipped
  if ((${#skipped[@]})); then
    printf '%s\n' "${skipped[@]}"
  else
    echo none
  fi
}

{
  print_system
  print_gpu
  print_clone
  print_rows
  print_updates
  print_firmware_updates
  print_units
  print_docker_disk
  print_skipped
} </dev/null 2>&1
