#!/usr/bin/env bash
# What the rows on a host are doing, read and never changed: each labeled container's state, where
# it listens, and whether it is stranded; its health, served model, and metrics, read from the row
# over HTTP; and the GPU memory each row's processes hold, read per class. Engine status, models,
# metrics, and memory consume it. Sourced by lib/hosting.sh. See context/hosting-suite.md and
# context/engines.md.

# Prints one tab-separated line a container carrying a row label, sorted by alias: its alias, ID,
# name, state, the address it is configured to listen on as <host>:<port> ("-" when it binds
# none), the count of its published ports, and the count of its networks. Prints nothing when the
# host has none, and fails when Docker does.
hosting_observe_rows() {
  local ids
  ids=$(docker container ls --all --quiet --filter "label=$HOSTING_ROW_LABEL") || return
  [[ -n $ids ]] || return 0
  # shellcheck disable=SC2086 # One container ID a word.
  docker container inspect $ids | jq -r --arg label "$HOSTING_ROW_LABEL" '.[]
    | ([(.HostConfig.PortBindings // {})[] | (. // [])[]] | first) as $bind
    | [.Config.Labels[$label], .Id[0:12], (.Name | ltrimstr("/")), .State.Status,
        (if $bind then "\(if ($bind.HostIp // "") == "" then "127.0.0.1" else $bind.HostIp end):\($bind.HostPort)"
         else "-" end),
        ([(.NetworkSettings.Ports // {})[] | (. // [])[]] | length),
        (.NetworkSettings.Networks // {} | length)]
    | @tsv' | sort
}

# Prints the body the row at the address given answers on the path given: hosting_observe_get
# <host:port> <path>. Fails when the row doesn't answer it.
hosting_observe_get() {
  curl --silent --fail --max-time 5 "http://$1$2"
}

# Prints the host PIDs of the processes in the running container with the ID given, one a line.
hosting_observe_pids() {
  docker top "$1" -eo pid | awk 'NR > 1 { print $1 }'
}

# Prints the host's MemAvailable from HOSTING_SYSROOT's /proc/meminfo, in GiB to two places, or
# "unreadable".
hosting_observe_mem_available() {
  awk '/^MemAvailable:/ { printf "%.2f GiB\n", $2 / 2^20; found = 1 }
    END { if (!found) print "unreadable" }' "${HOSTING_SYSROOT:-}/proc/meminfo" 2>/dev/null ||
    echo unreadable
}

# Prints the GPU memory each row's processes hold, on the class's source (hosting_per_class), from
# the rows given as hosting_observe_rows prints them, then each GPU process no row holds, then the
# pool the rows share.
hosting_observe_memory() {
  hosting_per_class hosting_observe_memory "$@"
}

# Joins the GPU memory read given, one "<pid> <figure>..." line a process, to the rows given,
# hosting_observe_rows's lines, by their containers' host PIDs, printing a table under the column
# names given: hosting_observe_join <read> <rows> <column>... One line a row, its alias, container,
# and the sum of each figure over its processes, a stopped row's figures "-", then one "pid <pid>"
# line, with its figures, for each process no row holds.
hosting_observe_join() {
  local alias id name state pids
  while IFS=$'\t' read -r alias id name state _; do
    [[ -n $alias ]] || continue
    pids=-
    [[ $state != running ]] || pids=$(hosting_observe_pids "$id" | paste -sd, -)
    printf '%s %s %s\n' "$alias" "$name" "${pids:--}"
  done <<<"$2" | awk -v columns="$(IFS=,; echo "${*:3}")" '
    function row(a, b, line, j) {
      line = sprintf("%-12s %-20s", a, b)
      for (j = 1; j <= width; j++) line = line sprintf(" %10s", figure[j])
      print line
    }
    NR == FNR {
      if (NF < 2) next
      pid[++np] = $1
      width = NF - 1
      for (j = 2; j <= NF; j++) mem[$1, j - 1] = $j
      next
    }
    !header++ {
      width = split(columns, figure, ",")
      row("ROW", "CONTAINER")
    }
    {
      if ($3 == "-") {
        for (j = 1; j <= width; j++) figure[j] = "-"
        row($1, $2)
        next
      }
      n = split($3, held, ",")
      for (j = 1; j <= width; j++) figure[j] = 0
      for (k = 1; k <= n; k++) {
        owned[held[k]] = 1
        for (j = 1; j <= width; j++) figure[j] += mem[held[k], j]
      }
      row($1, $2)
    }
    END {
      if (!header++) {
        width = split(columns, figure, ",")
        row("ROW", "CONTAINER")
      }
      for (i = 1; i <= np; i++) {
        if (pid[i] in owned) continue
        for (j = 1; j <= width; j++) figure[j] = mem[pid[i], j]
        row("pid " pid[i], "-")
      }
    }' <(printf '%s\n' "$1") -
}

# On a GB10, each process's GPU memory is nvidia-smi's used_memory, and the pool is the host's
# MemAvailable, since the GPU allocates from system memory. It joins nvidia-smi's processes to each
# row's container by docker top's host PIDs.
hosting_observe_memory_gb10() {
  local read
  read=$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits |
    tr -d ' ' | tr , ' ') || return
  hosting_observe_join "$read" "$1" "GPU MiB"
  echo "pool: MemAvailable $(hosting_observe_mem_available)"
}

# On a Strix Halo, each process's GPU memory is amdgpu_top's VRAM and GTT, and the pool is amdgpu's
# GTT, with the host's MemAvailable beside it, the memory GTT doesn't cover. It reads amdgpu_top -p
# and GTT from HOSTING_SYSROOT's sysfs.
hosting_observe_memory_strix_halo() {
  local read card gtt=unreadable
  read=$(timeout 30 amdgpu_top -p --no-pc |
    sed -nE 's/.*\( *([0-9]+)\), ctxs +[0-9]+, VRAM +([0-9]+) MiB.*GTT +([0-9]+) MiB.*/\1 \2 \3/p') ||
    return
  hosting_observe_join "$read" "$1" "VRAM MiB" "GTT MiB"
  for card in "${HOSTING_SYSROOT:-}"/sys/class/drm/card*/device; do
    [[ -r $card/mem_info_gtt_used && -r $card/mem_info_gtt_total ]] || continue
    gtt=$(awk -v u="$(<"$card/mem_info_gtt_used")" -v t="$(<"$card/mem_info_gtt_total")" \
      'BEGIN { printf "%.2f GiB of %.2f GiB\n", u / 2^30, t / 2^30 }')
    break
  done
  echo "pool: GTT used $gtt; MemAvailable $(hosting_observe_mem_available)"
}

# Prints a summary of the vLLM Prometheus metrics given on stdin, each metric summed over its
# label sets, "-" for one the row doesn't report: requests running and waiting, the KV cache's
# usage, the prompt and generation tokens, the finished requests, and the preemptions.
hosting_observe_metrics() {
  awk '
    /^vllm:/ {
      name = $1
      sub(/\{.*/, "", name)
      value[name] += $NF
      seen[name] = 1
    }
    function show(label, name, scale, suffix) {
      if (name in seen) printf "%-20s %s%s\n", label ":", value[name] * scale, suffix
      else printf "%-20s -\n", label ":"
    }
    END {
      show("requests running", "vllm:num_requests_running", 1, "")
      show("requests waiting", "vllm:num_requests_waiting", 1, "")
      show("KV cache usage", "vllm:kv_cache_usage_perc", 100, "%")
      show("prompt tokens", "vllm:prompt_tokens_total", 1, "")
      show("generation tokens", "vllm:generation_tokens_total", 1, "")
      show("requests finished", "vllm:request_success_total", 1, "")
      show("preemptions", "vllm:num_preemptions_total", 1, "")
    }'
}

# Prints a table of the rows on the host, each labeled container and each recorded alias with
# none: its alias, container, state, health (its /health answering, for a running row), and the
# address it is configured to listen on. Then flags each stranded row, a running container on no
# network or publishing no port, printing the command that recovers it.
# Fails when any row is not running and healthy, or none could be read.
hosting_observe_status() {
  local rows alias id name state address published networks health bound fail=0 flags=()
  rows=$(hosting_observe_rows) || return
  printf '%-12s %-20s %-10s %-10s %s\n' ROW CONTAINER STATE HEALTH ADDRESS
  while IFS=$'\t' read -r alias id name state address published networks; do
    [[ -n $alias ]] || continue
    health=-
    if [[ $state == running ]]; then
      health=healthy
      if [[ $address == - ]] || ! hosting_observe_get "$address" /health >/dev/null; then
        health=unhealthy
      fi
    fi
    [[ $health == healthy ]] || fail=1
    printf '%-12s %-20s %-10s %-10s %s\n' "$alias" "$name" "$state" "$health" "$address"
    [[ $state == running ]] || continue
    bound=$address
    [[ $address != - ]] || bound="its address"
    if ((networks == 0)); then
      flags+=("$name is stranded: it is on no network, so $bound is published nowhere;\
 docker network connect bridge $name reattaches it")
    elif ((published == 0)); then
      flags+=("$name is stranded: its start couldn't bind $bound, so it publishes no port;\
 docker restart $name binds it, once the host holds the address")
    fi
  done <<<"$rows"
  for alias in $(hosting_record); do
    if ! cut -f 1 <<<"$rows" | grep -qx -- "$alias"; then
      printf '%-12s %-20s %-10s %-10s %s\n' "$alias" - none - -
      fail=1
    fi
  done
  if ((${#flags[@]})); then
    echo
    printf '%s\n' "${flags[@]}"
    echo "net.ipv4.ip_nonlocal_bind = 1, the root step in the class's runbook, keeps a" \
      "container from starting before the host holds its address"
  fi
  return "$fail"
}

# Prints a table of the model each running row serves, from its /v1/models: the row's alias, the
# served model's ID, the repository it loaded, and its maximum context. Fails when any row doesn't
# answer.
hosting_observe_models() {
  local rows alias name state address body fail=0
  rows=$(hosting_observe_rows) || return
  printf '%-12s %-12s %-40s %s\n' ROW MODEL ROOT CONTEXT
  while IFS=$'\t' read -r alias _ name state address _; do
    [[ -n $alias ]] || continue
    if [[ $state != running || $address == - ]] ||
      ! body=$(hosting_observe_get "$address" /v1/models); then
      printf '%-12s %s\n' "$alias" "- ($name is $state and gave no /v1/models)"
      fail=1
      continue
    fi
    jq -r --arg alias "$alias" '.data[]
      | [$alias, .id, (.root // "-"), (.max_model_len // "-" | tostring)] | @tsv' <<<"$body" |
      while IFS=$'\t' read -r alias id root context; do
        printf '%-12s %-12s %-40s %s\n' "$alias" "$id" "$root" "$context"
      done
  done <<<"$rows"
  return "$fail"
}

# Prints the row with the alias given as hosting_observe_rows does, refusing when no container
# carries its row label or it is not running and configured to listen.
hosting_observe_row() {
  local rows row
  rows=$(hosting_observe_rows) || return
  row=$(awk -F '\t' -v alias="$1" '$1 == alias' <<<"$rows")
  if [[ -z $row ]]; then
    echo "hosting: no container carries the row label $HOSTING_ROW_LABEL=$1; hosting engine" \
      "status lists the rows" >&2
    return 1
  fi
  if [[ $(cut -f 4 <<<"$row") != running || $(cut -f 5 <<<"$row") == - ]]; then
    echo "hosting: $1's container $(cut -f 3 <<<"$row") is $(cut -f 4 <<<"$row") or listens on" \
      "no address; hosting engine status shows it" >&2
    return 1
  fi
  echo "$row"
}
