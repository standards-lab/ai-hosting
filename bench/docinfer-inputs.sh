#!/usr/bin/env bash
# docinfer-inputs writes the bench's real inputs from a local docproc run, shaped as docinfer sends
# them, and checks them against the committed manifest. build plans the rows from the run's record
# (the dense pages its list names, and every distinct audio window of 28 to 30 s), then writes each
# row's own page or window with the Python of the bench environment's GuideLLM, and the JSONL rows
# the scenarios read, each naming its file and that file's sha256. check fails, naming the file,
# unless each JSONL file's sha256, its paths taken relative to the output directory, is the
# manifest's, and each row's file is the sha256 its row gives. manifest prints the manifest of the
# inputs in the output directory. It writes only under the output directory, and exits 2 on a
# refusal.
#
#   bench/docinfer-inputs.sh build [--docproc <run dir>] [--pages <file>] [--output <dir>]
#   bench/docinfer-inputs.sh check [--manifest <file>] [--output <dir>]
#   bench/docinfer-inputs.sh manifest [--output <dir>]
#
# See bench/README.md.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd) || exit

page_rows=440
window_rows=2000
window_seconds=(28 30)
window_rate=16000
vision_prompt='Transcribe the text in this picture. If it has no text, describe it in one sentence.'
audio_prompt='Transcribe the following speech segment in its original language into text.

Follow these specific instructions for formatting the answer:
* Only output the transcription, with no newlines.
* When transcribing numbers, write the digits, i.e. write 1.7 and not one point seven, and write 3 instead of three.'
row_files=(dense-pages.jsonl windows-30.jsonl)

usage() {
  echo "docinfer-inputs: $1" >&2
  echo "usage: bench/docinfer-inputs.sh build [--docproc <run dir>] [--pages <file>] [--output <dir>]" \
    "| check [--manifest <file>] [--output <dir>] | manifest [--output <dir>]" >&2
  exit 2
}

refuse() {
  echo "docinfer-inputs: $1" >&2
  exit 2
}

command=${1-}
case $command in
  build | check | manifest) shift ;;
  '') usage "no build, check or manifest" ;;
  *) usage "unknown $command" ;;
esac

docproc=$HOME/runs/docs-corpus/baseline/v0.2.0/docproc
pages=$root/bench/dense-pages.txt
manifest=$root/bench/docinfer-inputs.sha256
output=$root/.state/bench/docinfer
while (($#)); do
  case $command:$1 in
    build:--docproc | build:--pages | check:--manifest | *:--output)
      (($# >= 2)) || usage "$1 needs a value"
      [[ -n $2 ]] || usage "$1 is empty"
      case $1 in
        --docproc) docproc=$2 ;;
        --pages) pages=$2 ;;
        --manifest) manifest=$2 ;;
        --output) output=$2 ;;
      esac
      shift 2
      ;;
    *) usage "$command takes no $1" ;;
  esac
done
output=$(realpath -m -- "$output") || exit

canonical_sha256() {
  jq -c --arg dir "$output/" 'walk(if type == "string" then ltrimstr($dir) else . end)' "$1" |
    sha256sum | cut -d ' ' -f 1
}

check_row_files() {
  local rows=$1 failed
  failed=$(jq -r '"\(.sha256)  \(.image // .audio)"' "$rows" |
    sha256sum --check --quiet --strict 2>/dev/null | sed 's/: FAILED.*$//')
  if [[ -n $failed ]]; then
    sed "s|^|FAIL: |; s|\$|: not the sha256 its row in $rows gives|" <<<"$failed" >&2
    return 1
  fi
}

check_inputs() {
  [[ -f $manifest ]] || refuse "manifest $manifest is not a file"
  local fail=0 want name got
  while read -r want name; do
    [[ $want =~ ^[0-9a-f]{64}$ && -n $name ]] || refuse "manifest $manifest: malformed line: $want $name"
    if [[ ! -f $output/$name ]]; then
      echo "FAIL: $output/$name is missing; run bench/docinfer-inputs.sh build" >&2
      fail=1
      continue
    fi
    got=$(canonical_sha256 "$output/$name") || exit
    if [[ $got != "$want" ]]; then
      echo "FAIL: $output/$name: sha256 $got, the manifest's $want" >&2
      fail=1
      continue
    fi
    check_row_files "$output/$name" || fail=1
  done <"$manifest"
  return "$fail"
}

print_manifest() {
  local name
  for name in "${row_files[@]}"; do
    [[ -f $output/$name ]] || refuse "$output/$name is not a file; run bench/docinfer-inputs.sh build"
    check_row_files "$output/$name" || exit 1
    echo "$(canonical_sha256 "$output/$name")  $name"
  done
}

case $command in
  check)
    check_inputs || exit 1
    echo "docinfer-inputs: $output matches $manifest"
    exit 0
    ;;
  manifest)
    print_manifest
    exit 0
    ;;
esac

records=("$docproc"/runs/*/record.jsonl)
[[ -f ${records[0]} ]] || refuse "$docproc holds no docproc run, runs/<id>/record.jsonl"
((${#records[@]} == 1)) || refuse "$docproc holds ${#records[@]} docproc runs, not 1"
record=${records[0]}
[[ -f $pages ]] || refuse "the page list $pages is not a file"
mapfile -t wanted < <(grep -v '^#' "$pages" | grep .)
((${#wanted[@]})) || refuse "the page list $pages names no page"
for sha in "${wanted[@]}"; do
  [[ $sha =~ ^[0-9a-f]{64}$ ]] || refuse "the page list $pages: $sha is not a sha256"
done
[[ -z $(printf '%s\n' "${wanted[@]}" | sort | uniq -d) ]] ||
  refuse "the page list $pages names a page twice"

if ! guidellm=$(command -v guidellm); then
  refuse "guidellm is not on PATH; run in the bench environment, MISE_ENV=bench mise exec --"
fi
python=$(dirname "$(readlink -f "$guidellm")")/python
[[ -x $python ]] || refuse "no Python beside $guidellm"

mapfile -t found < <(jq -r --argjson want "$(printf '%s\n' "${wanted[@]}" | jq -Rsc 'split("\n")[:-1]')" \
  'select(.event == "output" and .output.kind == "image") | .output.sha256
   | select(IN($want[]))' "$record" | sort -u)
missing=$(comm -23 <(printf '%s\n' "${wanted[@]}" | sort) <(printf '%s\n' "${found[@]}"))
[[ -z $missing ]] || refuse "the run $record has no image output $(head -n 1 <<<"$missing")"

mapfile -t windows < <(jq -r --argjson lo $((window_seconds[0] * window_rate)) \
  --argjson hi $((window_seconds[1] * window_rate)) \
  'select(.event == "output" and .output.kind == "audio") | .output
   | select((.meta.samples | tonumber) as $n | $n >= $lo and $n <= $hi) | .sha256' "$record" |
  sort -u)
((${#windows[@]})) ||
  refuse "the run $record has no audio window of ${window_seconds[0]} to ${window_seconds[1]} s"

for sha in "${found[@]}" "${windows[@]}"; do
  [[ -f $docproc/content/${sha:0:2}/$sha ]] || refuse "$docproc/content/${sha:0:2}/$sha is not a file"
done

plan() {
  jq -nc --argjson sources "$(printf '%s\n' "${@:5}" | jq -Rsc 'split("\n")[:-1]')" \
    --argjson rows "$2" --arg kind "$1" --arg dir "$output/$3" --arg ext "$4" \
    --arg content "$docproc/content" '
    ($sources | length) as $n
    | range($rows) as $i | $sources[$i % $n] as $s
    | {kind: $kind, source: $s, path: "\($content)/\($s[:2])/\($s)",
       dest: "\($dir)/\("0000\($i)"[-5:]).\($ext)", cycle: ($i / $n | floor)}'
}

mkdir -p "$output/dense-pages" "$output/windows-30" || exit
plan_file=$output/plan.jsonl
{
  plan page "$page_rows" dense-pages png "${found[@]}"
  plan window "$window_rows" windows-30 wav "${windows[@]}"
} >"$plan_file" || exit

"$python" "$root/bench/docinfer-inputs.py" <"$plan_file" || exit

sums=$(jq -r .dest "$plan_file" | xargs -d '\n' sha256sum) || exit
repeat=$(cut -d ' ' -f 1 <<<"$sums" | sort | uniq -d | head -n 1)
[[ -z $repeat ]] || refuse "two rows wrote the same file, sha256 $repeat"

write_rows() {
  jq -nc --arg kind "$1" --arg column "$2" --arg prompt "$3" --rawfile sums <(echo "$sums") '
    ($sums | split("\n") | map(select(. != "") | capture("^(?<sha>[0-9a-f]{64})  (?<path>.*)$")
      | {key: .path, value: .sha}) | from_entries) as $sha
    | inputs | select(.kind == $kind)
    | {prompt: $prompt, ($column): .dest, source, sha256: $sha[.dest]}' "$plan_file"
}

write_rows page image "$vision_prompt" >"$output/dense-pages.jsonl" || exit
write_rows window audio "$audio_prompt" >"$output/windows-30.jsonl" || exit
rm -f "$plan_file"
echo "docinfer-inputs: $output/dense-pages.jsonl $page_rows rows over ${#found[@]} pages," \
  "$output/windows-30.jsonl $window_rows rows over ${#windows[@]} windows"
