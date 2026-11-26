#!/usr/bin/env bash
# Tests for bench/vision-probe.sh, the vision row's image-budget probe, with curl stubbed to answer
# as the row did at probe-1120: the three requests it sends, their bodies, the table it prints, and
# what it refuses before any request.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

run_probe() {
  local copy reply
  copy=$(cat <<'EOF'
body=${*: -2:1}
n=$(find "$dir" -maxdepth 1 -name 'body-*' | wc -l)
cp "${body#@}" "$dir/body-$n"
EOF
)
  reply=$(cat <<'EOF'
jq -c '{usage: {prompt_tokens: (if (.messages[0].content | length) == 1 then 18
  elif (.messages[0].content[0].image_url.url | length) < 100000 then 1112 else 1122 end)}}' "${body#@}"
EOF
)
  write_stub curl "dir=$(printf %q "$tmp")
$copy
${curl_body:-}
$reply"
  run "$repo/bench/vision-probe.sh" "$@"
}

test_it_prints_the_probe_table_from_the_rows_prompt_tokens() {
  run_probe --host gb10-2
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal table "$out" "| Request | Prompt tokens | Image span |
| --- | --- | --- |
| Text only | 18 | - |
| 1240×1754 page | 1112 | 1094 |
| 3705×4934 page | 1122 | 1104 |"
}

test_it_sends_three_requests_to_the_vision_rows_port() {
  run_probe --host gb10-2
  assert_equal requests "$(calls | grep -c ' http://gb10-2:8001/v1/chat/completions$')" 3
}

test_the_text_only_request_sends_the_text_alone_with_one_token_out() {
  run_probe --host gb10-2
  assert_equal body "$(jq -c . "$tmp/body-0")" \
    '{"model":"vision","max_tokens":1,"messages":[{"role":"user","content":[{"type":"text","text":"Transcribe this page."}]}]}'
}

test_each_page_goes_whole_as_a_png_data_url_before_the_text() {
  run_probe --host gb10-2
  local n page
  for n in 1 2; do
    page=$repo/bench/probe/$([[ $n == 1 ]] && echo cfr-1240x1754.png || echo cfr-3705x4934.png)
    assert_equal "request $n's shape" "$(jq -c '{model, max_tokens, types: [.messages[0].content[].type],
      text: .messages[0].content[1].text}' "$tmp/body-$n")" \
      '{"model":"vision","max_tokens":1,"types":["image_url","text"],"text":"Transcribe this page."}'
    assert_equal "request $n's page" \
      "$(jq -r '.messages[0].content[0].image_url.url' "$tmp/body-$n")" \
      "data:image/png;base64,$(base64 -w 0 "$page")"
  done
}

test_the_committed_pages_are_the_probes_sizes() {
  local size page
  for size in 1240x1754 3705x4934; do
    page=$repo/bench/probe/cfr-$size.png
    assert_equal "$size page size" "$(od -An -tu1 -j16 -N8 "$page" |
      awk '{ printf "%dx%d", $1*16777216 + $2*65536 + $3*256 + $4, $5*16777216 + $6*65536 + $7*256 + $8 }')" \
      "$size"
  done
}

test_another_alias_uses_its_rows_port() {
  run_probe --host gb10-1 --alias agent
  assert_equal status "$status" 0
  assert_equal requests "$(calls | grep -c ' http://gb10-1:8000/v1/chat/completions$')" 3
}

test_a_failed_request_stops_the_probe() {
  local curl_body='exit 22'
  run_probe --host gb10-2
  assert_equal status "$status" 1
  assert_contains stderr "$err" "vision-probe: the text-only request to http://gb10-2:8001 failed"
  assert_equal requests "$(calls | wc -l)" 1
}

test_a_reply_without_prompt_tokens_stops_the_probe() {
  local curl_body='echo "{}"; exit 0'
  run_probe --host gb10-2
  assert_equal status "$status" 1
  assert_contains stderr "$err" "the text-only request's reply gives no usage.prompt_tokens: {}"
}

test_it_refuses_bad_arguments_before_any_request() {
  local args
  for args in "" "--host" "--host gb10-2.example.ts.net" "--host gb10-2 --alias" "--host gb10-2 extra"; do
    # shellcheck disable=SC2086 # Each case is split into its arguments.
    run_probe $args
    assert_equal "status for [$args]" "$status" 2
    assert_contains "stderr for [$args]" "$err" "usage: bench/vision-probe.sh"
  done
  run_probe --host gb10-2 --alias nothing
  assert_equal status "$status" 2
  assert_contains stderr "$err" "alias nothing is the alias of 0 rows in the class profiles, not 1"
  assert_equal calls "$(calls)" ""
}

run_tests
