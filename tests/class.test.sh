#!/usr/bin/env bash
# Tests for host-class detection (hosting_class and hosting_per_class in lib/hosting.sh), through
# fixture commands run by the dispatcher, against a fake system tree, with docker, nvidia-smi, and
# amdgpu_top stubbed so a test sees any call to them.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

stub_host_commands() {
  write_stub docker
  write_stub nvidia-smi
  write_stub amdgpu_top
}

write_class_command() {
  write_command engine memory "GPU memory per process" '
engine_memory_gb10() { echo "gb10 $*"; }
engine_memory_strix_halo() { echo "strix-halo $*"; }
hosting_per_class engine_memory "$@"'
}

test_a_gb10_gpu_detects_gb10() {
  stub_host_commands
  fake_gpu 0x10de 0x2e12
  write_class_command
  run_hosting engine memory one
  assert_equal status "$status" 0
  assert_equal stdout "$out" "gb10 one"
  assert_equal calls "$(calls)" ""
}

test_a_strix_halo_gpu_detects_strix_halo() {
  stub_host_commands
  fake_gpu 0x1002 0x1586
  write_class_command
  run_hosting engine memory
  assert_equal status "$status" 0
  assert_equal stdout "$out" "strix-halo "
  assert_equal calls "$(calls)" ""
}

test_the_class_gpu_is_found_beside_another_card() {
  fake_gpu 0x8086 0x56a0
  fake_gpu 0x1002 0x1586
  write_class_command
  run_hosting engine memory
  assert_equal stdout "$out" "strix-halo "
}

test_a_host_matching_neither_class_is_refused_before_docker() {
  stub_host_commands
  fake_gpu 0x10de 0x2684
  fake_gpu 0x1002 0x744c
  write_class_command
  run_hosting engine memory
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_contains stderr "$err" "this host is no known class"
  assert_equal calls "$(calls)" ""
}

test_a_host_with_no_gpu_is_refused() {
  write_class_command
  run_hosting engine memory
  assert_equal status "$status" 1
  assert_contains stderr "$err" "this host is no known class"
}

test_hosting_class_overrides_the_probe() {
  fake_gpu 0x10de 0x2e12
  write_class_command
  HOSTING_CLASS=strix-halo run_hosting engine memory
  assert_equal status "$status" 0
  assert_equal stdout "$out" "strix-halo "
}

test_hosting_class_overrides_on_a_host_matching_neither() {
  write_class_command
  HOSTING_CLASS=gb10 run_hosting engine memory
  assert_equal status "$status" 0
  assert_equal stdout "$out" "gb10 "
}

test_hosting_class_outside_the_list_is_refused() {
  stub_host_commands
  fake_gpu 0x10de 0x2e12
  write_class_command
  HOSTING_CLASS=gb20 run_hosting engine memory
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "hosting: HOSTING_CLASS is gb20, which is none of gb10 strix-halo"
  assert_equal calls "$(calls)" ""
}

test_the_host_is_probed_once_per_call() {
  fake_gpu 0x10de 0x2e12
  write_command engine install "Starts each named row" "
hosting_class
echo \"\$HOSTING_CLASS\"
rm -r '$sysroot/sys'
hosting_class
echo \"\$HOSTING_CLASS\"
'$clone/bin/hosting' model pull"
  write_command model pull "Downloads a model" "hosting_class; echo \"pull \$HOSTING_CLASS\""
  run_hosting engine install
  assert_equal status "$status" 0
  assert_equal stdout "$out" "gb10
gb10
pull gb10"
}

test_a_command_that_does_not_differ_by_class_runs_on_any_host() {
  write_command profile validate "Validates the host-class profiles" 'echo validated'
  run_hosting profile validate
  assert_equal status "$status" 0
  assert_equal stdout "$out" validated
}

test_the_listing_never_detects() {
  write_class_command
  run_hosting
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
}

run_tests
