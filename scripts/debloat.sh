#!/usr/bin/env bash
# Desativa os pacotes de anúncios, rastreamento e telemetria e aplica as
# configurações de desempenho. Sem --apply, só simula.
#
# Segurança:
#   - exige o snapshot do preflight.sh e o perfil de device.conf;
#   - cada comando passa pelo guardrail de lib.sh e vai para o journal;
#   - para na primeira resposta inesperada da TV;
#   - depois do reinício confere a saúde e, se falhar, desfaz tudo sozinho.
#
# Uso: ./scripts/debloat.sh [--apply] [-y] [--no-reboot]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_flags "$@"
need_device
require_profile
load_conf
need_snapshot
acquire_lock

settings_lines() {
  list_of "$DATA/settings.txt"
  if [[ $ALEXA == 0 ]]; then list_of "$DATA/settings.alexa.txt"; fi
}

step "plano"
note "desativar   até $(targets | wc -l | tr -d ' ') pacotes (reversível)"
note "alexa       $([[ $ALEXA == 1 ]] && echo mantida || echo 'desativada (ALEXA=0)')"
[[ -n $KEEP_APPS ]] && note "mantidos    $KEEP_APPS"
note "ajustes     $(settings_lines | wc -l | tr -d ' ')"
confirm "Aplicar o debloat em $SERIAL?" || die "cancelado"

step "pacotes"
off=$(disabled_now)
changed=0; skipped=0; prot=0; sysoff=0; absent=0
for p in $(targets); do
  if is_forbidden "$p"; then printf '  %-46s PULADO (protegido)\n' "$p"; continue; fi
  if ! present "$p"; then printf '  %-46s ausente\n' "$p"; absent=$((absent+1)); continue; fi
  if grep -qx -- "$p" <<<"$off"; then printf '  %-46s já desativado\n' "$p"; skipped=$((skipped+1)); continue; fi
  if [[ $APPLY == 0 ]]; then acmd pm disable-user --user 0 "$p"; continue; fi

  out=$(acmd pm disable-user --user 0 "$p" | head -1 | tr -d '\r')
  case $out in
    *disabled-user*)
      journal disable "$p"
      printf '  %-46s desativado\n' "$p"; changed=$((changed+1)) ;;
    *"protected package"*)
      printf '  %-46s protegido pela Amazon (normal)\n' "$p"; prot=$((prot+1)) ;;
    *"Shell cannot change component state"*)
      if grep -q 'User 0:.* enabled=2' <<<"$(dev "dumpsys package $p")"; then
        printf '  %-46s já desativado pelo sistema\n' "$p"; sysoff=$((sysoff+1))
      else
        die "resposta inesperada para $p: $out. Parei aqui. Para desfazer: ./scripts/restore.sh --apply"
      fi ;;
    *) die "resposta inesperada para $p: $out. Parei aqui. Para desfazer: ./scripts/restore.sh --apply" ;;
  esac
  alive || die "a TV parou de responder depois de $p. Reconecte e rode ./scripts/restore.sh --apply"
done

# Alguns pacotes desativados continuam vivos até o reinício. Corta o segundo
# plano deles (appops) e os para. UIDs de sistema (< 10000) ficam de fora.
step "processos que sobreviveram à desativação"
live=$(running_names); n=0
for p in $(targets); do
  grep -qx -- "$p" <<<"$live" || continue
  is_forbidden "$p" && continue
  uid=$(uid_of "$p")
  [[ -n $uid && $uid -ge 10000 ]] || { note "$p  uid de sistema, pulado"; continue; }
  for op in RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND; do
    prev=$(appop_mode "$p" "$op")
    [[ $prev == ignore ]] && continue
    acmd appops set "$p" "$op" ignore >/dev/null && journal appops "$p" "$op" "$prev"
  done
  acmd am force-stop "$p" >/dev/null
  printf '  %-46s segundo plano cortado\n' "$p"; n=$((n+1))
done
[[ $n == 0 ]] && note "nenhum"

step "configurações"
while read -r ns key value _; do
  prev=$(dev1 settings get "$ns" "$key")
  if [[ $prev == "$value" ]]; then printf '  %-46s já em %s\n' "$key" "$value"; continue; fi
  acmd settings put "$ns" "$key" "$value" >/dev/null && journal setting "$ns" "$key" "${prev:-null}"
  printf '  %-46s %s -> %s\n' "$key" "${prev:-null}" "$value"
done < <(settings_lines)

step "resumo"
note "desativados $changed · já desativados $skipped · protegidos $prot · do sistema $sysoff · ausentes $absent"
[[ $APPLY == 0 ]] && { note "simulação: nada mudou. Para executar: ./scripts/debloat.sh --apply"; exit 0; }
note "journal: ${JOURNAL#$ROOT/}"

reboot_wait
[[ $NO_REBOOT == 1 ]] && exit 0
step "saúde depois do reinício"
nap 20
if health_check --home; then
  note "ok. Meça daqui a 5 minutos: ./scripts/measure.sh depois"
else
  warn "a saúde falhou. Desfazendo tudo automaticamente."
  undo_journal
  reboot_wait
  die "as mudanças foram desfeitas. Guarde report/ e confira a TV."
fi
