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

# Runs jq with the program given, which may call lib/profile.jq's definitions, and the remaining
# arguments, printing raw strings.
hosting_profile_jq() {
  jq -r -L "$(dirname "${BASH_SOURCE[0]}")" "include \"profile\"; $1" "${@:2}"
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
  errors=$(hosting_profile_jq 'profile_errors | "\(.path | key_path): \(.message)"' <<<"$json") ||
    return
  if [[ -n $errors ]]; then
    while IFS= read -r line; do
      echo "hosting: $name: $line" >&2
    done <<<"$errors"
    return 1
  fi
}

# Checks the classes directory's layout: one directory for each of HOSTING_CLASSES, none for any
# other class, each holding its profile.toml and its runbook, and nothing else. Prints each
# error to stderr, every one at once, and fails if it finds any.
hosting_profile_layout() {
  local fail=0 entry class file
  if [[ -z $HOSTING_PROFILES ]]; then
    echo "hosting: classes: no classes directory in this clone" >&2
    return 1
  fi
  for class in "${HOSTING_CLASSES[@]}"; do
    for file in profile.toml runbook.md; do
      if [[ ! -f $HOSTING_PROFILES/$class/$file ]]; then
        echo "hosting: classes/$class/$file: missing" >&2
        fail=1
      fi
    done
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

# Loads the host's class profile, which a command validates before its first effect: detects the
# class (hosting_class), validates the class's profile, and holds its path in HOSTING_PROFILE, its
# name in HOSTING_PROFILE_NAME, and the profile decoded to JSON in HOSTING_PROFILE_JSON. Fails, the
# errors printed, when the profile is invalid.
hosting_profile_load() {
  hosting_class || return
  HOSTING_PROFILE=$(hosting_profile_path "$HOSTING_CLASS")
  HOSTING_PROFILE_NAME=classes/$HOSTING_CLASS/profile.toml
  hosting_profile_validate "$HOSTING_PROFILE" "$HOSTING_PROFILE_NAME" || return
  HOSTING_PROFILE_JSON=$(hosting_yq -p toml -o json '.' "$HOSTING_PROFILE")
}

# Refuses an alias the loaded profile (hosting_profile_load) has no row for, listing its aliases.
hosting_profile_alias() {
  local aliases
  aliases=$(jq -r '[.rows[].alias] | join(" ")' <<<"$HOSTING_PROFILE_JSON")
  if [[ " $aliases " != *" $1 "* ]]; then
    echo "hosting: $HOSTING_PROFILE_NAME has no row $1; its aliases are $aliases" >&2
    return 1
  fi
}

# Sets one field of the row with the alias given in the loaded profile (hosting_profile_load) and
# writes the profile in place, only when the edited profile validates: hosting_profile_set <alias>
# <field> <value>. The field is a row's key path in the schema's dotted form, such as cap or
# load.target; a number field's value is read as a number, flags' as words split on spaces, and
# any other's as text. Refuses an unknown alias or field, and an edit that fails validation,
# printing its errors and leaving the profile byte-identical.
hosting_profile_set() {
  local kind value candidate
  hosting_profile_alias "$1" || return
  # shellcheck disable=SC2016 # $field is jq's, bound by --arg.
  kind=$(hosting_profile_jq '
    if number_fields | index([$field]) then "number"
    elif list_fields | index([$field]) then "list"
    elif settable_fields | index([$field]) then "text"
    else "" end' -n --arg field "$2")
  if [[ -z $kind ]]; then
    echo "hosting: $2 is no field of a row; see classes/README.md for a row's keys" >&2
    return 1
  fi
  case $kind in
    number) value='env(HOSTING_SET_VALUE)' ;;
    list) value='strenv(HOSTING_SET_VALUE) | split(" ")' ;;
    text) value='strenv(HOSTING_SET_VALUE)' ;;
  esac
  candidate=$(mktemp) || return
  cp "$HOSTING_PROFILE" "$candidate"
  if HOSTING_SET_ALIAS=$1 HOSTING_SET_VALUE=$3 hosting_yq -p toml -o toml -i \
    "(.rows[] | select(.alias == strenv(HOSTING_SET_ALIAS))).$2 = ($value)" "$candidate" &&
    hosting_profile_validate "$candidate" "$HOSTING_PROFILE_NAME"; then
    cp "$candidate" "$HOSTING_PROFILE"
    rm -f "$candidate"
    return
  fi
  rm -f "$candidate"
  return 1
}
