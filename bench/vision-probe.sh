#!/usr/bin/env bash
# vision-probe reads how many prompt tokens the vision row gives a page at its image budget, with no
# other load: one request to /v1/chat/completions with the text "Transcribe this page." alone, then
# one for each of the two committed CFR pages, a 1240x1754 and a 3705x4934 PNG, each sent whole as a
# base64 data URL before the same text, every request with max_tokens 1. It prints each request's
# usage.prompt_tokens and the page's image span, that less the text-only request's, as the findings'
# probe table. The row is the alias's in the class profiles, its port read from there. It exits 2
# on a refusal before the first request, and 1 when a request fails.
#
#   bench/vision-probe.sh --host <host> [--alias <alias>]
#
# See bench/README.md.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd) || exit
# shellcheck source=lib/profile.sh
source "$root/lib/profile.sh"

text='Transcribe this page.'
pages=("$root/bench/probe/cfr-1240x1754.png" "$root/bench/probe/cfr-3705x4934.png")

usage() {
  echo "vision-probe: $1" >&2
  echo "usage: bench/vision-probe.sh --host <host> [--alias <alias>]" >&2
  exit 2
}

refuse() {
  echo "vision-probe: $1" >&2
  exit 2
}

alias=vision
while (($#)); do
  case $1 in
    --host | --alias)
      (($# >= 2)) || usage "$1 needs a value"
      case $1 in
        --host) host=$2 ;;
        --alias) alias=$2 ;;
      esac
      shift 2
      ;;
    *) usage "unknown argument $1" ;;
  esac
done
[[ -v host ]] || usage "no --host"
[[ $host =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || usage "--host $host is not a short host name"
[[ -n $alias ]] || usage "--alias is empty"

for page in "${pages[@]}"; do
  [[ -f $page ]] || refuse "the probe page $page is not a file"
done
for tool in curl base64; do
  command -v "$tool" >/dev/null || refuse "$tool is not on PATH"
done

ports=()
for profile in "$root"/classes/*/profile.toml; do
  port=$(hosting_yq -p toml -o json '.' "$profile" |
    jq -r --arg alias "$alias" '.rows[]? | select(.alias == $alias) | .port') || exit
  [[ -z $port ]] || ports+=("$port")
done
((${#ports[@]} == 1)) || refuse "alias $alias is the alias of ${#ports[@]} rows in the class profiles, not 1"
target=http://$host:${ports[0]}

body=$(mktemp) || exit
trap 'rm -f "$body"' EXIT

prompt_tokens() {
  local reply
  if ! reply=$(curl --silent --show-error --fail --max-time 600 \
    -H 'Content-Type: application/json' --data-binary "@$body" "$target/v1/chat/completions"); then
    echo "vision-probe: the $1 request to $target failed" >&2
    exit 1
  fi
  if ! jq -er '.usage.prompt_tokens | numbers' <<<"$reply"; then
    echo "vision-probe: the $1 request's reply gives no usage.prompt_tokens: $reply" >&2
    exit 1
  fi
}

jq -n --arg model "$alias" --arg text "$text" \
  '{model: $model, max_tokens: 1, messages: [{role: "user", content: [{type: "text", text: $text}]}]}' \
  >"$body" || exit
base=$(prompt_tokens "text-only") || exit

echo "| Request | Prompt tokens | Image span |"
echo "| --- | --- | --- |"
echo "| Text only | $base | - |"
for page in "${pages[@]}"; do
  size=${page##*cfr-}
  size=${size%.png}
  jq -n --arg model "$alias" --arg text "$text" --rawfile image <(base64 -w 0 "$page") \
    '{model: $model, max_tokens: 1, messages: [{role: "user", content: [
       {type: "image_url", image_url: {url: "data:image/png;base64,\($image)"}},
       {type: "text", text: $text}]}]}' >"$body" || exit
  tokens=$(prompt_tokens "${size/x/×} page") || exit
  echo "| ${size/x/×} page | $tokens | $((tokens - base)) |"
done
