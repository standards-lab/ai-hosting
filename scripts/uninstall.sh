#!/usr/bin/env bash
# Removes ~/.local/bin/hosting when it is a link into this clone, and leaves anything else at that
# path in place. Never detects the host class. See context/hosting-suite.md.
set -euo pipefail

clone=$(dirname "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")")
link=$HOME/.local/bin/hosting

if [[ ! -e $link && ! -L $link ]]; then
  echo "uninstall: $link is absent; nothing to remove"
elif [[ -L $link && $(readlink -f -- "$link") == "$clone"/* ]]; then
  rm -- "$link"
  echo "uninstall: removed $link"
else
  echo "uninstall: $link is not a link into $clone; left in place"
fi
