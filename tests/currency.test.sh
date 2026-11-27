#!/usr/bin/env bash
# Tests for scripts/currency.sh's report of the mise tool pins, the gateway services' FROM pins, and
# its HOLDS list, offline: mise, gh, curl, and crane are stubbed, over a project whose action, vLLM
# release, and image pins are current.
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
  service_image torii owner/gateway:v1.1.0 v1.0.0 v1.1.0 v1.2.0-rc.1 latest
  write_stub gh "echo v1"
  write_stub curl "echo '{\"digest\": \"sha256:d\", \"info\": {\"version\": \"1\"}}'"
}

service_image() {
  local service=$1 base=$2
  shift 2
  mkdir -p "$project/compose/$service" "$(dirname "$tmp/tags/${base%:*}")"
  printf 'FROM %s\n' "$base" >"$project/compose/$service/Dockerfile"
  printf '%s\n' "$@" >"$tmp/tags/${base%:*}"
  write_stub crane "cat '$tmp/tags/'\"\$2\""
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

test_a_service_image_behind_its_latest_v_tag_is_reported() {
  fake_project
  outdated_tools ""
  service_image torii owner/gateway:v1.0.0 v1.0.0 v1.1.0 v1.10.0 v1.11.0-rc.1 1.12.0
  run_currency
  assert_equal status "$status" 1
  assert_equal stdout "$out" "compose/torii/Dockerfile: owner/gateway v1.0.0 -> v1.10.0"
}

test_a_service_image_is_compared_within_its_variant() {
  fake_project
  outdated_tools ""
  service_image postgres postgres:18.7-alpine 18.7-alpine 18.10-alpine 19.0 20-alpine \
    19.1-alpine3.22 latest
  run_currency
  assert_equal status "$status" 1
  assert_equal stdout "$out" "compose/postgres/Dockerfile: postgres 18.7-alpine -> 18.10-alpine"
}

test_a_service_image_at_its_latest_tag_reports_nothing() {
  fake_project
  outdated_tools ""
  service_image postgres postgres:19.0-alpine 18.7-alpine 19.0-alpine 19.1 19.2-beta1-alpine
  run_currency
  assert_equal status "$status" 0
  assert_equal stdout "$out" ""
}

test_a_held_service_image_passes() {
  fake_project
  outdated_tools "postgres 18.7-alpine: $reason"
  service_image postgres postgres:18.7-alpine 18.7-alpine 19.0-alpine
  run_currency
  assert_equal status "$status" 0
  assert_equal stdout "$out" "compose/postgres/Dockerfile: postgres 18.7-alpine -> 19.0-alpine held: $reason"
}

test_a_service_image_with_no_tag_of_its_form_fails() {
  fake_project
  outdated_tools ""
  service_image torii owner/gateway:v1.0.0 1.0.0 1.1.0 latest
  run_currency
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" \
    "compose/torii/Dockerfile: owner/gateway lists no release tag of v1.0.0's form"
}

run_tests
