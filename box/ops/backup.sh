#!/bin/bash
# Backup completo in UN archivio: brain/ (system of record) + pg_dump (embeddings, token,
# audit, facts). Da mettere in cron. Ripristino: ops/restore.sh <archivio>.
set -euo pipefail
cd "$(dirname "$0")/.."
TS=$(date +%Y%m%d-%H%M%S)
OUT="backups/brain-box-$TS"
mkdir -p "$OUT"

docker compose exec -T postgres pg_dump -U gbrain gbrain | gzip > "$OUT/db.sql.gz"
tar czf "$OUT/brain.tgz" brain/
cp config.yml "$OUT/"

tar czf "backups/brain-box-$TS.tgz" -C backups "brain-box-$TS"
rm -rf "$OUT"
# tieni gli ultimi 14
ls -1t backups/brain-box-*.tgz 2>/dev/null | tail -n +15 | xargs rm -f 2>/dev/null || true
echo "backup: backups/brain-box-$TS.tgz"
