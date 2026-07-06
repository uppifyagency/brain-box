#!/bin/bash
# STATUS COLLECTOR — scrive status/status.json ogni ~10s per il dashboard live (brain-live.html).
# Gira SULL'HOST (i container non vedono docker/load/disco). Cron: */5 → loop di 5 min con
# iterazioni da 10s + lock (stessa infrastruttura del guardian: niente demoni, niente systemd).
# Sola lettura: non cura niente (quello è ops/guardian.sh).
set -u
cd "$(dirname "$0")/.."
OUT_DIR=./status; OUT="$OUT_DIR/status.json"
LOCK=/tmp/status-collector.lock
DC="sudo docker compose"

if ! mkdir "$LOCK" 2>/dev/null; then
  [ -n "$(find "$LOCK" -maxdepth 0 -mmin +7 2>/dev/null)" ] \
    && { rmdir "$LOCK"; mkdir "$LOCK" 2>/dev/null || exit 0; } || exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
mkdir -p "$OUT_DIR"

PSQL() { $DC exec -T postgres psql -U gbrain gbrain -t -A -c "$1" 2>/dev/null | tr -d ' '; }

for _ in $(seq 1 30); do
  T0=$(date +%s)

  # VM
  LOAD=$(cut -d' ' -f1 /proc/loadavg)
  RAM_USED=$(free -m | awk 'NR==2{print $3}'); RAM_TOT=$(free -m | awk 'NR==2{print $2}')
  DISK_PCT=$(df / --output=pcent | tail -1 | tr -dc 0-9)

  # container: {"nome":"stato",...}
  CONT=$($DC ps -a --format '{{.Service}} {{.State}}' 2>/dev/null | \
         awk '{printf "%s\"%s\":\"%s\"", sep, $1, $2; sep=","}')

  # postgres
  EMB=$(PSQL "SELECT count(*) FROM content_chunks WHERE embedding IS NOT NULL;")
  TOT=$(PSQL "SELECT count(*) FROM content_chunks;")
  PAGES=$(PSQL "SELECT count(*) FROM pages WHERE deleted_at IS NULL;")
  FACTS=$(PSQL "SELECT count(*) FROM facts;")
  DBSZ=$(PSQL "SELECT pg_database_size(current_database())/1024/1024;")
  SRC=$($DC exec -T postgres psql -U gbrain gbrain -t -A -F: -c \
    "SELECT p.source_id, count(DISTINCT p.id) FROM pages p WHERE p.deleted_at IS NULL GROUP BY 1;" 2>/dev/null | \
    awk -F: '{printf "%s\"%s\":%s", sep, $1, $2; sep=","}')

  # ollama: modelli caricati + task/min (il battito vero)
  MODELS=$($DC exec -T ollama ollama ps 2>/dev/null | awk 'NR>1{printf "%s\"%s\"", sep, $1; sep=","}')
  OTASKS=$($DC logs ollama --since 1m 2>/dev/null | grep -c "processing task")

  # inbox per reparto + quarantena
  INBOX=$(for d in inbox/*/; do n=$(basename "$d"); [ "$n" = quarantena ] && continue; \
          c=$(find "$d" -maxdepth 1 -type f ! -name '.*' ! -name '*.meta.json' 2>/dev/null | wc -l | tr -d ' '); \
          printf ',"%s":%s' "$n" "$c"; done | sed 's/^,//')
  QUAR=$(find inbox/quarantena -type f ! -name '*.motivo.txt' 2>/dev/null | wc -l | tr -d ' ')

  # backup: età in minuti + MB
  BK=$(ls -t backups/*.tgz 2>/dev/null | head -1)
  if [ -n "$BK" ]; then
    BK_AGE=$(( ($(date +%s) - $(stat -c %Y "$BK")) / 60 )); BK_MB=$(( $(stat -c %s "$BK") / 1024 / 1024 ))
  else BK_AGE=-1; BK_MB=0; fi

  # guardian: streak + ultima riga
  read -r _ _ GSTREAK < /home/ubuntu/.guardian-state 2>/dev/null || GSTREAK=0
  GLAST=$(tail -1 /home/ubuntu/guardian.log 2>/dev/null | sed 's/"/\\"/g' | cut -c1-160)

  # gbrain health (endpoint HTTP del serve)
  GB_OK=$(curl -sf -o /dev/null -w 1 --max-time 3 http://127.0.0.1:3141/health 2>/dev/null || echo 0)

  cat > "$OUT.tmp" <<JSON
{"ts":$T0,"vm":{"load":$LOAD,"ram_used_mb":$RAM_USED,"ram_tot_mb":$RAM_TOT,"disk_pct":$DISK_PCT},
"containers":{${CONT:-}},
"brain":{"pages":${PAGES:-0},"chunks":${TOT:-0},"embedded":${EMB:-0},"facts":${FACTS:-0},"db_mb":${DBSZ:-0},"gbrain_http_ok":${GB_OK:-0},"sources":{${SRC:-}}},
"ollama":{"loaded":[${MODELS:-}],"tasks_per_min":${OTASKS:-0}},
"inbox":{${INBOX:-}},"quarantena":${QUAR:-0},
"backup":{"age_min":$BK_AGE,"size_mb":$BK_MB},
"guardian":{"streak":${GSTREAK:-0},"last":"${GLAST:-}"}}
JSON
  mv -f "$OUT.tmp" "$OUT"   # rename atomico: il gate non serve mai un file a metà

  ELAPSED=$(( $(date +%s) - T0 )); [ "$ELAPSED" -lt 10 ] && sleep $(( 10 - ELAPSED ))
done
