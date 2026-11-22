#!/usr/bin/env bash
# Tests for mise run install and mise run uninstall, run on the clone's copy under the temporary
# HOME, so the link they write or remove is the temporary ~/.local/bin/hosting.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

run_mise() {
  run bash -c 'cd "$1" && mise run --quiet "$2"' mise "$clone" "$1"
}

link() {
  echo "$HOME/.local/bin/hosting"
}

test_install_links_the_one_command() {
  run_mise install
  assert_equal status "$status" 0
  assert_equal link "$(readlink "$(link)")" "$clone/bin/hosting"
  assert_equal "linked files" "$(ls "$HOME/.local/bin")" hosting
}

test_the_installed_link_runs_the_suite() {
  write_command profile validate "Validates the host-class profiles" 'echo validated'
  run_mise install
  run "$(link)" profile validate
  assert_equal stdout "$out" validated
}

test_install_again_keeps_the_link() {
  run_mise install
  run_mise install
  assert_equal status "$status" 0
  assert_equal link "$(readlink "$(link)")" "$clone/bin/hosting"
}

test_install_refuses_a_link_into_another_clone() {
  mkdir -p "$HOME/.local/bin" "$tmp/other/bin"
  ln -s "$tmp/other/bin/hosting" "$(link)"
  run_mise install
  assert_equal status "$status" 1
  assert_contains stderr "$err" "is not a link into $clone"
  assert_equal link "$(readlink "$(link)")" "$tmp/other/bin/hosting"
}

test_install_refuses_a_file() {
  mkdir -p "$HOME/.local/bin"
  echo mine >"$(link)"
  run_mise install
  assert_equal status "$status" 1
  assert_equal file "$(<"$(link)")" mine
}

test_uninstall_removes_the_link_into_this_clone() {
  run_mise install
  run_mise uninstall
  assert_equal status "$status" 0
  [[ ! -e $(link) && ! -L $(link) ]] || fail "the link is still present"
}

test_uninstall_leaves_a_link_into_another_clone() {
  mkdir -p "$HOME/.local/bin" "$tmp/other/bin"
  ln -s "$tmp/other/bin/hosting" "$(link)"
  run_mise uninstall
  assert_equal status "$status" 0
  assert_equal link "$(readlink "$(link)")" "$tmp/other/bin/hosting"
}

test_uninstall_leaves_a_file() {
  mkdir -p "$HOME/.local/bin"
  echo mine >"$(link)"
  run_mise uninstall
  assert_equal status "$status" 0
  assert_equal file "$(<"$(link)")" mine
}

test_uninstall_with_nothing_installed_succeeds() {
  run_mise uninstall
  assert_equal status "$status" 0
}

test_uninstall_never_detects_the_class() {
  run_mise install
  HOSTING_CLASS=gb20 run_mise uninstall
  assert_equal status "$status" 0
  [[ ! -L $(link) ]] || fail "the link is still present"
}

run_tests
