#!/bin/bash
# Sul BOX. Conia per un dipendente un bearer STATICO federato su tutti i reparti e stampa:
# la riga `claude mcp add`, le env per il watcher della cartella drop, i puntatori Codex/Gemini.
# Meccanica del grant federato VERIFICATA E2E in 10 (contratto core/legacy-token-scope.ts:
# un bearer nudo vede solo 'default'; con l'array in permissions.source_id federa).
#
# uso: ./client-kit/register-employee.sh <nome> [url-base]     (url-base es. https://box.<tailnet>.ts.net)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:-}"; [ -n "$NAME" ] || { echo "uso: $0 <nome> [url-base]"; exit 1; }
BASE="${2:-http://localhost:$(grep '^GBRAIN_PORT=' .env | cut -d= -f2)}"
WRITE_SRC="${3:-$(grep '^DELERA_DEPTS=' .env | cut -d= -f2 | tr -d '"' | awk '{print $1}')}"

GB="docker compose exec -T gbrain gbrain"
PSQL="docker compose exec -T postgres psql -U gbrain gbrain"

# un solo token pulito per nome (auth create non deduplica)
$GB auth revoke "$NAME" >/dev/null 2>&1 || true
TOK=$($GB auth create "$NAME" 2>&1 | grep -oE 'gbrain_[A-Za-z0-9_-]+' | head -1)
[ -n "$TOK" ] || { echo "ERRORE: creazione token fallita (box su? docker compose ps)"; exit 1; }

# array reparti federati, write-floor = primo
ARR=$($GB sources list --json 2>/dev/null | python3 -c '
import sys, json
w = sys.argv[1]
d = json.load(sys.stdin)
srcs = d.get("sources", d) if isinstance(d, dict) else d
ids = [s["id"] for s in srcs if s.get("federated")]
print(json.dumps([w] + [i for i in ids if i != w]))' "$WRITE_SRC")
[ -n "$ARR" ] || { echo "ERRORE: sources list vuota (almeno un reparto con contenuto?)"; exit 1; }

$PSQL -q -c "UPDATE access_tokens SET permissions = jsonb_set(coalesce(permissions,'{}'::jsonb),'{source_id}','$ARR'::jsonb) WHERE name='$NAME';"

cat <<EOF

== $NAME · reparti federati: $ARR · scrive in: $WRITE_SRC ==

1) Claude Code — il dipendente incolla questa riga e riavvia:

   claude mcp add brain --transport http "$BASE/mcp" --header "Authorization: Bearer $TOK"

2) Cartella drop sul suo Mac (opzionale):

   BRAIN_URL="$BASE" BRAIN_TOKEN="$TOK" BRAIN_EMPLOYEE="$NAME" ./install-drop.sh
   (script in client-kit/drop-installer/, da inviargli insieme al token)

3) Codex / Gemini / claude.ai: ricette in client-kit/CONNETTORI.md
   (claude.ai richiede expose: public — vedi GO-LIVE.md)

Revoca immediata:  docker compose exec gbrain gbrain auth revoke $NAME
⚠️ Il bearer è full-access sui reparti federati (F7): backup notturno attivo prima di distribuirlo.
EOF
