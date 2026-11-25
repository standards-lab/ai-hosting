#!/usr/bin/env bash
# audio-clips writes the audio bench's speech from the LibriSpeech dummy set, in the bench
# environment, with the Python of its GuideLLM: for the audio capacity scenarios, each clip and each
# 28 to 30 s window of consecutive clips as a 16 kHz WAV, and the JSONL rows the scenarios read,
# under the output directory; for the probe, clips of about 10, 30, 60 and 120 s into the directory
# given. Each WAV has its reference transcript beside it. It exits 2 on a refusal.
#
#   bench/audio-clips.sh scenarios [--output <dir>]
#   bench/audio-clips.sh probe <dir>
#
# See bench/README.md.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd) || exit

usage() {
  echo "audio-clips: $1" >&2
  echo "usage: bench/audio-clips.sh scenarios [--output <dir>] | bench/audio-clips.sh probe <dir>" >&2
  exit 2
}

case ${1-} in
  scenarios)
    output=$root/.state/bench/audio
    if (($# == 3)) && [[ $2 == --output ]]; then
      output=$3
    elif (($# != 1)); then
      usage "scenarios takes only --output <dir>"
    fi
    ;;
  probe)
    (($# == 2)) || usage "probe takes one directory"
    output=$2
    ;;
  '') usage "no scenarios or probe" ;;
  *) usage "unknown $1" ;;
esac
[[ -n $output ]] || usage "the output directory is empty"

if ! guidellm=$(command -v guidellm); then
  echo "audio-clips: guidellm is not on PATH; run in the bench environment, MISE_ENV=bench mise exec --" >&2
  exit 2
fi
python=$(dirname "$(readlink -f "$guidellm")")/python
if [[ ! -x $python ]]; then
  echo "audio-clips: no Python beside $guidellm" >&2
  exit 2
fi

exec "$python" "$root/bench/audio-clips.py" "$1" --output="$output"
