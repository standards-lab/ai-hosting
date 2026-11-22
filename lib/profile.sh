#!/usr/bin/env bash
# The host-class profiles: where each class's profile lives in the clone, and the validator every
# command that reads a profile runs before its first effect. Sourced by lib/hosting.sh. See
# classes/README.md.

# The directory holding one directory per host class, each holding the class's profile and its
# runbook.
HOSTING_PROFILES=$(cd "$(dirname "${BASH_SOURCE[0]}")/../classes" 2>/dev/null && pwd)

# Prints the path of the class's profile: hosting_profile_path <class>.
hosting_profile_path() {
  echo "$HOSTING_PROFILES/$1/profile.toml"
}

# Runs mikefarah yq, the TOML reader mise.toml pins, with the arguments given: the first yq on PATH
# that is mikefarah's, since another yq may stand before mise's. Refuses when none is.
hosting_yq() {
  local candidate
  for candidate in $(type -ap yq); do
    if "$candidate" --version 2>/dev/null | grep -q 'mikefarah/yq'; then
      "$candidate" "$@"
      return
    fi
  done
  echo "hosting: no yq on PATH is mikefarah yq, the TOML reader mise.toml pins; run mise install" \
    "and put mise's tools on PATH" >&2
  return 1
}

# Validates the profile at the path given, printing each error to stderr as
# "hosting: <name>: <key path>: <message>", every error at once, and fails if it has any. The name
# is the path, unless a second argument names it: hosting_profile_validate <path> [name].
hosting_profile_validate() {
  local name=${2:-$1} json errors line
  hosting_yq --version >/dev/null || return
  if ! json=$(hosting_yq -p toml -o json '.' "$1" 2>&1); then
    echo "hosting: $name: ${json#Error: }" >&2
    return 1
  fi
  errors=$(jq -r -f "$(dirname "${BASH_SOURCE[0]}")/profile.jq" <<<"$json") || return
  if [[ -n $errors ]]; then
    while IFS= read -r line; do
      echo "hosting: $name: $line" >&2
    done <<<"$errors"
    return 1
  fi
}

# Checks the classes directory's layout: one directory for each of HOSTING_CLASSES, none for any
# other class, each holding its profile.toml and at most its runbook beside it. Prints each
# error to stderr, every one at once, and fails if it finds any.
hosting_profile_layout() {
  local fail=0 entry class file
  if [[ -z $HOSTING_PROFILES ]]; then
    echo "hosting: classes: no classes directory in this clone" >&2
    return 1
  fi
  for class in "${HOSTING_CLASSES[@]}"; do
    if [[ ! -f $HOSTING_PROFILES/$class/profile.toml ]]; then
      echo "hosting: classes/$class/profile.toml: missing" >&2
      fail=1
    fi
  done
  for entry in "$HOSTING_PROFILES"/*/; do
    class=$(basename "$entry")
    if [[ " ${HOSTING_CLASSES[*]} " != *" $class "* ]]; then
      echo "hosting: classes/$class: not a host class; the classes are ${HOSTING_CLASSES[*]}" >&2
      fail=1
      continue
    fi
    for file in "$entry"* "$entry".[!.]*; do
      [[ -e $file ]] || continue
      case ${file##*/} in
        profile.toml | runbook.md) ;;
        *)
          echo "hosting: classes/$class/${file##*/}: a class directory holds only profile.toml" \
            "and runbook.md" >&2
          fail=1
          ;;
      esac
    done
  done
  return "$fail"
}

# Validates every class's profile, after the layout (hosting_profile_layout), printing each valid
# profile's name and every error at once, and fails if any is invalid.
hosting_profile_validate_all() {
  local fail=0 class name
  hosting_profile_layout || fail=1
  for class in "${HOSTING_CLASSES[@]}"; do
    name=classes/$class/profile.toml
    [[ -f $HOSTING_PROFILES/$class/profile.toml ]] || continue
    if hosting_profile_validate "$(hosting_profile_path "$class")" "$name"; then
      echo "$name: valid"
    else
      fail=1
    fi
  done
  return "$fail"
}
