#!/usr/bin/env bash
# Tests for scripts/currency.sh's report of the mise tool pins and its HOLDS list, offline: mise,
# gh, and curl are stubbed, over a project whose action, vLLM release, and image pins are current.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

reason="MTEB requires Python below 3.15"

fake_project() {
  project=$tmp/project
  mkdir -p "$project/lib" "$project/.github/workflows" "$project/images/audio"
  echo VLLM_RELEASE=v1 >"$project/lib/vllm.env"
  echo "      - uses: owner/action@v1" >"$project/.github/workflows/ci.yml"
  printf 'FROM owner/image:v1@sha256:d\nRUN pip install package==1\n' \
    >"$project/images/audio/Dockerfile"
  write_stub gh "echo v1"
  write_stub curl "echo '{\"digest\": \"sha256:d\", \"info\": {\"version\": \"1\"}}'"
}

outdated_tools() {
  local holds=$1
  shift
  jq -n --arg holds "$holds" '{HOLDS: $holds}' >"$tmp/env.json"
  jq -n --arg root "$project" '[$ARGS.positional | range(0; length; 4) as $i | .[$i:$i + 4]
    | {key: .[1], value: {name: .[1], requested: .[2], current: .[2], bump: .[3], latest: .[3],
        source: {type: "mise.toml", path: "\($root)/\(.[0])"}}}] | from_entries' \
    --args "$@" >"$tmp/outdated.json"
  write_stub mise "case \$1 in env) cat '$tmp/env.json' ;; outdated) cat '$tmp/outdated.json' ;; esac"
}

run_currency() {
  MISE_PROJECT_ROOT=$project run "$clone/scripts/currency.sh"
}

test_a_held_pin_is_reported_with_its_reason_and_passes() {
  fake_project
  outdated_tools "python 3.14.10: $reason" mise.bench.toml python 3.14.10 3.15.2
  run_currency
  assert_equal status "$status" 0
  assert_equal stdout "$out" "mise.bench.toml: python 3.14.10 -> 3.15.2 held: $reason"
}

test_a_trailing_pin_beside_a_held_one_fails() {
  fake_project
  outdated_tools "python 3.14.10: $reason" mise.bench.toml python 3.14.10 3.15.2 \
    mise.toml jq 1.8.2 1.8.3
  run_currency
  assert_equal status "$status" 1
  assert_equal stdout "$out" "mise.bench.toml: python 3.14.10 -> 3.15.2 held: $reason
mise.toml: jq 1.8.2 -> 1.8.3"
}

test_a_hold_ends_when_the_pin_moves() {
  fake_project
  outdated_tools "python 3.14.9: $reason" mise.bench.toml python 3.14.10 3.15.2
  run_currency
  assert_equal status "$status" 1
  assert_equal stdout "$out" "mise.bench.toml: python 3.14.10 -> 3.15.2"
}

test_current_pins_report_nothing() {
  fake_project
  outdated_tools ""
  run_currency
  assert_equal status "$status" 0
  assert_equal stdout "$out" ""
}

run_tests
