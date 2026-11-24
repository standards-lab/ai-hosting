#!/usr/bin/env bash
# Tests for scripts/watch.sh's report of a register's upstream and watched lines, offline: gh is
# stubbed to answer from fixture responses under the test's directory, each --jq expression applied
# with jq as gh would, and the register is a fixture written as the clone's docs/watch.md.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

stub_gh() {
  write_stub gh "root=$(printf %q "$tmp/gh")
$(
    cat <<'EOF'
expr='' args=()
while (($#)); do
  case $1 in
    --jq) expr=$2 && shift 2 ;;
    --json | -H) shift 2 ;;
    -R) args+=("$2") && shift 2 ;;
    *) args+=("$1") && shift ;;
  esac
done
case ${args[0]} in
  pr | issue) response=$root/${args[0]}/${args[3]}/${args[2]} ;;
  release) response=$root/release/${args[2]} ;;
  api) response=$root/api/${args[1]} ;;
esac
[[ -f $response ]] || exit 1
if [[ -n $expr ]]; then jq -r "$expr" "$response"; else cat "$response"; fi
EOF
  )"
}

respond() {
  mkdir -p "$(dirname "$tmp/gh/$1")"
  printf '%s\n' "$2" >"$tmp/gh/$1"
}

released() {
  respond "release/$1" "{\"tagName\": \"$2\"}"
}

register() {
  mkdir -p "$clone/docs"
  {
    echo "## An entry"
    cat
  } >"$clone/docs/watch.md"
}

run_watch() {
  stub_gh
  run "$clone/scripts/watch.sh"
  report=${out#*$'\n'}
}

line_for() {
  grep -F -- "$1" <<<"$report"
}

test_an_upstream_pull_request_matching_its_state_passes() {
  respond pr/o/r/5 '{"state": "MERGED"}'
  register <<'EOF'
- `upstream o/r#5 = merged` a pull request.
EOF
  run_watch
  assert_equal status "$status" 0
  assert_equal report "$report" "An entry
  o/r#5: recorded merged, now merged"
}

test_an_upstream_issue_is_read_when_no_pull_request_has_its_number() {
  respond issue/o/r/6 '{"state": "CLOSED"}'
  register <<'EOF'
- `upstream o/r#6 = closed`
EOF
  run_watch
  assert_equal status "$status" 0
  assert_equal line "$(line_for 'o/r#6')" "  o/r#6: recorded closed, now closed"
}

test_an_upstream_line_whose_state_moved_differs() {
  respond pr/o/r/5 '{"state": "MERGED"}'
  register <<'EOF'
- `upstream o/r#5 = open`
EOF
  run_watch
  assert_equal status "$status" 1
  assert_equal line "$(line_for 'o/r#5')" "  o/r#5: recorded open, now merged; differs"
}

test_a_json_line_matching_the_release_file_passes() {
  released o/r v2
  respond 'api/repos/o/r/contents/schema/config.json?ref=v2' '{"a": {"type": "string"}}'
  register <<'EOF'
- `json o/r schema/config.json .a.type = "string"`
EOF
  run_watch
  assert_equal status "$status" 0
  assert_equal line "$(line_for 'config.json')" \
    '  o/r@v2 schema/config.json .a.type: recorded "string", now "string"'
}

test_a_json_line_whose_value_changed_differs() {
  released o/r v2
  respond 'api/repos/o/r/contents/schema/config.json?ref=v2' '{"a": {"type": ["string", "array"]}}'
  register <<'EOF'
- `json o/r schema/config.json .a.type = "string"`
EOF
  run_watch
  assert_equal status "$status" 1
  assert_equal line "$(line_for 'config.json')" \
    '  o/r@v2 schema/config.json .a.type: recorded "string", now ["string","array"]; differs'
}

test_a_text_line_matching_the_release_file_passes() {
  released o/r v2
  respond 'api/repos/o/r/contents/ui/a.ts?ref=v2' 'label: "legacy LLM backend",'
  register <<'EOF'
- `text o/r ui/a.ts legacy LLM backend = present`
- `text o/r ui/a.ts concurrencyLimit = absent`
EOF
  run_watch
  assert_equal status "$status" 0
  assert_equal report "$report" 'An entry
  o/r@v2 ui/a.ts "legacy LLM backend": recorded present, now present
  o/r@v2 ui/a.ts "concurrencyLimit": recorded absent, now absent'
}

test_a_text_line_whose_string_left_differs() {
  released o/r v2
  respond 'api/repos/o/r/contents/ui/a.ts?ref=v2' 'label: "LLM backend",'
  register <<'EOF'
- `text o/r ui/a.ts legacy LLM backend = present`
EOF
  run_watch
  assert_equal status "$status" 1
  assert_equal line "$(line_for 'ui/a.ts')" \
    '  o/r@v2 ui/a.ts "legacy LLM backend": recorded present, now absent; differs'
}

test_a_release_contains_line_matching_the_comparison_passes() {
  released o/r v2
  respond 'api/repos/o/r/compare/2a7c2ec473a221c643ff5c3adab77351bac65e71...v2' '{"status": "behind"}'
  respond 'api/repos/o/r/compare/d7e9f0d1f14d6e0b59bca4f0a46a96a856ad03e6...v2' '{"status": "identical"}'
  register <<'EOF'
- `release-contains o/r 2a7c2ec473a221c643ff5c3adab77351bac65e71 = absent`
- `release-contains o/r d7e9f0d1f14d6e0b59bca4f0a46a96a856ad03e6 = present`
EOF
  run_watch
  assert_equal status "$status" 0
  assert_equal report "$report" 'An entry
  o/r@v2 contains 2a7c2ec473a2: recorded absent, now absent
  o/r@v2 contains d7e9f0d1f14d: recorded present, now present'
}

test_a_release_contains_line_whose_release_took_the_commit_differs() {
  released o/r v3
  respond 'api/repos/o/r/compare/2a7c2ec473a221c643ff5c3adab77351bac65e71...v3' '{"status": "ahead"}'
  register <<'EOF'
- `release-contains o/r 2a7c2ec473a221c643ff5c3adab77351bac65e71 = absent`
EOF
  run_watch
  assert_equal status "$status" 1
  assert_equal line "$(line_for 'contains')" \
    '  o/r@v3 contains 2a7c2ec473a2: recorded absent, now present; differs'
}

test_a_line_gh_cannot_read_is_unreadable_and_differs() {
  respond pr/o/r/5 '{"state": "OPEN"}'
  released o/r v2
  register <<'EOF'
- `upstream o/r#5 = open`
- `upstream o/r#404 = open`
- `text o/r gone.ts anything = absent`
EOF
  run_watch
  assert_equal status "$status" 1
  assert_equal report "$report" 'An entry
  o/r#5: recorded open, now open
  o/r#404: recorded open, now unreadable; differs
  o/r@v2 gone.ts "anything": recorded absent, now unreadable; differs'
}

test_lines_not_in_the_four_forms_are_ignored() {
  respond pr/o/r/5 '{"state": "OPEN"}'
  register <<'EOF'
Prose naming `upstream o/r#1 = open` outside a list item.
- `other o/r#2 = open` a span of another form.
- Text before `upstream o/r#3 = open`, not the item's first span.
- `upstream o/r#5 = open`
EOF
  run_watch
  assert_equal status "$status" 0
  assert_equal report "$report" "An entry
  o/r#5: recorded open, now open"
  assert_equal calls "$(calls)" "gh pr view 5 -R o/r --json state --jq .state | ascii_downcase"
}

test_the_latest_release_tag_is_read_once_per_repository() {
  local repo
  for repo in o/r o/s; do
    released "$repo" v2
    respond "api/repos/$repo/contents/a.json?ref=v2" '{"a": 1}'
    respond "api/repos/$repo/compare/abc...v2" '{"status": "ahead"}'
  done
  register <<'EOF'
- `json o/r a.json .a = 1`
- `text o/r a.json "a" = present`
- `release-contains o/r abc = present`
- `json o/s a.json .a = 1`
- `release-contains o/s abc = present`
EOF
  run_watch
  assert_equal status "$status" 0
  assert_equal "release reads" "$(grep '^gh release view' <<<"$(calls)")" \
    "gh release view -R o/r --json tagName --jq .tagName
gh release view -R o/s --json tagName --jq .tagName"
}

run_tests
