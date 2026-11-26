#!/usr/bin/env bash
# Tests for bench/docinfer-inputs.sh, the bench's real-input builder and its manifest check,
# against a small docproc run each test writes, with guidellm stubbed and its Python stubbed to
# write each planned file as its source and its cycle: the rows the builder plans and writes, the
# check passing on matching inputs wherever they lie and failing, naming the file, on a mismatch,
# what the builder refuses before writing anything, and that the scenarios reading these rows read
# them from where it writes.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=lib/profile.sh
source "$repo/lib/profile.sh"

vision_prompt='Transcribe the text in this picture. If it has no text, describe it in one sentence.'

content() {
  local sha
  sha=$(printf '%s' "$1" | sha256sum | cut -d ' ' -f 1)
  mkdir -p "$docproc/content/${sha:0:2}"
  printf '%s' "$1" >"$docproc/content/${sha:0:2}/$sha"
  echo "$sha"
}

image_event() {
  jq -nc --arg sha "$1" '{event: "output", input: "/docs/a.pdf",
    output: {kind: "image", media_type: "image/png", sha256: $sha}}'
}

window_event() {
  jq -nc --arg sha "$1" --arg samples "$2" '{event: "output", input: "/docs/a.wav",
    output: {kind: "audio", media_type: "audio/wav", meta: {samples: $samples}, sha256: $sha}}'
}

write_run() {
  docproc=$tmp/docproc
  mkdir -p "$docproc/runs/r"
  page_a=$(content page-a)
  page_b=$(content page-b)
  page_other=$(content page-other)
  window_28=$(content window-28)
  window_30=$(content window-30)
  window_27=$(content window-27)
  window_31=$(content window-31)
  {
    image_event "$page_b"
    image_event "$page_a"
    image_event "$page_a"
    image_event "$page_other"
    window_event "$window_30" 480000
    window_event "$window_28" 448000
    window_event "$window_28" 448000
    window_event "$window_27" 447999
    window_event "$window_31" 480001
    echo '{"event": "part", "input": "/docs/a.pdf"}'
  } >"$docproc/runs/r/record.jsonl"
  printf '# The pages.\n%s\n%s\n' "$page_a" "$page_b" >"$tmp/pages.txt"
}

run_inputs() {
  write_stub guidellm
  write_stub python 'while IFS=$'"'\\t'"' read -r path dest cycle; do
  { cat "$path"; echo " $cycle"; } >"$dest"
done < <(jq -r "[.path, .dest, .cycle] | @tsv")'
  run "$repo/bench/docinfer-inputs.sh" "$@"
}

build() {
  run_inputs build --docproc "$docproc" --pages "$tmp/pages.txt" --output "$tmp/out" "$@"
}

build_and_record_manifest() {
  write_run
  build
  run_inputs manifest --output "$tmp/out"
  printf '%s\n' "$out" >"$tmp/manifest"
}

check() {
  run_inputs check --manifest "$tmp/manifest" --output "${1:-$tmp/out}"
}

test_build_hands_the_python_the_plan_and_writes_the_rows() {
  write_run
  build
  assert_equal status "$status" 0
  assert_equal calls "$(calls)" "python $repo/bench/docinfer-inputs.py"
  local pages="$tmp/out/dense-pages.jsonl" windows="$tmp/out/windows-30.jsonl"
  assert_equal "page rows" "$(wc -l <"$pages")" 440
  assert_equal "window rows" "$(wc -l <"$windows")" 2000
  local first_two
  first_two=$(head -n 2 "$pages" | jq -r .source | paste -sd ' ')
  assert_equal "page sources, in sha256 order" "$first_two" \
    "$(printf '%s\n' "$page_a" "$page_b" | sort | paste -sd ' ')"
  assert_equal "window sources" "$(jq -r .source "$windows" | sort -u | paste -sd ' ')" \
    "$(printf '%s\n' "$window_28" "$window_30" | sort | paste -sd ' ')"
  assert_equal "page row 3" "$(sed -n 3p "$pages" | jq -c '{prompt, image}')" \
    "$(jq -nc --arg p "$vision_prompt" --arg i "$tmp/out/dense-pages/00002.png" '{prompt: $p, image: $i}')"
  assert_equal "page row 3's file" "$(cat "$tmp/out/dense-pages/00002.png")" \
    "$(cat "$docproc/content/$(sed -n 3p "$pages" | jq -r '.source | .[:2] + "/" + .')") 1"
  assert_equal "window prompt" "$(head -n 1 "$windows" | jq -r .prompt | head -n 1)" \
    "Transcribe the following speech segment in its original language into text."
  assert_equal "window row 2000's file" "$(jq -r 'select(.audio | endswith("/01999.wav")) | .audio' \
    "$windows")" "$tmp/out/windows-30/01999.wav"
  assert_equal "rows whose file is their sha256" "$(jq -r '"\(.sha256)  \(.image // .audio)"' \
    "$pages" "$windows" | sha256sum --check --quiet 2>&1)" ""
  assert_equal "plan left behind" "$([[ -e $tmp/out/plan.jsonl ]] && echo yes)" ""
}

test_check_passes_on_the_inputs_the_manifest_records() {
  build_and_record_manifest
  assert_equal "manifest files" "$(cut -d ' ' -f 3 "$tmp/manifest" | paste -sd ' ')" \
    "dense-pages.jsonl windows-30.jsonl"
  check
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
}

test_check_passes_on_the_same_inputs_moved_elsewhere() {
  build_and_record_manifest
  mv "$tmp/out" "$tmp/moved"
  find "$tmp/moved" -name '*.jsonl' -exec sed -i "s|$tmp/out/|$tmp/moved/|g" {} +
  check "$tmp/moved"
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
}

test_check_names_a_row_file_that_differs() {
  build_and_record_manifest
  echo changed >>"$tmp/out/windows-30/00007.wav"
  check
  assert_equal status "$status" 1
  assert_contains stderr "$err" "FAIL: $tmp/out/windows-30/00007.wav: not the sha256 its row in $tmp/out/windows-30.jsonl gives"
}

test_check_names_a_missing_row_file() {
  build_and_record_manifest
  rm "$tmp/out/dense-pages/00400.png"
  check
  assert_equal status "$status" 1
  assert_contains stderr "$err" "FAIL: $tmp/out/dense-pages/00400.png: not the sha256"
}

test_check_names_a_rows_file_that_differs() {
  build_and_record_manifest
  sed -i '1s/Transcribe/Describe/' "$tmp/out/dense-pages.jsonl"
  check
  assert_equal status "$status" 1
  assert_contains stderr "$err" "FAIL: $tmp/out/dense-pages.jsonl: sha256 "
  assert_contains stderr "$err" ", the manifest's $(head -n 1 "$tmp/manifest" | cut -d ' ' -f 1)"
}

test_check_names_a_missing_rows_file() {
  build_and_record_manifest
  rm "$tmp/out/windows-30.jsonl"
  check
  assert_equal status "$status" 1
  assert_equal stderr "$err" "FAIL: $tmp/out/windows-30.jsonl is missing; run bench/docinfer-inputs.sh build"
}

test_the_committed_manifest_records_both_rows_files() {
  assert_equal "manifest files" "$(cut -d ' ' -f 3 "$repo/bench/docinfer-inputs.sha256" | paste -sd ' ')" \
    "dense-pages.jsonl windows-30.jsonl"
  assert_equal "malformed lines" \
    "$(grep -cvE '^[0-9a-f]{64}  [a-z0-9-]+\.jsonl$' "$repo/bench/docinfer-inputs.sha256")" 0
}

test_the_committed_page_list_names_110_distinct_pages() {
  local list
  list=$(grep -v '^#' "$repo/bench/dense-pages.txt")
  assert_equal pages "$(grep -cE '^[0-9a-f]{64}$' <<<"$list")" 110
  assert_equal "distinct pages" "$(sort -u <<<"$list" | wc -l)" 110
}

test_the_scenarios_reading_these_rows_read_them_from_the_default_output() {
  local scenario
  for scenario in vision-dense:dense-pages.jsonl audio-real-30s:windows-30.jsonl; do
    assert_equal "${scenario%%:*} rows" \
      "$(hosting_yq '.spec.data[0].path' "$repo/bench/${scenario%%:*}.yaml")" \
      ".state/bench/docinfer/${scenario#*:}"
  done
}

test_build_refuses_a_page_the_run_lacks_before_writing() {
  write_run
  echo "$(printf x | sha256sum | cut -d ' ' -f 1)" >>"$tmp/pages.txt"
  build
  assert_equal status "$status" 2
  assert_contains stderr "$err" "has no image output $(printf x | sha256sum | cut -d ' ' -f 1)"
  assert_equal calls "$(calls)" ""
  assert_equal "output" "$([[ -e $tmp/out ]] && echo written)" ""
}

test_build_refuses_a_malformed_or_repeated_page_list() {
  write_run
  echo nope >>"$tmp/pages.txt"
  build
  assert_equal status "$status" 2
  assert_contains stderr "$err" "nope is not a sha256"
  write_run
  echo "$page_a" >>"$tmp/pages.txt"
  build
  assert_equal status "$status" 2
  assert_contains stderr "$err" "names a page twice"
  assert_equal calls "$(calls)" ""
}

test_build_refuses_a_run_with_no_window_of_28_to_30_s() {
  write_run
  jq -c 'select(.output.kind != "audio" or .output.meta.samples == "447999")' \
    "$docproc/runs/r/record.jsonl" >"$tmp/record" && mv "$tmp/record" "$docproc/runs/r/record.jsonl"
  build
  assert_equal status "$status" 2
  assert_contains stderr "$err" "has no audio window of 28 to 30 s"
  assert_equal calls "$(calls)" ""
}

test_build_refuses_a_missing_content_file() {
  write_run
  rm "$docproc/content/${window_30:0:2}/$window_30"
  build
  assert_equal status "$status" 2
  assert_contains stderr "$err" "$docproc/content/${window_30:0:2}/$window_30 is not a file"
  assert_equal calls "$(calls)" ""
}

test_build_refuses_a_directory_without_one_run() {
  write_run
  run_inputs build --docproc "$tmp" --pages "$tmp/pages.txt" --output "$tmp/out"
  assert_equal status "$status" 2
  assert_contains stderr "$err" "holds no docproc run"
  mkdir -p "$docproc/runs/s" && cp "$docproc/runs/r/record.jsonl" "$docproc/runs/s/"
  build
  assert_equal status "$status" 2
  assert_contains stderr "$err" "holds 2 docproc runs, not 1"
  assert_equal calls "$(calls)" ""
}

test_build_outside_the_bench_environment_refuses() {
  write_run
  PATH=$stubs:$(dirname "$(command -v jq)"):/usr/bin:/bin run "$repo/bench/docinfer-inputs.sh" \
    build --docproc "$docproc" --pages "$tmp/pages.txt" --output "$tmp/out"
  assert_equal status "$status" 2
  assert_contains stderr "$err" "guidellm is not on PATH"
}

test_arguments_are_validated() {
  local args
  for args in "" "rows" "check --pages x" "manifest --docproc x" "build --output" "build --docproc ''"; do
    eval "run_inputs $args"
    assert_equal "status for [$args]" "$status" 2
    assert_contains "stderr for [$args]" "$err" "usage: bench/docinfer-inputs.sh"
  done
  assert_equal calls "$(calls)" ""
}

run_tests
