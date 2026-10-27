#!/usr/bin/env bash
# Opcional (risco baixo a médio). Liga o DNS privado do Android (DNS-over-TLS)
# apontando para um servidor com bloqueio de anúncios e rastreamento.
# Não instala app, não usa VPN e não gasta RAM.
#
# Segurança:
#   - testa a internet da TV e a porta 853 do servidor ANTES de mudar;
#   - grava os valores anteriores no journal;
#   - depois de mudar, confere se os domínios de data/dns-check.txt resolvem,
#     incluindo os servidores de atualização; se algum falhar, desfaz sozinho;
#   - reinicia a TV e repete as checagens (alguns Fire TV só perdem a internet
#     depois de reiniciar); se falhar, desfaz sozinho.
#
# ATENÇÃO: com o DNS privado ligado, NÃO desligue a Depuração ADB. A Amazon
# esconde essa opção do menu: se o servidor sair do ar, o ADB é a única forma
# de desligar o DNS privado sem restauração de fábrica.
#
# Uso: ./scripts/dns.sh [--host=SERVIDOR] [--apply] [-y] [--no-reboot]
#      ./scripts/dns.sh --off [--apply] [-y]       desliga e volta ao valor anterior
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

OFF=0; HOST_ARG=""; rest=()
for a in "$@"; do
  case $a in
    --off)    OFF=1 ;;
    --host=*) HOST_ARG=${a#--host=} ;;
    *)        rest+=("$a") ;;
  esac
done
parse_flags ${rest[@]+"${rest[@]}"}
need_device
require_profile
load_conf
need_snapshot
acquire_lock

DNS_PAT=$'^setting\tglobal\tprivate_dns_'

if [[ $OFF == 1 ]]; then
  step "desligando o DNS privado"
  confirm "Desligar o DNS privado em $SERIAL?" || die "cancelado"
  undo_where "$DNS_PAT"
  [[ $APPLY == 1 ]] && note "modo agora: $(dev1 settings get global private_dns_mode)"
  exit 0
fi

host=${HOST_ARG:-$DNS_HOST}
[[ $host =~ $HOST_RE ]] || die "servidor inválido: $host"

# Testa a porta 853 (DNS-over-TLS) a partir do computador, que está na mesma rede.
probe_dot() {
  if [[ ${DUMBTV_TEST:-0} == 1 ]]; then [[ ${DUMBTV_DOT_PROBE:-ok} == ok ]]; return; fi
  timeout 6 bash -c "exec 3<>/dev/tcp/$1/853" 2>/dev/null
}

rollback() {
  warn "falhou:${1}. Desfazendo o DNS automaticamente."
  undo_where "$DNS_PAT"
  resolve_retry www.amazon.com >/dev/null || warn "a TV ainda não resolve nomes. Reinicie a TV e rode ./scripts/dns.sh --off --apply"
  die "o DNS privado foi desligado e os valores anteriores voltaram."
}

step "plano"
note "servidor     $host (DNS-over-TLS, porta 853)"
note "agora        modo $(dev1 settings get global private_dns_mode), servidor $(dev1 settings get global private_dns_specifier)"

step "checagens antes de mudar"
read -ra must <<<"$(dns_list must | tr '\n' ' ')"
for d in "${must[@]}"; do
  resolve_retry "$d" >/dev/null || die "a TV não resolve $d nem antes da mudança. Confira a internet da TV. Nada foi alterado."
done
note "internet da TV ok"
# Os CDNs de atualização só contam se resolvem agora; os que resolvem viram obrigatórios.
ota=()
for d in $(dns_list ota); do
  if resolve_retry "$d" >/dev/null; then ota+=("$d"); else note "$d não resolve nem antes; ignorado"; fi
done
probe_dot "$host" || die "o computador não alcança $host na porta 853. Nada foi alterado."
note "servidor $host responde na porta 853"

if [[ $(dev1 settings get global private_dns_mode) == hostname &&
      $(dev1 settings get global private_dns_specifier) == "$host" ]]; then
  note "o DNS privado já está ligado com $host"; exit 0
fi

confirm "Ligar o DNS privado com $host em $SERIAL?" || die "cancelado"

step "aplicando"
for key in private_dns_specifier private_dns_mode; do
  case $key in private_dns_specifier) value=$host ;; *) value=hostname ;; esac
  prev=$(dev1 settings get global "$key")
  acmd settings put global "$key" "$value" >/dev/null && journal setting global "$key" "${prev:-null}"
  printf '  %-46s %s -> %s\n' "$key" "${prev:-null}" "$value"
done
[[ $APPLY == 0 ]] && { note "simulação: nada mudou. Para executar: ./scripts/dns.sh --apply"; exit 0; }

step "checagens depois de mudar"
nap 5
dns_verify "${must[@]}" ${ota[@]+"${ota[@]}"} || rollback "$DNS_FAILED"
health_check || rollback " saúde do sistema"

for d in $(dns_list probe); do
  ip=$(tv_resolve "$d")
  if [[ -n $ip ]] && ! is_block_ip "$ip"; then
    warn "$d resolveu para $ip: o filtro pode não estar ativo (o Fire OS pode ignorar o DNS privado ou o provedor não bloqueia esse domínio)"
  else
    note "filtro ativo: $d bloqueado"
  fi
done

# Há relatos de Fire TV que perdem a internet só depois de reiniciar com o DNS
# privado ligado. Por isso o dns.sh reinicia e confere tudo de novo.
if [[ $NO_REBOOT == 1 ]]; then
  warn "sem reiniciar (--no-reboot): a checagem depois do reinício não foi feita"
else
  step "checagens depois do reinício"
  reboot_wait
  nap 20
  dns_verify "${must[@]}" ${ota[@]+"${ota[@]}"} || rollback "$DNS_FAILED (depois do reinício)"
  health_check --home || rollback " saúde do sistema depois do reinício"
fi

step "pronto"
note "DNS privado ligado com $host. Para desligar: ./scripts/dns.sh --off --apply"
warn "NÃO desligue a Depuração ADB enquanto o DNS privado estiver ligado."
warn "Se a TV perder a internet um dia: adb connect <ip-da-tv>:5555 e ./scripts/dns.sh --off --apply"
