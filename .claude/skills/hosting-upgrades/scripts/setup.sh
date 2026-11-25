#!/usr/bin/env bash
# setup prints the permission rules each hosting-upgrades mode needs, survey's and then measure's,
# or the one mode given, each marked present or missing against the permissions.allow lists of
# ~/.claude/settings.json, .claude/settings.json, and .claude/settings.local.json, a present rule
# with the file and the listed rule that grant it, then the JSON of every missing rule to add to
# .claude/settings.json. A rule is present when a listed rule is the same, is its bare tool name, or
# ends in :* or * and the rule's text begins with what comes before it. The probe's and tailscale's
# rules are one per host descriptor in docs/hosts/, the probe's by the descriptor's file name and
# tailscale's by its SSH short name, or the given host's alone. It writes nothing, and exits 2 on
# an unknown argument or a host with no descriptor, before it reads a settings file.
#
#   .claude/skills/hosting-upgrades/scripts/setup.sh [survey|measure [<host>]]
#
# See .claude/skills/hosting-upgrades/setup.md
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd) || exit
root=$(cd "$here/../../../.." && pwd) || exit
# shellcheck source=.claude/skills/hosting-upgrades/scripts/descriptors.sh
source "$here/descriptors.sh"

usage() {
  echo "setup: $1" >&2
  echo "usage: setup.sh [survey|measure [<host>]]" >&2
  exit 2
}

modes=(survey measure)
hosts=()
if (($# > 2)); then
  usage "one mode and one host at most"
elif (($# >= 1)); then
  [[ $1 == survey || $1 == measure ]] || usage "unknown mode $1"
  modes=("$1")
  if (($# == 2)); then
    reason=$(descriptor_check "$root" "$2") ||
      usage "$reason; the hosts with a descriptor are: $(descriptor_hosts "$root" | paste -sd ' ' -)"
    hosts=("$2")
  fi
fi
((${#hosts[@]})) || mapfile -t hosts < <(descriptor_hosts "$root")

descriptors=()
short_names=()
for host in "${hosts[@]}"; do
  short=$(descriptor_short_name "$root/docs/hosts/$host.md") || exit 2
  descriptors+=("$host")
  short_names+=("$short")
done

survey_rules() {
  local host
  for host in "${descriptors[@]}"; do
    echo "Bash(.claude/skills/hosting-upgrades/scripts/probe.sh $host)"
  done
  printf '%s\n' "Bash(mise run currency)" "Bash(mise run watch)" "Bash(bin/hosting profile stale)" \
    "Bash(gh release list *)" "Bash(gh release view *)" "Bash(gh search issues *)" \
    "Bash(gh search prs *)" "Bash(gh issue view *)" "Bash(gh pr view *)" \
    "Bash(curl -s https://huggingface.co/*)" "Bash(curl -s https://hub.docker.com/*)" \
    "Bash(curl -s https://raw.githubusercontent.com/*)" \
    "Bash(curl -s https://changelogs.ubuntu.com/*)" "Bash(curl -s https://ubuntu.com/*)" \
    "Bash(curl -s https://archlinux.org/*)" "Bash(curl -s https://www.nist.gov/*)" \
    "Bash(curl -s https://www.aisi.gov.uk/*)" "Bash(jq *)" \
    "WebFetch" "WebSearch" "Edit(.state/upgrades/**)"
}

measure_rules() {
  local host
  for host in "${short_names[@]}"; do
    echo "Bash(tailscale ping -c 1 $host)"
  done
  echo "Edit(docs/findings/**)"
}

allowed=()
granted_in=()
for file in "$HOME/.claude/settings.json" "$root/.claude/settings.json" \
  "$root/.claude/settings.local.json"; do
  [[ -f $file ]] || continue
  while IFS= read -r rule; do
    allowed+=("$rule")
    label=${file/#"$root"\//}
    granted_in+=("${label/#"$HOME"/\~}")
  done < <(jq -r '.permissions.allow[]? // empty' "$file") || exit
done

grants() {
  local need=$1 tool=${1%%(*} text rule=$2 pattern
  text=${need#"$tool"}
  text=${text#(}
  text=${text%)}
  [[ $rule == "$need" || $rule == "$tool" ]] && return 0
  [[ $rule == "$tool("*")" ]] || return 1
  pattern=${rule#"$tool("}
  pattern=${pattern%)}
  [[ $pattern == *:\* ]] && pattern="${pattern%:\*}*"
  # shellcheck disable=SC2053 # The listed rule's wildcards match as a glob.
  [[ $pattern == *\** && $text == $pattern ]]
}

granted_by() {
  local i
  for i in "${!allowed[@]}"; do
    if grants "$1" "${allowed[i]}"; then
      echo "${granted_in[i]}: \"${allowed[i]}\""
      return 0
    fi
  done
  return 1
}

missing=()
report() {
  local rules=() rule by present=0 lines=()
  mapfile -t rules
  for rule in "${rules[@]}"; do
    if by=$(granted_by "$rule"); then
      present=$((present + 1))
      lines+=("  present  \"$rule\"  granted in $by")
    else
      lines+=("  missing  \"$rule\"")
      missing+=("$rule")
    fi
  done
  echo "$1: $present of ${#rules[@]} present."
  printf '%s\n' "${lines[@]}"
}

for mode in "${modes[@]}"; do
  case $mode in
    survey) report "Survey's rules" < <(survey_rules) ;;
    measure)
      ((${#modes[@]} == 2)) || report "Survey's rules, which measure needs too" < <(survey_rules)
      report "Measure's own rules" < <(measure_rules)
      ;;
  esac
done

if ((${#missing[@]})); then
  echo "Add to .claude/settings.json, under permissions.allow:"
  echo
  printf '  "%s",\n' "${missing[@]}" | sed '$ s/,$//'
else
  echo "Every rule is present."
fi
