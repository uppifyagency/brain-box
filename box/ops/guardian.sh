#!/bin/bash
# GUARDIAN L1 — riflessi deterministici del brain-box. Cron: */15 (timer validati con
# simulazione a eventi discreti, vedi kit-ciro/ARCHITETTURA + HANDOFF Appendice).
#
# Filosofia: sensori → firme note → cure MECCANICHE idempotenti dal runbook.
# Ogni decisione va nel log; su anomalia scrive anche una pagina nel brain (interrogabile).
# GUARDIAN_MODE=observe (default): logga le cure SENZA eseguirle. =act: le esegue.
# Le firme richiedono zero-progresso: un sistema sano che lavora non viene MAI toccato.
set -u
cd "$(dirname "$0")/.."
MODE="${GUARDIAN_MODE:-observe}"
LOG=/home/ubuntu/guardian.log
STATE=/home/ubuntu/.guardian-state          # ultima lettura: "epoch chunk_count"
LOCK=/tmp/guardian.lock
DC="sudo docker compose"    # in cron gira come ubuntu: sudo NOPASSWD (come il backup)

log() { echo "[$(date -Is)] $*" >> "$LOG"; }
cure() { # $1=descrizione $2...=comando
  local desc="$1"; shift
  if [ "$MODE" = "act" ]; then log "CURA: $desc → eseguo"; "$@" >> "$LOG" 2>&1 || log "CURA FALLITA: $desc"
  else log "CURA (observe, NON eseguita): $desc"; fi
}
alert() { # anomalia non curabile → log + pagina nel brain
  log "ALERT: $1"
  $DC exec -T -e GBRAIN_SOURCE=ops gbrain gbrain capture --stdin --slug "ops/alert-$(date +%Y%m%d-%H%M)" \
    --title "ALERT guardian" <<< "$1" >/dev/null 2>&1 || true
}

# ── lock anti-sovrapposizione (TTL 45min = 3×intervallo) ──────────────────────
if ! mkdir "$LOCK" 2>/dev/null; then
  [ -n "$(find "$LOCK" -maxdepth 0 -mmin +45 2>/dev/null)" ] \
    && { rmdir "$LOCK"; mkdir "$LOCK" 2>/dev/null || exit 0; } || exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# ── S-container: tutti Up? ─────────────────────────────────────────────────────
DOWN=$($DC ps -a --format '{{.Name}} {{.State}}' | awk '$2!="running"{print $1}')
[ -n "$DOWN" ] && cure "container non running: $DOWN → up -d" $DC up -d

# ── S-disco ────────────────────────────────────────────────────────────────────
PCT=$(df / --output=pcent | tail -1 | tr -dc 0-9)
[ "$PCT" -gt 85 ] && alert "disco al ${PCT}% — pulire backups/ o allargare il volume"

# ── S-backup: più vecchio di 26h? ─────────────────────────────────────────────
LAST_BK=$(find backups -name '*.tar*' -o -name '*.gz' 2>/dev/null | xargs -r ls -t 2>/dev/null | head -1)
if [ -z "$LAST_BK" ] || [ -n "$(find "$LAST_BK" -mmin +1560 2>/dev/null)" ]; then
  # tollera il primo giorno di vita del box
  [ -n "$(find .env -mtime +1 2>/dev/null)" ] && alert "backup assente o più vecchio di 26h"
fi

# ── S-inbox: file reparto (mindepth 2: la radice può avere detriti admin) fermi >30min ─
STUCK=$(find inbox -mindepth 2 -type f ! -path '*/quarantena/*' ! -name '.*' ! -name '*.meta.json' \
        ! -name '*.motivo.txt' -mmin +30 2>/dev/null | head -3)
if [ -n "$STUCK" ]; then
  # anti-loop: la stessa cura al massimo una volta ogni 2h, poi è un problema da umano
  if [ ! -f /tmp/guardian-inbox-attempted ] || [ -n "$(find /tmp/guardian-inbox-attempted -mmin +120 2>/dev/null)" ]; then
    touch /tmp/guardian-inbox-attempted
    cure "file in inbox fermi >30min ($STUCK) → restart ingest" $DC restart ingest
  else
    alert "inbox ancora ferma dopo restart ingest <2h fa: $STUCK"
  fi
fi

# ── S-embed: firme di stallo (dal runbook F11/F12, timer da simulazione) ───────
PEND=$($DC exec -T postgres psql -U gbrain gbrain -t -A \
       -c "SELECT count(*) FROM content_chunks WHERE embedding IS NULL;" 2>/dev/null | tr -dc 0-9)
NOW_CNT=$($DC exec -T postgres psql -U gbrain gbrain -t -A \
       -c "SELECT count(*) FROM content_chunks WHERE embedding IS NOT NULL;" 2>/dev/null | tr -dc 0-9)
PREV_T=0; PREV_CNT=-1; STREAK=0
[ -f "$STATE" ] && read -r PREV_T PREV_CNT STREAK < "$STATE"
STREAK=${STREAK:-0}
NOW_T=$(date +%s); AGE=$(( NOW_T - PREV_T ))
# streak = giri consecutivi a zero progressi CON lavoro pendente
if [ "${PEND:-0}" -gt 0 ] && [ "$PREV_CNT" -ge 0 ] && [ "$NOW_CNT" = "$PREV_CNT" ] && [ "$AGE" -ge 550 ]; then
  STREAK=$(( STREAK + 1 ))
else
  STREAK=0
fi
echo "$NOW_T ${NOW_CNT:-0} $STREAK" > "$STATE"
OLLAMA_ACTIVE=$($DC logs ollama --since 2m 2>/dev/null | grep -c "processing task")
HOUR=$(date +%H)

if [ "$STREAK" -ge 1 ]; then
  # zero progressi con lavoro pendente → quale firma?
  # 🔴 il path CLI committa PER-PAGINA-INTERA: un libro da ~2400 chunk = ~70-90min di
  # ollama attivo SENZA commit, LEGITTIMO → S2 (invasiva) solo dopo 8 giri (=2h);
  # S1 (ollama FERMO = backfill morto) resta a 1 giro (~15min).
  if [ "$OLLAMA_ACTIVE" -eq 0 ]; then
    # S1: backfill MORTO (ollama fermo). Cura: pulisci lock di holder morti + rilancia loop.
    LIVE=$(sudo docker ps --format '{{.ID}}' | cut -c1-12 | paste -sd'|' -)
    cure "S1 backfill morto → clear lock morti + rilancio embed catch-up" bash -c "
      $DC exec -T postgres psql -U gbrain gbrain -c \"DELETE FROM gbrain_cycle_locks WHERE id LIKE 'gbrain-embed-backfill%' AND holder_host !~ '($LIVE)';\"
      $DC exec -e GBRAIN_EMBED_CONCURRENCY=1 -dT gbrain sh -c 'gbrain embed --stale --catch-up >> /tmp/embed-marathon.log 2>&1'"
  elif [ "$HOUR" -ge 4 ] && [ "$HOUR" -lt 7 ]; then
    # finestra dream: ollama occupato dai job chat è LEGITTIMO → solo nota, niente S2 (anti-FP)
    log "S2 soppressa (finestra dream): pending=$PEND, ollama attivo, streak=$STREAK"
  elif [ "$STREAK" -lt 8 ]; then
    # ollama attivo, pochi giri fermi: quasi certamente una pagina-gigante in lavorazione sana
    log "S2 in attesa (streak=$STREAK/8): pending=$PEND, ollama attivo — probabile pagina grande"
  else
    # S2: ZOMBIE-GRINDING (il caso F11: ollama macina, nessun commit). Cura più invasiva, 1 sola volta.
    if [ ! -f /tmp/guardian-s2-attempted ] || [ -n "$(find /tmp/guardian-s2-attempted -mmin +120 2>/dev/null)" ]; then
      touch /tmp/guardian-s2-attempted
      cure "S2 zombie-grinding → restart ollama + clear lock + rilancio catch-up" bash -c "
        $DC restart ollama && sleep 10
        $DC exec -T postgres psql -U gbrain gbrain -c \"DELETE FROM gbrain_cycle_locks WHERE id LIKE 'gbrain-embed-backfill%';\"
        $DC exec -e GBRAIN_EMBED_CONCURRENCY=1 -dT gbrain sh -c 'gbrain embed --stale --catch-up >> /tmp/embed-marathon.log 2>&1'"
    else
      alert "S2 già tentata <2h fa e l'embedding è ANCORA fermo (pending=$PEND) — serve un umano"
    fi
  fi
fi

# ── S-doctor: ogni 4° giro (~1h), solo referto (mai gate — può crashare, wart bun) ─
if [ $(( $(date +%s) / 900 % 4 )) -eq 0 ]; then
  $DC exec -T gbrain gbrain doctor --json > /home/ubuntu/.last-doctor.json 2>/dev/null \
    || log "doctor crashato (wart noto, non bloccante)"
fi

log "giro ok: pend=${PEND:-?} embedded=${NOW_CNT:-?} ollama_task2m=$OLLAMA_ACTIVE mode=$MODE"
