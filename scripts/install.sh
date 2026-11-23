#!/usr/bin/env bash
# Links ~/.local/bin/hosting to this clone's bin/hosting, the suite's one command. Refuses, changing
# nothing, when that path holds anything other than a link into this clone. Detects no host class
# and touches neither Docker nor the host. See context/hosting-suite.md.
set -euo pipefail

clone=$(dirname "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")")
link=$HOME/.local/bin/hosting

if [[ -e $link || -L $link ]] && [[ $(readlink -f -- "$link") != "$clone"/* ]]; then
  echo "install: $link is not a link into $clone; remove it, or run mise run uninstall from the" \
    "clone it links to, then install again" >&2
  exit 1
fi
mkdir -p "$(dirname "$link")"
ln -sfn "$clone/bin/hosting" "$link"
echo "install: $link -> $clone/bin/hosting"
