#!/usr/bin/env bash
# Tests for hosting model list and model prune (hosting_model_list and hosting_model_prune in
# lib/model.sh), over a fake model store in the Hugging Face cache layout, with hf stubbed to list
# and remove its repositories: list shows each model's size and rows, a dry run changes nothing,
# and --yes removes only the models no recorded row serves and the incomplete downloads.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

fake_store() {
  local repo dir
  store=$tmp/store
  for repo in google/gemma-4-E4B-it ibm-granite/granite-embedding-english-r2 old/model; do
    dir=$store/models--${repo//\//--}
    mkdir -p "$dir/blobs" "$dir/snapshots/abc" "$dir/refs"
    echo "$repo" >"$dir/blobs/1111"
    ln -s ../../blobs/1111 "$dir/snapshots/abc/config.json"
    printf abc >"$dir/refs/main"
  done
  echo partial >"$store/models--google--gemma-4-E4B-it/blobs/2222.incomplete"
  echo partial >"$store/models--old--model/blobs/3333.incomplete"
  sed -i "s|^store = .*|store = \"$store\"|" "$clone/classes/strix-halo/profile.toml"
  record "$@"
  # shellcheck disable=SC2016 # The stub's body expands when hf runs.
  write_stub hf '
if [[ $1 == cache && $2 == ls ]]; then
  echo "Hint: Found 1 incomplete download(s)" >&2
  for dir in "$4"/models--*/; do
    name=${dir%/}
    name=${name##*/models--}
    echo "{\"repo_id\": \"${name/--//}\", \"repo_type\": \"model\", \"size\": \"1.5G\"}"
  done | jq -s .
elif [[ $1 == cache && $2 == rm ]]; then
  name=${3#model/}
  rm -rf "$5/models--${name//\//--}"
fi'
}

tree() {
  (cd "$store" && find . | sort && find . -type f -exec md5sum {} + | sort)
}

model() {
  HOSTING_CLASS=strix-halo run_hosting model "$@"
}

test_list_shows_each_models_size_and_rows() {
  fake_store audio
  model list
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "MODEL                                            SIZE       ROWS                 PROFILE ROWS
google/gemma-4-E4B-it                            1.5G       audio                -
ibm-granite/granite-embedding-english-r2         1.5G       -                    embedding
old/model                                        1.5G       -                    -"
}

test_list_of_a_missing_store_shows_no_model() {
  fake_store audio
  rm -rf "$store"
  model list
  assert_equal status "$status" 0
  assert_equal stdout "$out" "MODEL                                            SIZE       ROWS                 PROFILE ROWS"
}

test_prune_without_yes_changes_nothing() {
  local before
  fake_store audio
  before=$(tree)
  model prune
  assert_equal status "$status" 0
  assert_equal stdout "$out" "would remove model ibm-granite/granite-embedding-english-r2 (1.5G)
would remove model old/model (1.5G)
would remove incomplete download $store/models--google--gemma-4-E4B-it/blobs/2222.incomplete
hosting model prune --yes removes them"
  assert_equal tree "$(tree)" "$before"
  assert_equal "hf removals" "$(calls | grep '^hf cache rm' || true)" ""
}

test_prune_yes_removes_only_unused_models_and_incomplete_downloads() {
  fake_store audio embedding
  model prune --yes
  assert_equal status "$status" 0
  assert_equal stdout "$out" "removed model old/model (1.5G)
removed incomplete download $store/models--google--gemma-4-E4B-it/blobs/2222.incomplete"
  assert_equal tree "$(cd "$store" && find . -name 'models--*' -prune -print | sort)" \
    "./models--google--gemma-4-E4B-it
./models--ibm-granite--granite-embedding-english-r2"
  assert_equal "kept blobs" "$(cd "$store" && find . -path '*/blobs/*' | sort)" \
    "./models--google--gemma-4-E4B-it/blobs/1111
./models--ibm-granite--granite-embedding-english-r2/blobs/1111"
}

test_prune_with_nothing_to_remove_says_so() {
  fake_store audio embedding
  rm -rf "$store/models--old--model" "$store/models--google--gemma-4-E4B-it/blobs/2222.incomplete"
  model prune --yes
  assert_equal status "$status" 0
  assert_equal stdout "$out" \
    "nothing to prune: every model in $store is served by a row recorded on this host"
}

test_a_recorded_alias_the_profile_lacks_is_refused_before_hf() {
  local before
  fake_store audio vision
  before=$(tree)
  model prune --yes
  assert_equal status "$status" 1
  assert_contains stderr "$err" "holds vision, which classes/strix-halo/profile.toml has no row for"
  assert_equal calls "$(calls)" ""
  assert_equal tree "$(tree)" "$before"
}

test_prune_takes_only_yes() {
  fake_store audio
  model prune --force
  assert_equal status "$status" 2
  assert_equal stderr "$err" "hosting: model prune takes only --yes
usage: hosting model prune [--yes]"
  model list extra
  assert_equal status "$status" 2
}

run_tests
