#!/usr/bin/env bash
# Tests for the hosting dispatcher: the listing, running a command, and the usage errors, on the
# clone's copy with fixture commands written by each test.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

remove_the_suite_commands() {
  rm -f "$clone"/bin/hosting-*-*
}

test_no_arguments_lists_only_the_usage_with_no_commands() {
  remove_the_suite_commands
  run_hosting
  assert_equal status "$status" 0
  assert_equal stdout "$out" "usage: hosting <group> <verb> [args...]"
  assert_equal stderr "$err" ""
}

test_no_arguments_lists_each_command_with_its_summary() {
  remove_the_suite_commands
  write_command profile validate "Validates the host-class profiles" ':'
  write_command engine install "Starts each named row" ':'
  run_hosting
  assert_equal status "$status" 0
  assert_equal stdout "$out" "usage: hosting <group> <verb> [args...]
  hosting engine install         Starts each named row
  hosting profile validate       Validates the host-class profiles"
}

test_listing_skips_files_that_are_not_executable() {
  remove_the_suite_commands
  write_command engine install "Starts each named row" ':'
  chmod -x "$clone/bin/hosting-engine-install"
  run_hosting
  assert_equal stdout "$out" "usage: hosting <group> <verb> [args...]"
}

test_a_command_runs_with_the_remaining_arguments() {
  write_command profile render "Prints a row" 'printf "[%s]" "$@"; exit 3'
  run_hosting profile render agent "two words"
  assert_equal status "$status" 3
  assert_equal stdout "$out" "[agent][two words]"
}

test_a_link_to_the_dispatcher_runs_commands_from_the_clone() {
  write_command profile render "Prints a row" 'echo rendered'
  ln -s "$clone/bin/hosting" "$tmp/hosting"
  run "$tmp/hosting" profile render
  assert_equal status "$status" 0
  assert_equal stdout "$out" rendered
}

test_an_unknown_command_is_a_usage_error() {
  run_hosting engine frobnicate
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" \
    "hosting: no command 'engine frobnicate'; run hosting with no arguments to list the commands"
}

test_a_group_without_a_verb_is_a_usage_error() {
  run_hosting engine
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" \
    "hosting: 'engine' names no verb; run hosting with no arguments to list the commands
usage: hosting <group> <verb> [args...]"
}

test_a_name_reaching_outside_the_commands_is_unknown() {
  write_command engine install "Starts each named row" 'echo ran'
  mkdir "$clone/bin/hosting-x"
  run_hosting x/../engine install
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
}

test_a_command_usage_error_prints_to_stderr_and_exits_2() {
  write_command engine install "Starts each named row" \
    'hosting_usage_error "engine install needs an alias" "engine install <alias>..."'
  run_hosting engine install
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: engine install needs an alias
usage: hosting engine install <alias>..."
}

run_tests
