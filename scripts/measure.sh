#!/usr/bin/env bash
# Só leitura. Mede RAM, processos, armazenamento, carga da CPU e quadros lentos da
# tela inicial, e compara com a medição anterior.
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
load=$(dev 'cat /proc/loadavg' | tr -d '\r' | awk 'NF>=3 && $1 ~ /^[0-9.]+$/ {print $1" "$2" "$3}')
up=$(dev 'cat /proc/uptime' | tr -d '\r' | awk '$1 ~ /^[0-9.]+$/ {print int($1/60)}')
# Quadros da tela inicial desde que o processo dela começou (zera no reinício).
gfx=$(dev 'dumpsys gfxinfo com.amazon.tv.launcher' | tr -d '\r')
frames=$(sed -n 's/^Total frames rendered: \([0-9]*\).*/\1/p' <<<"$gfx" | head -1)
jank=$(sed -n 's/^Janky frames: [0-9]* (\([0-9.]*\)%).*/\1/p' <<<"$gfx" | head -1)
top=$(dev 'dumpsys meminfo' | tr -d '\r' | awk '/Total PSS by process:/ {f=1; next} f && NF==0 {exit} f' | head -10)

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
  echo "# maiores consumidores de memória (PSS)"
  echo "$top"
} > "$out"

step "desempenho ($label)"
note "ram disponível  $avail MB de $total MB"
note "processos       $procs"
note "/data           $data"
note "carga da cpu    ${load:-n/d} (1, 5 e 15 min)"
note "ligada há       ${up:-n/d} min"
note "tela inicial    ${jank:-n/d}% de quadros lentos em ${frames:-n/d} quadros"
[[ -n $up && $up -lt 5 ]] && warn "a TV ligou há menos de 5 min: a carga da CPU ainda está alta pelo boot"
note "maiores consumidores:"
while IFS= read -r l; do note "  $l"; done <<<"$top"

if [[ -n $prev ]]; then
  pa=$(sed -n 's/^ram_disponivel_mb=//p' "$prev"); pp=$(sed -n 's/^processos=//p' "$prev")
  step "comparado com $(basename "$prev")"
  note "ram disponível  $((avail - pa)) MB"
  note "processos       $((procs - pp))"
  pj=$(sed -n 's/^tela_inicial_lentos_pct=//p' "$prev")
  [[ $jank =~ ^[0-9.]+$ && $pj =~ ^[0-9.]+$ ]] &&
    note "quadros lentos  $(awk -v a="$jank" -v b="$pj" 'BEGIN {printf "%+.1f pontos", a-b}')"
fi
note "salvo em ${out#"$ROOT"/}"
