#!/usr/bin/env bash
# Só leitura. Confere se o debloat está aplicado e se a TV está saudável.
# Sai com 0 quando tudo confere.
# Uso: ./scripts/verify.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_device
require_profile
load_conf
need_snapshot

fail=0
ok()  { printf '  %-8s %s\n' ok "$*"; }
bad() { printf '  %-8s %s\n' FALHA "$*"; fail=1; }

step "pacotes"
off=$(disabled_now); pending=0
for p in $(targets); do
  present "$p" || continue
  grep -qx -- "$p" <<<"$off" && continue
  grep -q 'User 0:.* enabled=[23]' <<<"$(dev "dumpsys package $p")" && continue
  # Protegidos pela Amazon continuam ativos; isso é esperado.
  pending=$((pending+1)); printf '  %-8s %s\n' ativo "$p"
done
[[ $pending == 0 ]] && ok "todos os pacotes alvo estão desativados ou ausentes" ||
  note "$pending pacotes ainda ativos (normal para os protegidos pela Amazon)"

step "configurações"
while read -r ns key value _; do
  cur=$(dev1 settings get "$ns" "$key")
  [[ $cur == "$value" ]] && ok "$key = $value" || bad "$key = $cur (esperado $value)"
done < <(list_of "$DATA/settings.txt"; [[ $ALEXA == 0 ]] && list_of "$DATA/settings.alexa.txt")

step "saúde"
health_check && ok "pacotes essenciais ativos e systemui rodando" || bad "saúde com problemas (veja os avisos)"

step "lembrete"
note "terminou? Desligue a Depuração ADB na TV: Configurações > Minha Fire TV > Opções do desenvolvedor"
exit $fail
