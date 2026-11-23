#!/usr/bin/env bash
# retrieval runs MTEB's BelebeleRetrieval against an embedding row's /v1/embeddings, in the bench
# environment, and writes MTEB's result for each subset under the output directory. It exits 2 on
# a refusal.
#
#   bench/retrieval.sh --endpoint <host:port> --query-prefix <prefix> --passage-prefix <prefix>
#     [--output <dir>] [<subset>...]
#
# See bench/README.md.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd) || exit

languages=(eng_Latn bul_Cyrl ell_Grek pol_Latn arb_Arab heb_Hebr jpn_Jpan rus_Cyrl
  zho_Hans hin_Deva spa_Latn fra_Latn kor_Hang)

usage() {
  echo "retrieval: $1" >&2
  echo "usage: bench/retrieval.sh --endpoint <host:port> --query-prefix <prefix> --passage-prefix <prefix> [--output <dir>] [<subset>...]" >&2
  exit 2
}

output=$root/.state/bench/retrieval
subsets=()
while (($#)); do
  case $1 in
    --endpoint | --query-prefix | --passage-prefix | --output)
      (($# >= 2)) || usage "$1 needs a value"
      case $1 in
        --endpoint) endpoint=$2 ;;
        --query-prefix) query_prefix=$2 ;;
        --passage-prefix) passage_prefix=$2 ;;
        --output) output=$2 ;;
      esac
      shift 2
      ;;
    -*) usage "unknown option $1" ;;
    *)
      subsets+=("$1")
      shift
      ;;
  esac
done

[[ -v endpoint ]] || usage "no --endpoint"
[[ $endpoint =~ ^[A-Za-z0-9][A-Za-z0-9.-]*:[0-9]+$ ]] ||
  usage "--endpoint $endpoint is not <host>:<port>"
[[ -v query_prefix ]] || usage "no --query-prefix; give '' for none"
[[ -v passage_prefix ]] || usage "no --passage-prefix; give '' for none"
[[ -n $output ]] || usage "--output is empty"
for subset in "${subsets[@]}"; do
  [[ $subset =~ ^[a-z]{3}_[A-Z][a-z]{3}-[a-z]{3}_[A-Z][a-z]{3}$ ]] ||
    usage "subset $subset is not <lang>_<Script>-<lang>_<Script>"
done

if ((${#subsets[@]} == 0)); then
  for language in "${languages[@]}"; do
    subsets+=("$language-$language")
    if [[ $language != eng_Latn ]]; then
      subsets+=("eng_Latn-$language" "$language-eng_Latn")
    fi
  done
fi

if ! mteb=$(command -v mteb); then
  echo "retrieval: mteb is not on PATH; run in the bench environment, MISE_ENV=bench mise exec --" >&2
  exit 2
fi
python=$(dirname "$(readlink -f "$mteb")")/python
if [[ ! -x $python ]]; then
  echo "retrieval: no Python beside $mteb" >&2
  exit 2
fi

exec "$python" "$root/bench/retrieval.py" --endpoint "$endpoint" \
  --query-prefix="$query_prefix" --passage-prefix="$passage_prefix" --output="$output" \
  -- "${subsets[@]}"
