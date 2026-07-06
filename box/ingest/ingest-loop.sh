#!/bin/bash
# Loop del worker: aspetta gbrain, poi UN ciclo di ingest per ogni EVENTO sull'inbox
# (inotifywait: parte appena il gate scrive un file) con fallback a INGEST_INTERVAL
# (default 10 min) se non arriva nulla o se inotify non è disponibile.
# Un ciclo fallito NON uccide il loop (il prossimo ritenta: i file restano in inbox).
set -u
echo "[ingest] attendo gbrain..."
until curl -sf http://gbrain:3131/health >/dev/null 2>&1; do sleep 5; done

if command -v inotifywait >/dev/null 2>&1; then
  echo "[ingest] gbrain OK — trigger a evento su /inbox (fallback ${INGEST_INTERVAL:-600}s)"
  while true; do
    /ingest/ingest-run.sh || echo "[ingest] ciclo fallito ($?): riprovo al prossimo giro"
    # file atterrati DURANTE il run (evento perso mentre si lavorava)? riparti subito.
    # NB: quarantena esclusa, o i file parcheggiati lì causano un hot-loop infinito.
    if [ -n "$(find /inbox -type f ! -path '*/quarantena/*' ! -name '.*' \
               ! -name '*.meta.json' ! -name '*.motivo.txt' 2>/dev/null | head -1)" ]; then
      sleep 3; continue
    fi
    # inbox vuota: attende un file nuovo (create/moved_to) O il timeout — poi ricicla
    inotifywait -qq -r -t "${INGEST_INTERVAL:-600}" -e create -e moved_to /inbox 2>/dev/null || true
    sleep 3   # lascia atterrare file+sidecar .meta.json in un colpo solo
  done
else
  echo "[ingest] gbrain OK — inotifywait assente: ciclo ogni ${INGEST_INTERVAL:-600}s"
  while true; do
    /ingest/ingest-run.sh || echo "[ingest] ciclo fallito ($?): riprovo al prossimo giro"
    sleep "${INGEST_INTERVAL:-600}"
  done
fi
