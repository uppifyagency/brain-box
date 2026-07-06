#!/bin/bash
# DREAM NIGHTLY — SOLO fasi deterministiche (lint, orphans, purge): zero LLM, secondi.
# Le fasi LLM (synthesize/patterns/consolidate) restano MANUALI finché l'uso non le
# tira (F3 2026-07-03: 0 transcript, patterns speculativo; consolidate ha senso quando
# i fatti accumulati saranno decine — riaprire allora, prima esecuzione supervisionata).
# libri ESCLUSO: lint che ritocca 54 libri = churn di re-embed senza guadagno.
# Rosso → pagina ops/dream-* nel brain (stesso pattern di guardian/acceptance-nightly).
# Cron: 30 4 * * * (dopo backup 03:00 e acceptance 04:00; nessuna contesa: niente gemma).
set -u
cd "$(dirname "$0")/.."
LOG=/home/ubuntu/dream.log
DC="sudo docker compose"
SOURCES="generale prova"
FAIL=""

log() { echo "[$(date -Is)] $*" >> "$LOG"; }

log "dream nightly start"
for s in $SOURCES; do
  for ph in lint orphans purge; do
    out=$($DC exec -T gbrain gbrain dream --phase "$ph" --json --dir "/data/brain/$s" 2>&1)
    if [ $? -eq 0 ]; then
      log "$s/$ph: $(printf '%s' "$out" | grep '"summary"' | head -1 | sed 's/^ *//;s/,$//')"
    else
      FAIL="$FAIL $s/$ph"
      log "$s/$ph FAIL: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
    fi
  done
done

if [ -n "$FAIL" ]; then
  $DC exec -T -e GBRAIN_SOURCE=ops gbrain gbrain capture \
    --slug "ops/dream-$(date +%Y%m%d-%H%M)" --title "dream nightly FAIL" \
    <<< "Fasi fallite:$FAIL — vedi ~/dream.log sul box" >/dev/null 2>&1 || true
fi
log "dream nightly done (fail:${FAIL:-nessuno})"
