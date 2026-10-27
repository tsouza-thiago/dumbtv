#!/usr/bin/env bash
# Só leitura. Mede RAM, processos e armazenamento e compara com a medição anterior.
# Uso: ./scripts/measure.sh [rótulo]     (ex.: antes, depois)
# Meça "depois" uns 5 minutos após o reinício, quando o sistema assenta.
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
top=$(dev 'dumpsys meminfo' | tr -d '\r' | awk '/Total PSS by process:/ {f=1; next} f && NF==0 {exit} f' | head -10)

{
  echo "rotulo=$label"
  echo "ram_total_mb=$total"
  echo "ram_disponivel_mb=$avail"
  echo "processos=$procs"
  echo "armazenamento=$data"
  echo "# maiores consumidores de memória (PSS)"
  echo "$top"
} > "$out"

step "desempenho ($label)"
note "ram disponível  $avail MB de $total MB"
note "processos       $procs"
note "/data           $data"
note "maiores consumidores:"
while IFS= read -r l; do note "  $l"; done <<<"$top"

if [[ -n $prev ]]; then
  pa=$(sed -n 's/^ram_disponivel_mb=//p' "$prev"); pp=$(sed -n 's/^processos=//p' "$prev")
  step "comparado com $(basename "$prev")"
  note "ram disponível  $((avail - pa)) MB"
  note "processos       $((procs - pp))"
fi
note "salvo em ${out#$ROOT/}"
