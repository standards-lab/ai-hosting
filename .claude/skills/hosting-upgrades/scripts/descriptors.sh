#!/usr/bin/env bash
# The host descriptors the hosting-upgrades scripts read, sourced: descriptor_hosts <root> lists the
# descriptors in the repository's docs/hosts/ by name, leaving out the template, descriptor_check
# <root> <host> prints why a host names no descriptor and fails, or prints nothing, and
# descriptor_short_name prints the SSH short name a descriptor's "SSH short name" section gives,
# refusing one that is not a short host name, such as a MagicDNS name or an ssh option.
# See docs/hosts/template.md

descriptor_hosts() {
  local file name
  for file in "$1"/docs/hosts/*.md; do
    [[ -f $file ]] || continue
    name=${file##*/}
    name=${name%.md}
    [[ $name == template ]] || echo "$name"
  done
}

descriptor_check() {
  if [[ ! $2 =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
    echo "$2 is not a short host name"
  elif [[ $2 == template ]]; then
    echo "template.md is the descriptor template, not a host"
  elif [[ ! -f $1/docs/hosts/$2.md ]]; then
    echo "no descriptor docs/hosts/$2.md"
  else
    return 0
  fi
  return 1
}

descriptor_short_name() {
  local name
  name=$(awk '
    /^## / { inside = ($0 == "## SSH short name"); next }
    inside && match($0, /`[^`]+`/) { print substr($0, RSTART + 1, RLENGTH - 2); exit }' "$1")
  if [[ ! $name =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
    echo "${1##*/}'s SSH short name [$name] is not a short host name" >&2
    return 1
  fi
  echo "$name"
}
