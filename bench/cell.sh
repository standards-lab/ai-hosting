#!/usr/bin/env bash
# cell runs one GuideLLM capacity scenario against one row, one level at a time, in the bench
# environment, writing one result JSON a level as <dir>/<cell>-<level>.json. A level is a count of
# streams on a concurrent scenario and a rate in requests a second on a constant one. Each level
# sends its own inputs: a level of a scenario reading a JSON file takes the next <rows> rows of it,
# and every level draws its synthetic text and images from seeds set to its level. --seconds sets
# each level's max_duration in place of the scenario's, and --requests its max_requests. The row is
# the alias's in the class profiles, its port and tokenizer read from there. Before the first level
# it refuses a row whose /metrics reads vllm:mm_cache_queries_total or
# vllm:prefix_cache_queries_total above 0: restart the row first. --gateway sends the load through
# the gateway on that host instead, with the key in AI_GATEWAY_TOKEN, and --row-down runs it with
# the row stopped, refusing a row whose /metrics answers. It exits 2 on a refusal, and stops at the
# first level GuideLLM fails.
#
#   bench/cell.sh --host <host> --alias <alias> --scenario <file> --cell <cell> [--output <dir>]
#     [--seconds <n>] [--requests <n>] [--gateway <host> [--row-down]] <level>[:<rows>]...
#
# See bench/README.md.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd) || exit
# shellcheck source=lib/profile.sh
source "$root/lib/profile.sh"

usage() {
  echo "cell: $1" >&2
  echo "usage: bench/cell.sh --host <host> --alias <alias> --scenario <file> --cell <cell> [--output <dir>] [--seconds <n>] [--requests <n>] [--gateway <host> [--row-down]] <level>[:<rows>]..." >&2
  exit 2
}

refuse() {
  echo "cell: $1" >&2
  exit 2
}

output=$root/.state/bench
gateway_port=3000
row_down=0
levels=()
while (($#)); do
  case $1 in
    --host | --alias | --scenario | --cell | --output | --seconds | --requests | --gateway)
      (($# >= 2)) || usage "$1 needs a value"
      case $1 in
        --host) host=$2 ;;
        --alias) alias=$2 ;;
        --scenario) scenario=$2 ;;
        --cell) cell=$2 ;;
        --output) output=$2 ;;
        --seconds) seconds=$2 ;;
        --requests) requests=$2 ;;
        --gateway) gateway=$2 ;;
      esac
      shift 2
      ;;
    --row-down)
      row_down=1
      shift
      ;;
    -*) usage "unknown option $1" ;;
    *)
      levels+=("$1")
      shift
      ;;
  esac
done

[[ -v host ]] || usage "no --host"
[[ $host =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || usage "--host $host is not a short host name"
[[ -v alias ]] || usage "no --alias"
[[ -v scenario ]] || usage "no --scenario"
[[ -v cell ]] || usage "no --cell"
[[ $cell =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage "--cell $cell is not a file name"
[[ -n $output ]] || usage "--output is empty"
[[ ! -v seconds || $seconds =~ ^[1-9][0-9]*$ ]] || usage "--seconds $seconds is not a positive whole number"
[[ ! -v requests || $requests =~ ^[1-9][0-9]*$ ]] || usage "--requests $requests is not a positive whole number"
[[ ! -v gateway || $gateway =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] ||
  usage "--gateway $gateway is not a short host name"
((!row_down)) || [[ -v gateway ]] || usage "--row-down needs --gateway"
if [[ -v gateway && -z ${AI_GATEWAY_TOKEN:-} ]]; then
  usage "--gateway needs the key in AI_GATEWAY_TOKEN"
fi
((${#levels[@]})) || usage "no level"

values=() rows=()
for level in "${levels[@]}"; do
  [[ $level =~ ^([1-9][0-9]*)(:([1-9][0-9]*))?$ ]] ||
    usage "level $level is not <level> or <level>:<rows>"
  for seen in "${values[@]}"; do
    [[ $seen != "${BASH_REMATCH[1]}" ]] || usage "level $level repeats level $seen"
  done
  values+=("${BASH_REMATCH[1]}")
  rows+=("${BASH_REMATCH[3]}")
done

[[ -f $scenario ]] || refuse "scenario $scenario is not a file"
if ! spec=$(hosting_yq -p yaml -o json '.spec' "$scenario" 2>&1) ||
  ! jq -e 'type == "object"' <<<"$spec" >/dev/null; then
  refuse "scenario $scenario has no spec mapping"
fi
kind=$(jq -r '.profile.kind' <<<"$spec")
case $kind in
  concurrent) level_key=streams ;;
  constant) level_key=rate ;;
  *) refuse "scenario $scenario is not a concurrent or constant profile; a level is a count of streams or a rate" ;;
esac
unsupported=$(jq -r '[.data[]? | .kind
  | select(. != "synthetic_text" and . != "synthetic_image" and . != "json_file")]
  | unique | join(", ")' <<<"$spec")
[[ -z $unsupported ]] ||
  refuse "scenario $scenario reads $unsupported, which a level can't take distinct inputs from"
jq -e '.data | type == "array" and length > 0' <<<"$spec" >/dev/null ||
  refuse "scenario $scenario has no data"
jq -e '[.data[] | .[] | select(type == "object" or type == "array")] | length == 0' \
  <<<"$spec" >/dev/null || refuse "scenario $scenario has a data source with nested settings"
source_file=$(jq -r '[.data[] | select(.kind == "json_file") | .path] | if length > 1
  then error("more than one json_file") else .[0] // "" end' <<<"$spec") ||
  refuse "scenario $scenario reads more than one JSON file"

for i in "${!levels[@]}"; do
  if [[ -n $source_file && -z ${rows[i]} ]]; then
    usage "level ${levels[i]} gives no rows; scenario $scenario reads a JSON file"
  elif [[ -z $source_file && -n ${rows[i]} ]]; then
    usage "level ${levels[i]} gives rows; scenario $scenario reads no JSON file"
  fi
done

matches=()
for profile in "$root"/classes/*/profile.toml; do
  match=$(hosting_yq -p toml -o json '.' "$profile" | jq -c --arg alias "$alias" \
    '.rows[]? | select(.alias == $alias) | {port, tokenizer: (.source.base_model // .model)}') ||
    exit
  [[ -z $match ]] || matches+=("$match")
done
((${#matches[@]} == 1)) || refuse "alias $alias is the alias of ${#matches[@]} rows in the class profiles, not 1"
port=$(jq -r .port <<<"${matches[0]}")
tokenizer=$(jq -r .tokenizer <<<"${matches[0]}")

if [[ -n $source_file ]]; then
  [[ $source_file == /* ]] || source_file=$root/$source_file
  [[ -f $source_file ]] || refuse "the scenario's JSON file $source_file is not a file"
  available=$(wc -l <"$source_file")
  needed=0
  for n in "${rows[@]}"; do
    needed=$((needed + n))
  done
  ((needed <= available)) ||
    refuse "the levels take $needed rows, and $source_file holds $available"
fi

for n in "${values[@]}"; do
  [[ ! -e $output/$cell-$n.json ]] || refuse "$output/$cell-$n.json exists"
done

command -v guidellm >/dev/null ||
  refuse "guidellm is not on PATH; run in the bench environment, MISE_ENV=bench mise exec --"

row=http://$host:$port
if ((row_down)); then
  ! curl --silent --fail --max-time 5 "$row/metrics" >/dev/null ||
    refuse "$row/metrics answers; --row-down runs with the row stopped"
else
  if ! metrics=$(curl --silent --fail --max-time 5 "$row/metrics"); then
    refuse "$row/metrics doesn't answer"
  fi
  for counter in vllm:mm_cache_queries_total vllm:prefix_cache_queries_total; do
    count=$(awk -v name="$counter" '$1 == name || index($1, name "{") == 1 { sum += $NF }
      END { print sum + 0 }' <<<"$metrics")
    [[ $count == 0 ]] ||
      refuse "$row reads $counter at $count, not 0; restart the row, as hosting engine update $alias on $host does"
  done
fi

target=$row
backend=kind=openai_http,model=$alias
if [[ -v gateway ]]; then
  target=http://$gateway:$gateway_port/$alias
  printf 'Authorization: Bearer %s\n' "$AI_GATEWAY_TOKEN" |
    curl --silent --fail --max-time 5 --output /dev/null --header @- "$target/v1/models" ||
    refuse "$target/v1/models doesn't answer the key in AI_GATEWAY_TOKEN"
  export GUIDELLM__SPEC__BACKEND__API_KEY=$AI_GATEWAY_TOKEN
  backend+=,validate_backend=false
fi

constraints=()
if [[ -v seconds || -v requests ]]; then
  while IFS= read -r constraint; do
    constraints+=(--constraint "$constraint")
  done < <(jq -r --arg seconds "${seconds:-}" --arg requests "${requests:-}" '
    ([if $requests != "" then {kind: "max_requests", count: ($requests | tonumber)} else empty end,
      if $seconds != "" then {kind: "max_duration", seconds: ($seconds | tonumber)} else empty end]
    ) as $given
    | [.constraints[]? | select(.kind as $kind | [$given[].kind] | index($kind) | not)] + $given
    | .[] | to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$spec")
fi

mkdir -p "$output" || exit
first=1
for i in "${!values[@]}"; do
  n=${values[i]}
  data=()
  while IFS= read -r source; do
    data+=(--data "$source")
  done < <(jq -r --arg seed "$n" --arg path "$output/$cell-$n.jsonl" '.data[]
    | if .kind == "json_file" then .path = $path
      elif .kind == "synthetic_image" then .seed = $seed else . end
    | to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$spec")
  if [[ -n $source_file ]]; then
    last=$((first + rows[i] - 1))
    sed -n "$first,${last}p" "$source_file" >"$output/$cell-$n.jsonl" || exit
    first=$((last + 1))
  fi
  GUIDELLM__SPEC__BACKEND__TARGET=$target guidellm run -c "$scenario" \
    --profile "kind=$kind,$level_key=$n" \
    "${data[@]}" \
    --seed "kind=static,value=$n" \
    "${constraints[@]}" \
    --backend "$backend" \
    --tokenizer "kind=huggingface_auto,model=$tokenizer" \
    --output "kind=json,path=$output/$cell-$n.json" || exit
done
