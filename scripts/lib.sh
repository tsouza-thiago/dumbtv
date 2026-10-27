#!/usr/bin/env bash
# Funções compartilhadas. Todo script faz `source` deste arquivo.
#
# Guardrails centrais:
#   1. Nada muda na TV sem --apply. O padrão é simulação.
#   2. A TV precisa bater com device.conf (modelo, SDK, build, tela inicial).
#   3. acmd só aceita uma lista fechada de comandos e recusa pacotes protegidos.
#   4. Cada mudança vai para report/journal.tsv logo depois de feita, com o valor
#      anterior, para o restore.sh desfazer exatamente o que foi feito.
#   5. Uma execução por vez (report/.lock).

ADB=${ADB:-adb}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DATA=${DATA:-$ROOT/data}
REPORT=${REPORT:-$ROOT/report}
SNAP=$REPORT/snapshot
JOURNAL=$REPORT/journal.tsv
CONF=${CONF:-$ROOT/dumbtv.conf}
PROFILE=${PROFILE:-$ROOT/device.conf}
SERIAL=${SERIAL:-${ADB_SERIAL:-}}
BOOT_SECONDS=${BOOT_SECONDS:-45}
ALLOW_UNTESTED=${ALLOW_UNTESTED:-0}
APPLY=0
ASSUME_YES=0
NO_REBOOT=0
SDK=0

# Nomes que nunca podem ser alvo, mesmo fora de never-disable.txt.
RISKY_PATTERN='(\.launcher$|homestarter|systemui|webview|packageinstaller|permissioncontroller|inputmethod|bluetooth|software\.ota|otaupdater|easyupgrade|venezia|oobe|settings\.v2|settings\.core)'

step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*" >&2; }
warn() { printf '  \033[33maviso:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merro:\033[0m %s\n' "$*" >&2; exit 1; }
nap()  { [[ ${DUMBTV_TEST:-0} == 1 ]] && return 0; sleep "$1"; }

parse_flags() {
  local a
  for a in "$@"; do
    case $a in
      --apply)     APPLY=1 ;;
      -y|--yes)    ASSUME_YES=1 ;;
      --no-reboot) NO_REBOOT=1 ;;
      *) die "opção desconhecida: $a" ;;
    esac
  done
  if [[ $APPLY == 0 ]]; then note "modo simulação: nada muda na TV (use --apply para executar)"; fi
}

confirm() {
  [[ $ASSUME_YES == 1 || $APPLY == 0 ]] && return 0
  local reply
  printf '%s [s/N] ' "$1" >&2
  read -r reply
  case $reply in s|S|sim|SIM|y|Y) return 0 ;; *) return 1 ;; esac
}

# --- configuração do dono (dumbtv.conf) -------------------------------------
# Lido linha a linha, nunca com `source`: só três chaves e valores validados.
load_conf() {
  ALEXA=1; LOCKDOWN=0; KEEP_APPS=""
  [[ -f $CONF ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [[ -z $line ]] && continue
    [[ $line =~ ^([A-Z_]+)=\"?([a-z0-9._\ ]*)\"?$ ]] || die "linha inválida em dumbtv.conf: $line"
    key=${BASH_REMATCH[1]}; val=${BASH_REMATCH[2]}
    case $key in
      ALEXA|LOCKDOWN) [[ $val == 0 || $val == 1 ]] || die "$key deve ser 0 ou 1"
                      printf -v "$key" '%s' "$val" ;;
      KEEP_APPS)      KEEP_APPS=$val ;;
      *) die "chave desconhecida em dumbtv.conf: $key" ;;
    esac
  done < "$CONF"
  local k
  for k in $KEEP_APPS; do
    grep -qx "$k" <<<"$(all_targets)" || die "KEEP_APPS: '$k' não está em nenhuma lista (erro de digitação?)"
  done
}

# --- listas ------------------------------------------------------------------
list_of() { sed 's/#.*//; s/[[:space:]]*$//' "$1" | awk 'NF'; }
never_disable() { list_of "$DATA/never-disable.txt" | awk '{print $1}'; }
all_targets() { { list_of "$DATA/packages.txt"; list_of "$DATA/alexa.txt"; } | awk '{print $1}'; }
setting_keys() { { list_of "$DATA/settings.txt"; list_of "$DATA/settings.alexa.txt"; } | awk '{print $1" "$2}'; }

keep_pkg() { local k; for k in $KEEP_APPS; do [[ $k == "$1" ]] && return 0; done; return 1; }

# Pacotes que este run pode desativar: packages.txt, mais alexa.txt com ALEXA=0.
targets() {
  {
    list_of "$DATA/packages.txt"
    if [[ ${ALEXA:-1} == 0 ]]; then list_of "$DATA/alexa.txt"; fi
  } | awk '{print $1}' | while read -r p; do keep_pkg "$p" || printf '%s\n' "$p"; done
}

is_forbidden() {
  [[ $1 =~ $RISKY_PATTERN ]] && return 0
  grep -qx -- "$1" <<<"$(never_disable)"
}

# --- adb ---------------------------------------------------------------------
dev()  { "$ADB" -s "$SERIAL" shell "$@" 2>&1 </dev/null; }
dev1() { dev "$@" | head -1 | tr -d '\r'; }
alive() { [[ $(dev1 echo ok) == ok ]]; }

need_device() {
  command -v "$ADB" >/dev/null || die "adb não encontrado no PATH"
  "$ADB" start-server >/dev/null 2>&1
  if [[ -z $SERIAL ]]; then
    local found
    found=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')
    [[ -z $found ]] && die "nenhuma TV conectada. Ligue a Depuração ADB e rode: adb connect <ip-da-tv>:5555"
    [[ $(wc -l <<<"$found") -gt 1 ]] && die "várias TVs conectadas; defina ADB_SERIAL: $(tr '\n' ' ' <<<"$found")"
    SERIAL=$found
  fi
  alive || die "a TV $SERIAL não responde"
  SDK=$(dev1 getprop ro.build.version.sdk)
  [[ $SDK =~ ^[0-9]+$ ]] || SDK=0
}

launcher_version() {
  dev 'dumpsys package com.amazon.tv.launcher' | sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -1 | tr -d '\r'
}

# Confere a TV contra device.conf. Com --restore-only, exige só fabricante e
# modelo, para que uma atualização do Fire OS não impeça desfazer as mudanças.
require_profile() {
  local line key val man model build lver
  while IFS= read -r line; do
    [[ $line =~ ^(EXPECT_[A-Z_]+)=([A-Za-z0-9._]+)$ ]] || continue
    key=${BASH_REMATCH[1]}; val=${BASH_REMATCH[2]}
    printf -v "$key" '%s' "$val"
  done < "$PROFILE"

  man=$(dev1 getprop ro.product.manufacturer)
  model=$(dev1 getprop ro.product.model)
  [[ $man == "$EXPECT_MANUFACTURER"* ]] || die "fabricante '$man' não é $EXPECT_MANUFACTURER. Este projeto só serve para o Fire TV Stick 3ª geração."
  [[ $model == "$EXPECT_MODEL" ]] || die "modelo '$model' não é $EXPECT_MODEL. As listas não foram verificadas para este aparelho."
  [[ ${1:-} == --restore-only ]] && return 0

  [[ $SDK == "$EXPECT_SDK" ]] || die "SDK $SDK não é $EXPECT_SDK (Fire OS 7)."
  build="$(dev1 getprop ro.build.version.name) $(dev1 getprop ro.build.display.id)"
  lver=$(launcher_version)
  local miss=""
  [[ $build == *"$EXPECT_BUILD"* && $build == *"$EXPECT_BUILD_NUMBER"* ]] || miss="build '$build' (esperado $EXPECT_BUILD/$EXPECT_BUILD_NUMBER)"
  [[ $lver == "$EXPECT_LAUNCHER_VERSION" ]] || miss="${miss:+$miss; }tela inicial '$lver' (esperado $EXPECT_LAUNCHER_VERSION)"
  if [[ -n $miss ]]; then
    [[ $ALLOW_UNTESTED == 1 ]] || die "versão não testada: $miss. Provavelmente o Fire OS atualizou. Revise as listas e rode de novo com ALLOW_UNTESTED=1."
    warn "versão não testada, seguindo por ALLOW_UNTESTED=1: $miss"
  fi
}

present() { grep -q '^package:' <<<"$(dev "pm path $1")"; }
disabled_now() { dev 'pm list packages -d' | sed 's/^package://' | tr -d '\r'; }
uid_of() { dev "dumpsys package $1" | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1; }
running_names() { dev 'ps -A -o NAME' | tr -d '\r'; }

front_activity() {
  dev 'dumpsys activity activities' | grep -m1 -E 'ResumedActivity: ActivityRecord' |
    sed -nE 's/.*ActivityRecord\{[^ ]+ u[0-9]+ ([^ }]+).*/\1/p'
}

# Modo atual de uma operação appops ("default" quando não há registro).
appop_mode() {
  local m
  m=$(dev "appops get $1 $2" | tr -d '\r' | sed -n "s/^$2: \([a-z]*\).*/\1/p" | head -1)
  printf '%s' "${m:-default}"
}

# --- guardrail de comandos ---------------------------------------------------
# Imprime o motivo e retorna 1 quando o comando não é permitido.
check_cmd() {
  case "$1 ${2:-}" in
    "pm disable-user")
      [[ $# == 5 && $3 == --user && $4 == 0 ]] || { echo "formato inválido"; return 1; }
      is_forbidden "$5" && { echo "pacote protegido"; return 1; }
      grep -qx -- "$5" <<<"$(targets)" || { echo "pacote fora das listas"; return 1; } ;;
    "pm enable")
      [[ $# == 5 && $3 == --user && $4 == 0 ]] || { echo "formato inválido"; return 1; } ;;
    "settings put"|"settings delete")
      [[ $3 == secure || $3 == global ]] || { echo "namespace não permitido"; return 1; }
      [[ $2 == put && $# == 5 || $2 == delete && $# == 4 ]] || { echo "formato inválido"; return 1; }
      grep -qxF -- "$3 $4" <<<"$(setting_keys)" || { echo "chave fora de settings*.txt"; return 1; } ;;
    "appops set")
      [[ $# == 5 ]] || { echo "formato inválido"; return 1; }
      [[ $4 == RUN_IN_BACKGROUND || $4 == RUN_ANY_IN_BACKGROUND ]] || { echo "operação não permitida"; return 1; }
      [[ $5 =~ ^(allow|ignore|deny|default|foreground)$ ]] || { echo "modo inválido"; return 1; }
      if [[ $5 == ignore || $5 == deny ]]; then
        is_forbidden "$3" && { echo "pacote protegido"; return 1; }
        grep -qx -- "$3" <<<"$(targets; list_of "$DATA/protected.txt")" || { echo "pacote fora das listas"; return 1; }
      fi ;;
    "am force-stop")
      [[ $# == 3 ]] || { echo "formato inválido"; return 1; }
      is_forbidden "$3" && { echo "pacote protegido"; return 1; }
      grep -qx -- "$3" <<<"$(targets; list_of "$DATA/protected.txt")" || { echo "pacote fora das listas"; return 1; } ;;
    "pm trim-caches")
      [[ $# == 3 ]] || { echo "formato inválido"; return 1; } ;;
    *) echo "comando fora da lista permitida"; return 1 ;;
  esac
}

# Executa um comando que muda a TV, depois de passar pelo guardrail.
acmd() {
  local why
  why=$(check_cmd "$@") || die "guardrail bloqueou: '$*' ($why)"
  if [[ $APPLY == 0 ]]; then note "[simulação] $*"; return 0; fi
  dev "$@"
}

journal() {
  [[ $APPLY == 1 ]] || return 0
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:-}" "${4:-}" >> "$JOURNAL"
}

# --- trava e snapshot --------------------------------------------------------
acquire_lock() {
  mkdir -p "$REPORT"
  mkdir "$REPORT/.lock" 2>/dev/null ||
    die "outra execução está em andamento (se tiver certeza que não, apague report/.lock)"
  trap 'rmdir "$REPORT/.lock" 2>/dev/null' EXIT
  trap 'warn "interrompido. Para desfazer o que já mudou: ./scripts/restore.sh --apply"; exit 130' INT TERM
}

need_snapshot() {
  [[ -f $SNAP/packages-disabled.txt && -f $SNAP/settings-secure.txt ]] ||
    die "sem snapshot do estado original. Rode ./scripts/preflight.sh primeiro."
}

# --- reinício e saúde --------------------------------------------------------
boot_id() { dev1 cat /proc/sys/kernel/random/boot_id; }

# O `svc power reboot` deixa o PackageManager gravar o estado dos pacotes antes
# de desligar; o `reboot` puro pode cortar essa gravação no meio.
ask_reboot() {
  dev svc power reboot >/dev/null 2>&1 || true
  nap 3
  if alive && [[ -z $(dev1 getprop sys.shutdown.requested) ]]; then
    nap 12
    dev reboot >/dev/null 2>&1 || true
  fi
}

reboot_wait() {
  if [[ $NO_REBOOT == 1 ]]; then note "sem reiniciar (--no-reboot): reinicie a TV antes do próximo passo"; return 0; fi
  local i before
  before=$(boot_id)
  note "reiniciando a TV"
  ask_reboot
  nap "$BOOT_SECONDS"
  for i in $(seq 1 30); do
    [[ $SERIAL == *:* ]] && "$ADB" connect "$SERIAL" >/dev/null 2>&1
    if [[ $(dev1 getprop sys.boot_completed) == 1 && $(boot_id) != "$before" ]]; then
      note "TV reiniciada"; return 0
    fi
    nap 5
  done
  die "a TV não concluiu o boot. Confira a TV antes de rodar qualquer outra coisa."
}

# Saúde do sistema. Com --home, envia o botão Home e confere a tela da Amazon.
health_check() {
  local bad=0 off p home
  [[ $(dev1 getprop sys.boot_completed) == 1 ]] || { warn "boot não concluído"; bad=1; }
  off=$(disabled_now)
  for p in $(never_disable); do
    grep -qx -- "$p" <<<"$off" || continue
    grep -qx -- "$p" "$SNAP/packages-disabled.txt" 2>/dev/null && continue
    warn "pacote essencial desativado: $p"; bad=1
  done
  grep -q '[0-9]' <<<"$(dev 'pidof com.android.systemui')" || { warn "systemui não está rodando"; bad=1; }
  if [[ ${1:-} == --home ]]; then
    dev 'am start -a android.intent.action.MAIN -c android.intent.category.HOME' >/dev/null
    nap 3
    home=$(front_activity); home=${home%%/*}
    case $home in
      com.amazon.tv.launcher|com.amazon.firehomestarter) note "tela inicial: $home" ;;
      '') warn "não consegui ler a tela da frente (TV em repouso?)" ;;
      *)  warn "a tela da frente é $home, não a tela inicial da Amazon"; bad=1 ;;
    esac
  fi
  return $bad
}

# Desfaz o journal de trás para frente.
undo_journal() {
  [[ -s $JOURNAL ]] || { note "nada a desfazer (journal vazio)"; return 0; }
  local kind a b c
  while IFS=$'\t' read -r kind a b c; do
    case $kind in
      disable) acmd pm enable --user 0 "$a" >/dev/null; note "reativado      $a" ;;
      appops)  acmd appops set "$a" "$b" "$c" >/dev/null; note "appops         $a $b -> $c" ;;
      setting) if [[ $c == null ]]; then acmd settings delete "$a" "$b" >/dev/null
               else acmd settings put "$a" "$b" "$c" >/dev/null; fi
               note "configuração   $b -> $c" ;;
      *) warn "linha desconhecida no journal: $kind" ;;
    esac
  done < <(awk '{l[NR]=$0} END {for (i=NR; i>0; i--) print l[i]}' "$JOURNAL")
  if [[ $APPLY == 1 ]]; then mv "$JOURNAL" "$REPORT/journal.desfeito-$(date +%Y%m%d-%H%M%S).tsv"; fi
}
