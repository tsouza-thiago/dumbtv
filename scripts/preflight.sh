#!/usr/bin/env bash
# Só leitura na TV. Confere o aparelho contra device.conf, mostra o estado atual
# e salva o snapshot do estado original em report/snapshot/ (uma vez só).
# Uso: ./scripts/preflight.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_device
load_conf

step "aparelho"
note "serial        $SERIAL"
note "modelo        $(dev1 getprop ro.product.manufacturer) $(dev1 getprop ro.product.model)"
note "fire os       $(dev1 getprop ro.build.version.name) ($(dev1 getprop ro.build.display.id))"
note "android sdk   $SDK"
note "tela inicial  com.amazon.tv.launcher $(launcher_version)"
require_profile
note "perfil        confere com device.conf"

# Antes da checagem de saúde, que usa o snapshot para saber o que já vinha desativado.
step "snapshot do estado original"
mkdir -p "$SNAP"
if [[ -f $SNAP/packages-disabled.txt ]]; then
  note "já existe (report/snapshot/); o original é mantido"
else
  dev 'pm list packages' | sed 's/^package://' | tr -d '\r' | sort > "$SNAP/packages-all.txt"
  disabled_now | sort > "$SNAP/packages-disabled.txt"
  dev 'settings list secure' | tr -d '\r' > "$SNAP/settings-secure.txt"
  dev 'settings list global' | tr -d '\r' > "$SNAP/settings-global.txt"
  { dev1 getprop ro.build.version.name; dev1 getprop ro.build.display.id; launcher_version; } > "$SNAP/versions.txt"
  note "salvo em report/snapshot/"
fi

step "estado atual"
note "pacotes       $(dev 'pm list packages' | wc -l | tr -d ' ') instalados, $(disabled_now | awk 'NF' | wc -l | tr -d ' ') desativados"
note "processos     $(running_names | awk 'NR>1 && NF' | wc -l | tr -d ' ')"
note "ram livre     $(dev 'cat /proc/meminfo' | awk '/^MemAvailable:/ {printf "%d MB", $2/1024}')"
if health_check; then note "saúde         ok"; else die "a TV já tem problemas antes de qualquer mudança. Nada será feito."; fi

step "o debloat faria"
note "desativar até $(targets | wc -l | tr -d ' ') pacotes da Amazon$([[ $ALEXA == 0 ]] && printf ' (incluindo a Alexa)')"
note "aplicar $(list_of "$DATA/settings.txt" | wc -l | tr -d ' ') configurações de desempenho e privacidade"
[[ $LOCKDOWN == 1 ]] && note "lockdown: cortar o segundo plano de $(list_of "$DATA/protected.txt" | wc -l | tr -d ' ') pacotes protegidos"
note "reiniciar a TV uma vez e conferir a saúde (desfaz sozinho se falhar)"

step "nunca é tocado"
note "/system, a tela inicial, as configurações, o controle remoto, as entradas HDMI,"
note "o Bluetooth, a loja, o Prime Video e o atualizador do sistema (data/never-disable.txt)"

step "próximo passo"
note "./scripts/measure.sh antes      mede o desempenho atual"
note "./scripts/debloat.sh            simula e mostra cada comando"
