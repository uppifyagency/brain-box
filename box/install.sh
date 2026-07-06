#!/bin/bash
# brain-box — UNICO comando di installazione. Idempotente: rilanciarlo non distrugge nulla.
# Fa: prerequisiti → segreti per-istanza → compose up → attesa health → smoke test → prossimi passi.
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
die() { echo "ERRORE: $*" >&2; exit 1; }

# ── prerequisiti ──────────────────────────────────────────────────────────────────
command -v docker >/dev/null || die "serve Docker (https://docs.docker.com/engine/install/)"
docker info >/dev/null 2>&1 || die "il demone Docker non risponde: avvialo"

# ── config.yml (piatto: chiave: valore) ───────────────────────────────────────────
cfg() { awk -F': *' -v k="$1" '$1==k{sub(/^[^:]*: */,"");print;exit}' config.yml; }
AZIENDA=$(cfg azienda);   [ -n "$AZIENDA" ] || die "config.yml: manca 'azienda'"
DEPTS=$(cfg reparti);     [ -n "$DEPTS" ]   || die "config.yml: manca 'reparti'"
EXPOSE=$(cfg expose);     EXPOSE=${EXPOSE:-tailnet}
LLM=$(cfg llm);           LLM=${LLM:-off}

# ── .env: segreti PER-ISTANZA, generati una volta, mai sovrascritti ───────────────
if [ ! -f .env ]; then
  say "genero i segreti dell'istanza (.env)"
  PGPW=$(openssl rand -hex 24)
  cat > .env <<EOF
# generato da install.sh — NON committare, NON condividere tra istanze
POSTGRES_PASSWORD=$PGPW
GBRAIN_PORT=3141
GATE_PORT=3134
# llm: delera|byok → scommenta e compila (PIANO §5.1)
#LLM_BASE_URL=
#LLM_API_KEY=
EOF
  chmod 600 .env
fi
# chiavi GESTITE (riflettono config.yml a ogni run; i segreti sopra restano intatti)
grep -q '^DELERA_DEPTS=' .env && sed -i.bak "s/^DELERA_DEPTS=.*/DELERA_DEPTS=\"$DEPTS\"/" .env \
  || echo "DELERA_DEPTS=\"$DEPTS\"" >> .env
rm -f .env.bak

# ── Ollama: nativo sull'host (Mac/dev) o container (VM Linux) ─────────────────────
PROFILE=()
if curl -sf --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
  say "Ollama NATIVO rilevato sull'host: lo riuso (zero download duplicati)"
  grep -q '^OLLAMA_BASE_URL=' .env || echo "OLLAMA_BASE_URL=http://host.docker.internal:11434/v1" >> .env
  ollama pull bge-m3 2>/dev/null || true
else
  say "nessun Ollama sull'host: uso il container (profilo bundled-ollama)"
  PROFILE=(--profile bundled-ollama)
  sed -i.bak '/^OLLAMA_BASE_URL=/d' .env && rm -f .env.bak
fi

[ "$LLM" = "off" ] || grep -q '^LLM_API_KEY=..*' .env \
  || echo "ATTENZIONE: llm: $LLM in config.yml ma LLM_API_KEY vuota in .env → il dream cycle LLM resterà spento"

# ── su ─────────────────────────────────────────────────────────────────────────────
mkdir -p brain inbox backups
# ORDINE (imparato dal test su VM pulita): con l'ollama in container, il MODELLO deve
# esserci PRIMA che gbrain faccia init/ingest — altrimenti il primo embed fallisce e
# il backfill va in cooldown (smoke rosso pur con box sano).
if [ "${#PROFILE[@]}" -gt 0 ]; then
  say "avvio Ollama e scarico il modello embedding (bge-m3, ~1.1GB) PRIMA del resto"
  docker compose ${PROFILE[@]+"${PROFILE[@]}"} up -d ollama
  docker compose ${PROFILE[@]+"${PROFILE[@]}"} exec -T ollama sh -c 'until ollama list >/dev/null 2>&1; do sleep 2; done'
  docker compose ${PROFILE[@]+"${PROFILE[@]}"} exec -T ollama ollama pull bge-m3
fi
say "avvio il box (prima volta: build immagini + download, può volerci qualche minuto)"
# ${PROFILE[@]+...}: bash 3.2 (macOS) + set -u esplode su array vuoto senza questa guardia
docker compose ${PROFILE[@]+"${PROFILE[@]}"} up -d --build

say "attendo che il brain sia vivo"
PORT=$(grep '^GBRAIN_PORT=' .env | cut -d= -f2)
for _ in $(seq 1 60); do
  curl -sf "http://localhost:${PORT:-3141}/health" >/dev/null 2>&1 && break
  sleep 3
done
curl -sf "http://localhost:${PORT:-3141}/health" >/dev/null || die "gbrain non risponde su :${PORT:-3141} — vedi: docker compose logs gbrain"

# WORKAROUND bug upstream (op-checkpoint.ts:189, commit bb2e88c): il checkpoint del sync
# viene scritto JSONB doppio-encodato → viola il CHECK → OGNI sync dopo il primo abortisce
# con "checkpoint_unavailable". Il drop del vincolo è innocuo (solo validazione di forma).
# Rimuovere quando fixato a monte. Trovato su VM pulita 2026-07-02.
docker compose exec -T postgres psql -U gbrain -q gbrain -c \
  "ALTER TABLE op_checkpoints DROP CONSTRAINT IF EXISTS op_checkpoints_completed_keys_array;" 2>/dev/null || true

# ── prova che è vivo davvero ────────────────────────────────────────────────────────
./ops/smoke-test.sh

say "FATTO — prossimi passi"
cat <<EOF
1. Esponi il brain (host, una volta):
     tailscale up
     tailscale serve --bg --set-path /mcp    http://127.0.0.1:${PORT:-3141}/mcp
     tailscale serve --bg --set-path /upload http://127.0.0.1:3134/upload
EOF
[ "$EXPOSE" = "public" ] && cat <<'EOF'
     tailscale funnel --bg 443    # expose: public → /mcp raggiungibile da claude.ai
EOF
cat <<EOF
2. Registra un dipendente:   ./client-kit/register-employee.sh <nome>
3. Backup in cron:           crontab -e →  0 3 * * * $(pwd)/ops/backup.sh
EOF
