#!/usr/bin/env bash
# Baixo risco. Limpa o cache dos apps para liberar armazenamento (o aparelho tem
# só 8 GB, e pouco espaço livre deixa o sistema lento). Os apps recriam o cache;
# o primeiro uso de cada um pode ser um pouco mais lento. Nenhum dado de login some.
# Uso: ./scripts/cache.sh [--apply] [-y]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_flags "$@"
need_device
require_profile
load_conf
acquire_lock

free_data() { dev 'df -h /data' | tr -d '\r' | awk 'NR==2 {print $4}'; }
step "cache dos apps"
note "livre antes   $(free_data)"
confirm "Limpar o cache dos apps em $SERIAL?" || die "cancelado"
acmd pm trim-caches 999G >/dev/null
if [[ $APPLY == 1 ]]; then note "livre depois  $(free_data)"; fi
