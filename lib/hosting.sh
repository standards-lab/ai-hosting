#!/usr/bin/env bash
# The hosting suite's shell library, sourced by the hosting dispatcher and every
# hosting-<group>-<verb> command, which stay thin consumers of it. It holds the usage error every
# command reports the same way and the host-class detection the commands that differ by class
# share. See context/hosting-suite.md.

# The closed list of host classes, which the profiles, the detection, and HOSTING_CLASS share.
HOSTING_CLASSES=(gb10 strix-halo)

# Prints the message given to stderr, then the usage given, when one is, and exits 2.
hosting_usage_error() {
  echo "hosting: $1" >&2
  if [[ -n ${2:-} ]]; then
    echo "usage: hosting $2" >&2
  fi
  exit 2
}

# Prints the class whose GPU a DRM card under HOSTING_SYSROOT's /sys reports by its PCI vendor and
# device IDs: gb10 for the NVIDIA GB10 (0x10de:0x2e12), strix-halo for the AMD Strix Halo
# (0x1002:0x1586). Fails, printing nothing, on a host matching neither.
# Adapted from spike-model-engines (6ce3210): host/vllm.sh's vllm_flavor, which took any host
# without AMD's vendor ID as cuda; here each class has its own positive probe, by the IDs
# spike-hosting-upgrades' host reports recorded, gb10-1's at 26b6c37 and the Framework's at 12067db.
hosting_probe_class() {
  local card ids
  for card in "${HOSTING_SYSROOT:-}"/sys/class/drm/card*/device; do
    [[ -r $card/vendor && -r $card/device ]] || continue
    ids=$(<"$card/vendor"):$(<"$card/device")
    case $ids in
      0x10de:0x2e12) echo gb10 && return ;;
      0x1002:0x1586) echo strix-halo && return ;;
    esac
  done
  return 1
}

# Sets and exports HOSTING_CLASS, the host's class: HOSTING_CLASS as given, when set, refused
# unless it is one of HOSTING_CLASSES, or else the probe's (hosting_probe_class), refusing a host
# matching neither class. A command calls it once, and the commands it runs inherit the class, so
# the host is probed once per call. Touches neither Docker nor the host.
hosting_class() {
  local class
  if [[ -n ${HOSTING_CLASS:-} ]]; then
    for class in "${HOSTING_CLASSES[@]}"; do
      [[ $HOSTING_CLASS == "$class" ]] && export HOSTING_CLASS && return
    done
    echo "hosting: HOSTING_CLASS is $HOSTING_CLASS, which is none of ${HOSTING_CLASSES[*]}" >&2
    return 1
  fi
  if ! class=$(hosting_probe_class); then
    echo "hosting: this host is no known class: no GPU here is gb10's NVIDIA GB10 (PCI" \
      "10de:2e12) or strix-halo's AMD Strix Halo (PCI 1002:1586); HOSTING_CLASS names the" \
      "class to override the probe" >&2
    return 1
  fi
  export HOSTING_CLASS=$class
}

# Detects the host class (hosting_class), then runs the command's private function for it: the
# function name given with the class appended, a hyphen read as an underscore, such as
# engine_memory_gb10 or engine_memory_strix_halo, with the remaining arguments.
hosting_per_class() {
  hosting_class || return
  "$1_${HOSTING_CLASS//-/_}" "${@:2}"
}
