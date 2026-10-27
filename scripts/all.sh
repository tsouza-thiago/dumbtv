#!/usr/bin/env bash
# A passada completa, na ordem certa. Sem --apply, tudo é simulação.
# Uso: ./scripts/all.sh [--apply] [-y]
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/lib.sh"
parse_flags "$@"
load_conf

"$DIR/preflight.sh"           || exit 1
"$DIR/measure.sh" antes       || exit 1
"$DIR/debloat.sh" "$@"        || exit 1
if [[ $LOCKDOWN == 1 ]]; then "$DIR/lockdown.sh" "$@" || exit 1; fi
[[ $APPLY == 1 ]] || exit 0
"$DIR/verify.sh"
note "espere uns 5 minutos e rode: ./scripts/measure.sh depois"
