#!/bin/bash
# acceptance-nightly.sh — cron 04:00: la suite di acceptance si controlla da sola.
# Verde → riga nel log. Rosso → RETRY dopo 90s (classifica i transitori: modelli a
# freddo alle 4 di notte); rosso anche al retry → pagina ops/acceptance-* NEL brain
# col dettaglio dei test falliti. Output completo di ogni run: ~/acceptance-last.log
# (v2 2026-07-04: --stdin su capture — senza, il corpo della pagina si perdeva in
#  silenzio; retry-classificatore dopo il primo rosso notturno reale, test 1 @04:00).
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=/home/ubuntu/acceptance.log
LAST=/home/ubuntu/acceptance-last.log

TOKEN=$(grep -o "gbrain_[A-Za-z0-9]*" /home/ubuntu/acceptance-token.txt | head -1)
[ -n "$TOKEN" ] || { echo "[$(date -Iseconds)] TOKEN acceptance mancante" >> "$LOG"; exit 1; }

run_suite() { # la suite gira DENTRO il container (bun), contro il serve locale :3131
  docker cp tests/acceptance/run.mjs brain-box-gbrain-1:/tmp/acceptance-run.mjs >/dev/null 2>&1
  docker compose exec -T \
    -e BRAIN_URL=http://localhost:3131/mcp \
    -e BRAIN_ACCEPTANCE_TOKEN="$TOKEN" \
    gbrain bun /tmp/acceptance-run.mjs 2>&1
}

OUT=$(run_suite); RC=$?
{ echo "=== run 1 · $(date -Iseconds) · exit=$RC ==="; echo "$OUT"; } > "$LAST"
echo "[$(date -Iseconds)] exit=$RC $(echo "$OUT" | tail -1)" >> "$LOG"

if [ $RC -ne 0 ]; then
  sleep 90   # modelli a freddo: dai tempo a ollama di caricare, poi riprova
  OUT2=$(run_suite); RC2=$?
  { echo "=== run 2 (retry) · $(date -Iseconds) · exit=$RC2 ==="; echo "$OUT2"; } >> "$LAST"
  echo "[$(date -Iseconds)] retry exit=$RC2 $(echo "$OUT2" | tail -1)" >> "$LOG"
  if [ $RC2 -eq 0 ]; then
    echo "[$(date -Iseconds)] VERDETTO: rosso TRANSITORIO (retry verde) — niente pagina ops" >> "$LOG"
    exit 0
  fi
  # rosso confermato → referto COMPLETO nel brain (--stdin: senza, il corpo si perde)
  { echo "Suite rossa due volte di fila ($(date -Iseconds)). Test falliti:";
    echo "$OUT2" | grep "❌"; echo; echo "Output completo: ~/acceptance-last.log sul box."; } | \
  docker compose exec -T -e GBRAIN_SOURCE=ops gbrain gbrain capture --stdin \
    --slug "ops/acceptance-$(date +%Y%m%d)" --title "SUITE ACCEPTANCE ROSSA (confermata)" \
    >/dev/null 2>&1 || true
  exit $RC2
fi
exit 0
