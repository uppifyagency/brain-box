#!/usr/bin/env bash
# think.sh "domanda" [anchor-slug] — ragionamento pesante di gemma SENZA timeout.
# Poka-yoke (audit scoperta #12): via MCP i think >5min vengono uccisi dal client
# E IL LAVORO SI PERDE. Da qui: detached nel container, log su file, risposta
# persistita come pagina nel brain (--save). La regola comoda batte la regola scritta.
set -euo pipefail
cd "$(dirname "$0")/.."
Q="${1:?uso: ops/think.sh \"domanda\" [anchor-slug]}"
ANCHOR="${2:-}"
TS=$(date +%Y%m%d-%H%M%S)
LOG="/tmp/think-$TS.log"

sudo docker compose exec -dT -e TQ="$Q" -e TA="$ANCHOR" gbrain \
  sh -c 'gbrain think "$TQ" --save ${TA:+--anchor "$TA"} > '"$LOG"' 2>&1'

echo "think lanciato (detached). Su CPU aspettati 5-15 minuti."
echo "  log:      sudo docker compose exec -T gbrain tail -f $LOG"
echo "  risposta: a fine corsa nel log e come pagina synthesis/ nel brain (--save)"
