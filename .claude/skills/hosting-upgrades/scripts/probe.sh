#!/usr/bin/env bash
# probe reads one host's state over ssh, read-only and without root, for the hosting-upgrades
# skill. It refuses any argument but the name of a host with a descriptor in docs/hosts/ before it
# reaches the host, then runs probe-host.sh there as `ssh <short name> bash -s`, the short name the
# descriptor gives, and prints its labeled sections with every tailnet address and MagicDNS name
# redacted. It exits 2 on a refusal, and with ssh's status otherwise.
#
#   .claude/skills/hosting-upgrades/scripts/probe.sh <host>
#
# See .claude/skills/hosting-upgrades/survey.md
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd) || exit
root=$(cd "$here/../../../.." && pwd) || exit
# shellcheck source=.claude/skills/hosting-upgrades/scripts/descriptors.sh
source "$here/descriptors.sh"

refuse() {
  echo "probe: $1" >&2
  echo "probe: the hosts with a descriptor are: $(descriptor_hosts "$root" | paste -sd ' ' -)" >&2
  exit 2
}

redact() {
  sed -E \
    -e 's/(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])(\.[0-9]{1,3}){2}/\1[tailnet-ipv4]/g' \
    -e 's/[Ff][Dd]7[Aa]:115[Cc]:[Aa]1[Ee]0(:[0-9A-Fa-f]{0,4})*/[tailnet-ipv6]/g' \
    -e 's/([A-Za-z0-9-]+\.)+[Tt][Ss]\.[Nn][Ee][Tt]\.?/[magicdns-name]/g'
}

(($# == 1)) || refuse "usage: probe.sh <host>"
host=$1
[[ $host =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || refuse "$host is not a short host name"
[[ $host != template ]] || refuse "template.md is the descriptor template, not a host"
descriptor=$root/docs/hosts/$host.md
[[ -f $descriptor ]] || refuse "no descriptor docs/hosts/$host.md"
short=$(descriptor_short_name "$descriptor") || exit 2

ssh -o BatchMode=yes -- "$short" bash -s <"$here/probe-host.sh" | redact
exit "${PIPESTATUS[0]}"
