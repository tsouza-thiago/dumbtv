#!/usr/bin/env bash
# Só leitura. Mede RAM, processos, armazenamento, carga da CPU, CPU do áudio,
# quadros lentos da tela inicial, duração do boot e memória média das últimas 3 h,
# e compara com a medição anterior.
# Uso: ./scripts/measure.sh [rótulo]     (ex.: antes, depois)
# Meça "depois" uns 5 minutos após o reinício, quando o sistema assenta. Antes de
# cada medição, navegue 1 minuto pela tela inicial: os quadros lentos contam desde
# que a tela inicial abriu e zeram no reinício.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
label=${1:-medicao}
[[ $label =~ ^[a-zA-Z0-9_-]+$ ]] || die "rótulo inválido: use letras, números, - ou _"
need_device

mkdir -p "$REPORT"
prev=$(ls -1t "$REPORT"/measure-*.txt 2>/dev/null | head -1)
out="$REPORT/measure-$label-$(date +%Y%m%d-%H%M%S).txt"

mem=$(dev 'cat /proc/meminfo' | tr -d '\r')
avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' <<<"$mem")
total=$(awk '/^MemTotal:/ {print int($2/1024)}' <<<"$mem")
procs=$(running_names | awk 'NR>1 && NF' | wc -l | tr -d ' ')
data=$(dev 'df -h /data' | tr -d '\r' | awk 'NR==2 {print $4" livres de "$2}')
# O Fire OS 7 nega /proc/loadavg ao shell do adb; o `uptime` mostra a mesma carga.
load=$(dev 'uptime' | tr -d '\r' | sed -nE 's/.*load average: *([0-9.]+), *([0-9.]+), *([0-9.]+).*/\1 \2 \3/p' | head -1)
up=$(dev 'cat /proc/uptime' | tr -d '\r' | awk '$1 ~ /^[0-9.]+$/ {print int($1/60)}')
# Quadros da tela inicial desde que o processo dela começou (zera no reinício).
gfx=$(dev 'dumpsys gfxinfo com.amazon.tv.launcher' | tr -d '\r')
frames=$(sed -n 's/^Total frames rendered: \([0-9]*\).*/\1/p' <<<"$gfx" | head -1)
jank=$(sed -n 's/^Janky frames: [0-9]* (\([0-9.]*\)%).*/\1/p' <<<"$gfx" | head -1)
top=$(dev 'dumpsys meminfo' | tr -d '\r' | awk '/Total PSS by process:/ {f=1; next} f && NF==0 {exit} f' | head -10)
# Memória média das últimas 3 h (procstats): PSS médio × fração do tempo em que o
# processo existiu. Mais estável que o retrato do meminfo. Usa vírgula decimal
# conforme o idioma da TV. Só awk POSIX (sem extensões do gawk).
avg3h=$(dev 'dumpsys procstats --hours 3' | tr -d '\r' | awk '
  function mb(v,  n) { n = v; gsub(/[^0-9.,]/, "", n); sub(/,/, ".", n)
    return v ~ /GB/ ? n * 1024 : v ~ /KB/ ? n / 1024 : n + 0 }
  /^  \* / { name = $2; next }
  name != "" && $1 == "TOTAL:" {
    pct = $2; sub(/%/, "", pct); sub(/,/, ".", pct)
    split($0, a, "("); split(a[2], b, "/"); split(b[1], c, "-")
    printf "%d MB  %s\n", mb(c[2]) * pct / 100 + 0.5, name; name = "" }' | sort -rn | head -5)
# CPU do serviço de áudio (no AFTSSS, o com.amazon.whad mantém uma captura aberta).
audio=$(dev 'dumpsys cpuinfo' | tr -d '\r' | sed -nE 's/^ *([0-9.]+)% [0-9]+\/[^ ]*hardware\.audio[^ ]*:.*/\1/p' | head -1)
# Duração do último boot até a tela ficar pronta. O buffer de eventos gira em
# poucas horas: só existe na medição feita logo depois de reiniciar.
boot=$(dev 'logcat -d -b events' | tr -d '\r' | sed -nE 's/.*boot_progress_enable_screen: *\[?([0-9]+).*/\1/p' | tail -1)
[[ $boot =~ ^[0-9]+$ ]] && boot=$((boot / 1000)) || boot=""

{
  echo "rotulo=$label"
  echo "ram_total_mb=$total"
  echo "ram_disponivel_mb=$avail"
  echo "processos=$procs"
  echo "armazenamento=$data"
  echo "carga_cpu=${load:-n/d}"
  echo "ligada_min=${up:-n/d}"
  echo "tela_inicial_quadros=${frames:-n/d}"
  echo "tela_inicial_lentos_pct=${jank:-n/d}"
  echo "cpu_audio_pct=${audio:-n/d}"
  echo "boot_s=${boot:-n/d}"
  echo "# maiores consumidores de memória (PSS)"
  echo "$top"
  echo "# memória média nas últimas 3 h (procstats)"
  echo "$avg3h"
} > "$out"

step "desempenho ($label)"
note "ram disponível  $avail MB de $total MB"
note "processos       $procs"
note "/data           $data"
note "carga da cpu    ${load:-n/d} (1, 5 e 15 min)"
note "ligada há       ${up:-n/d} min"
note "tela inicial    ${jank:-n/d}% de quadros lentos em ${frames:-n/d} quadros"
note "cpu do áudio    ${audio:-n/d}%"
note "último boot     ${boot:+$boot s}${boot:-n/d (só logo depois de reiniciar)}"
[[ -n $up && $up -lt 5 ]] && warn "a TV ligou há menos de 5 min: a carga da CPU ainda está alta pelo boot"
note "maiores consumidores:"
while IFS= read -r l; do note "  $l"; done <<<"$top"
note "média das últimas 3 h:"
while IFS= read -r l; do note "  $l"; done <<<"$avg3h"

if [[ -n $prev ]]; then
  pa=$(sed -n 's/^ram_disponivel_mb=//p' "$prev"); pp=$(sed -n 's/^processos=//p' "$prev")
  step "comparado com $(basename "$prev")"
  note "ram disponível  $((avail - pa)) MB"
  note "processos       $((procs - pp))"
  pj=$(sed -n 's/^tela_inicial_lentos_pct=//p' "$prev")
  [[ $jank =~ ^[0-9.]+$ && $pj =~ ^[0-9.]+$ ]] &&
    note "quadros lentos  $(awk -v a="$jank" -v b="$pj" 'BEGIN {printf "%+.1f pontos", a-b}')"
  pa=$(sed -n 's/^cpu_audio_pct=//p' "$prev")
  [[ $audio =~ ^[0-9.]+$ && $pa =~ ^[0-9.]+$ ]] &&
    note "cpu do áudio    $(awk -v a="$audio" -v b="$pa" 'BEGIN {printf "%+.1f pontos", a-b}')"
fi
note "salvo em ${out#"$ROOT"/}"
