#!/usr/bin/env bash
# Opcional (risco médio). Corta a execução em segundo plano dos pacotes que a
# Amazon impede de desativar (data/protected.txt). Não reinicia a TV.
# Fica de fora: o atualizador do sistema e qualquer pacote com UID de sistema.
# Uso: ./scripts/lockdown.sh [--apply] [-y]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_flags "$@"
need_device
require_profile
load_conf
need_snapshot
acquire_lock

confirm "Cortar o segundo plano dos pacotes protegidos em $SERIAL?" || die "cancelado"

step "pacotes protegidos"
for p in $(list_of "$DATA/protected.txt" | awk '{print $1}'); do
  if is_forbidden "$p"; then printf '  %-46s PULADO (protegido)\n' "$p"; continue; fi
  if ! present "$p"; then printf '  %-46s ausente\n' "$p"; continue; fi
  uid=$(uid_of "$p")
  if [[ -z $uid || $uid -lt 10000 ]]; then printf '  %-46s PULADO (uid de sistema %s)\n' "$p" "${uid:-?}"; continue; fi
  for op in RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND; do
    prev=$(appop_mode "$p" "$op")
    [[ $prev == ignore ]] && continue
    acmd appops set "$p" "$op" ignore >/dev/null && journal appops "$p" "$op" "$prev"
  done
  acmd am force-stop "$p" >/dev/null
  printf '  %-46s segundo plano cortado (uid %s)\n' "$p" "$uid"
done

if [[ $APPLY == 1 ]]; then
  health_check || { warn "a saúde falhou. Desfazendo."; undo_journal; die "desfeito."; }
  note "ok. Desfaça com ./scripts/restore.sh --apply"
fi
