#!/usr/bin/env bash
# Tests for hosting model pull (hosting_model_pull in lib/model.sh), with hf stubbed to log its
# calls and whether it may send the host's token: it downloads into the class's store, with the
# token only when hf auth whoami accepts it, and says clearly when a repository is gated.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

# Stubs hf: hf auth whoami succeeds when the first argument is "signed-in", and hf download logs
# whether the implicit token is off, then runs the body given, if any.
stub_hf() {
  write_stub hf "
if [[ \$1 == auth ]]; then [[ $1 == signed-in ]]; exit; fi
echo \"token-off=\${HF_HUB_DISABLE_IMPLICIT_TOKEN:-} cache=\$HF_HUB_CACHE\" >>$tmp/calls
${2:-}"
}

pull() {
  HOSTING_CLASS=strix-halo run_hosting model pull "$@"
}

test_pull_downloads_into_the_store_with_the_token() {
  stub_hf signed-in 'echo /srv/models/models--google--gemma-4-E4B-it/snapshots/abc'
  pull google/gemma-4-E4B-it
  assert_equal status "$status" 0
  assert_equal stdout "$out" /srv/models/models--google--gemma-4-E4B-it/snapshots/abc
  assert_equal calls "$(calls)" "hf auth whoami
hf download google/gemma-4-E4B-it --cache-dir /srv/models
token-off= cache=/srv/models"
}

test_pull_without_a_token_downloads_unauthenticated() {
  stub_hf signed-out
  pull google/gemma-4-E4B-it
  assert_equal status "$status" 0
  assert_contains calls "$(calls)" "token-off=1 cache=/srv/models"
}

test_a_gated_repository_fails_clearly() {
  stub_hf signed-out "echo \"Error: Access denied. Model 'meta-llama/Llama-3.2-1B' requires approval.\" >&2; exit 1"
  pull meta-llama/Llama-3.2-1B
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "Error: Access denied. Model 'meta-llama/Llama-3.2-1B' requires approval.
hosting: meta-llama/Llama-3.2-1B is a gated repository: an account granted access at https://huggingface.co/meta-llama/Llama-3.2-1B must hold the token hf auth login stores on this host (hf auth whoami finds none)"
}

test_another_failure_is_hfs_own() {
  stub_hf signed-in "echo \"Error: Model 'nobody/none' not found.\" >&2; exit 1"
  pull nobody/none
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "Error: Model 'nobody/none' not found."
}

test_a_repository_not_owner_slash_name_is_refused_before_hf() {
  stub_hf signed-in
  pull 'google/gemma 4'
  assert_equal status "$status" 1
  assert_equal stderr "$err" "hosting: google/gemma 4 is not a Hugging Face model repository, <owner>/<name>"
  assert_equal calls "$(calls)" ""
}

test_pull_takes_exactly_one_repository() {
  stub_hf signed-in
  pull
  assert_equal status "$status" 2
  assert_equal stderr "$err" "hosting: model pull takes one repository
usage: hosting model pull <repo>"
}

run_tests
