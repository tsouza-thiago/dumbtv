#!/usr/bin/env bash
# Desfaz tudo o que o journal registrou, na ordem inversa, e reinicia a TV.
# Exige só fabricante e modelo: funciona mesmo depois de uma atualização do Fire OS.
# Uso: ./scripts/restore.sh [--apply] [-y] [--no-reboot]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_flags "$@"
need_device
require_profile --restore-only
load_conf
acquire_lock

step "plano"
if [[ ! -s $JOURNAL ]]; then note "journal vazio: nada a desfazer"; exit 0; fi
note "desfazer $(wc -l < "$JOURNAL" | tr -d ' ') mudanças registradas em ${JOURNAL#"$ROOT"/}"
confirm "Desfazer as mudanças em $SERIAL?" || die "cancelado"

step "desfazendo"
undo_journal
[[ $APPLY == 0 ]] && { note "simulação: nada mudou. Para executar: ./scripts/restore.sh --apply"; exit 0; }
reboot_wait
[[ $NO_REBOOT == 1 ]] && exit 0
health_check --home && note "restaurado." || warn "a TV voltou, mas a saúde tem avisos. Confira a TV."
