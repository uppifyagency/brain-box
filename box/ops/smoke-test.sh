#!/bin/bash
# La prova "il brain è vivo": health → doctor → ingest E2E di un file test → ricerca.
# Verde = M0 ok su questa macchina. Usato da install.sh e rilanciabile da solo.
set -uo pipefail
cd "$(dirname "$0")/.."
PORT=$(grep '^GBRAIN_PORT=' .env 2>/dev/null | cut -d= -f2); PORT=${PORT:-3141}
GATE=$(grep '^GATE_PORT=' .env 2>/dev/null | cut -d= -f2); GATE=${GATE:-3134}
DEPT=$(grep '^DELERA_DEPTS=' .env | cut -d= -f2 | tr -d '"' | awk '{print $1}')
GB="docker compose exec -T gbrain gbrain"
FAIL=0
ok()  { echo "  ✅ $*"; }
ko()  { echo "  ❌ $*"; FAIL=1; }

echo "== smoke test brain-box =="

curl -sf "http://localhost:$PORT/health" >/dev/null && ok "gbrain /health (:$PORT)" || ko "gbrain non risponde su :$PORT"
curl -sf "http://localhost:$GATE/health" >/dev/null && ok "upload-gate /health (:$GATE)" || ko "upload-gate non risponde su :$GATE"

# doctor --json può crashare (wart upstream visto su VM 6GB: "Trace/breakpoint trap").
# Non è il gate: il gate è l'E2E sotto. Qui solo warning.
if $GB doctor --json 2>/dev/null | grep -q '"'; then ok "doctor risponde"; else echo "  ⚠️ doctor non risponde (wart noto, non blocca: contano health + E2E)"; fi

# E2E: file con marcatore unico → inbox (bind-mount = stesso path del gate) → un ciclo
# di ingest → il marcatore è ricercabile (CLI search vuole --source: muro 09 #8).
MARK="smoke-$(date +%s)"
mkdir -p "inbox/$DEPT"
echo "Il codice segreto dello smoke test è $MARK. Questo file è generato da ops/smoke-test.sh." \
  > "inbox/$DEPT/$MARK.md"
# retrodata il file DENTRO il container (GNU touch): il filtro di stabilità dell'ingest
# (-mmin +1) altrimenti lo salterebbe perché appena creato
docker compose exec -T ingest touch -d "2 minutes ago" "/inbox/$DEPT/$MARK.md" 2>/dev/null || true
docker compose exec -T ingest /ingest/ingest-run.sh >/dev/null 2>&1 || true

FOUND=""
for _ in $(seq 1 24); do   # embed async ~1 min (muro 09 #7): retry fino a 2 min
  if $GB search "$MARK" --source "$DEPT" 2>/dev/null | grep -q "$MARK"; then FOUND=1; break; fi
  sleep 5
done
[ -n "$FOUND" ] && ok "E2E: drop → ingest → cercabile ('$MARK' trovato in '$DEPT')" \
                || ko "E2E: '$MARK' non trovato dopo 2 min (docker compose logs ingest)"

if [ "$FAIL" = 0 ]; then echo "== SMOKE TEST VERDE =="; else echo "== SMOKE TEST ROSSO =="; exit 1; fi
