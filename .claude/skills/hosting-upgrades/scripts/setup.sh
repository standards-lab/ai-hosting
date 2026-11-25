#!/usr/bin/env bash
# setup prints the permission rules each hosting-upgrades mode needs, survey's and then measure's,
# or the one mode given, each marked present or missing against the permissions.allow lists of
# .claude/settings.json and .claude/settings.local.json, then the JSON of every missing rule to add
# to .claude/settings.json. A rule is present when a listed rule is the same, is its bare tool name,
# or ends in :* or * and the rule's text begins with what comes before it. The probe's and
# tailscale's rules are one per host descriptor in docs/hosts/. It writes nothing, and exits 2 on an
# unknown argument.
#
#   .claude/skills/hosting-upgrades/scripts/setup.sh [survey|measure]
#
# See .claude/skills/hosting-upgrades/setup.md
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd) || exit
root=$(cd "$here/../../../.." && pwd) || exit
# shellcheck source=.claude/skills/hosting-upgrades/scripts/descriptors.sh
source "$here/descriptors.sh"

usage() {
  echo "setup: $1" >&2
  echo "usage: setup.sh [survey|measure]" >&2
  exit 2
}

modes=(survey measure)
if (($# > 1)); then
  usage "one mode at most"
elif (($# == 1)); then
  [[ $1 == survey || $1 == measure ]] || usage "unknown mode $1"
  modes=("$1")
fi

hosts=()
while IFS= read -r host; do
  short=$(descriptor_short_name "$root/docs/hosts/$host.md") || exit 2
  hosts+=("$short")
done < <(descriptor_hosts "$root")

survey_rules() {
  local host
  for host in "${hosts[@]}"; do
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
  for host in "${hosts[@]}"; do
    echo "Bash(tailscale ping -c 1 $host)"
  done
  echo "Edit(docs/findings/**)"
}

allowed=()
for file in "$root/.claude/settings.json" "$root/.claude/settings.local.json"; do
  [[ -f $file ]] || continue
  while IFS= read -r rule; do
    allowed+=("$rule")
  done < <(jq -r '.permissions.allow[]? // empty' "$file") || exit
done

covered() {
  local need=$1 tool=${1%%(*} text rule pattern
  text=${need#"$tool"}
  text=${text#(}
  text=${text%)}
  for rule in "${allowed[@]}"; do
    [[ $rule == "$need" || $rule == "$tool" ]] && return 0
    [[ $rule == "$tool("*")" ]] || continue
    pattern=${rule#"$tool("}
    pattern=${pattern%)}
    [[ $pattern == *:\* ]] && pattern="${pattern%:\*}*"
    # shellcheck disable=SC2053 # The listed rule's wildcards match as a glob.
    [[ $pattern == *\** && $text == $pattern ]] && return 0
  done
  return 1
}

missing=()
report() {
  local rules=() rule present=0 lines=()
  mapfile -t rules
  for rule in "${rules[@]}"; do
    if covered "$rule"; then
      present=$((present + 1))
      lines+=("  present  \"$rule\"")
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
      [[ ${#modes[@]} == 2 ]] || report "Survey's rules, which measure needs too" < <(survey_rules)
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
