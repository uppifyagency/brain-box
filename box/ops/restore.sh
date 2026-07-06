#!/bin/bash
# Ripristina un backup su QUESTO box (anche su hosting diverso: copia la cartella
# brain-box, ./install.sh, poi questo script). ⚠️ Sovrascrive DB e brain/ correnti.
set -euo pipefail
cd "$(dirname "$0")/.."
ARC="${1:-}"; [ -f "$ARC" ] || { echo "uso: $0 backups/brain-box-<ts>.tgz"; exit 1; }

read -r -p "Sovrascrivo DB e brain/ di questa istanza con $ARC. Confermi? [scrivi SI] " R
[ "$R" = "SI" ] || { echo "annullato"; exit 1; }

TMP=$(mktemp -d)
tar xzf "$ARC" -C "$TMP"
DIR=$(find "$TMP" -maxdepth 1 -type d -name 'brain-box-*' | head -1)

rm -rf brain && mkdir brain
tar xzf "$DIR/brain.tgz"

# DROP/CREATE DATABASE non possono stare nello stesso -c: psql li avvolge in una
# transazione e DROP DATABASE la rifiuta (scoperto col drill del 2026-07-03 — lo
# script com'era moriva qui il giorno del disastro).
docker compose exec -T postgres psql -U gbrain -c "DROP DATABASE IF EXISTS gbrain_restore;" postgres
docker compose exec -T postgres psql -U gbrain -c "CREATE DATABASE gbrain_restore;" postgres
gunzip -c "$DIR/db.sql.gz" | docker compose exec -T postgres psql -q -U gbrain gbrain_restore
docker compose stop gbrain gate ingest
docker compose exec -T postgres psql -U gbrain -c "DROP DATABASE gbrain;" postgres
docker compose exec -T postgres psql -U gbrain -c "ALTER DATABASE gbrain_restore RENAME TO gbrain;" postgres
docker compose start gbrain gate ingest

rm -rf "$TMP"
echo "ripristinato. Verifica: ./ops/smoke-test.sh"
