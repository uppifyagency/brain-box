#!/bin/bash
# Sul MAC DEL DIPENDENTE. Crea la cartella drop sul Desktop + il watcher invisibile (launchd).
# uso: BRAIN_URL=https://box.<tailnet>.ts.net BRAIN_TOKEN=gbrain_xxx BRAIN_EMPLOYEE=mario ./install-drop.sh
# I reparti li chiede al gate (GET /health non li dà: li passa l'admin) → env BRAIN_DEPTS="generale vendite".
set -euo pipefail

: "${BRAIN_URL:?serve BRAIN_URL (dal foglio dell'admin)}"
: "${BRAIN_TOKEN:?serve BRAIN_TOKEN (dal foglio dell'admin)}"
: "${BRAIN_EMPLOYEE:?serve BRAIN_EMPLOYEE (il tuo nome)}"
: "${BRAIN_DEPTS:?serve BRAIN_DEPTS (es. \"generale vendite\")}"
AZIENDA="${BRAIN_AZIENDA:-Azienda}"

# F9 (TCC): launchd NON può leggere ~/Desktop → la cartella vera sta in ~/BrainDrop,
# sul Desktop c'è solo un symlink (verificato in 09: drag&drop in Finder funziona uguale).
BASE="$HOME/BrainDrop"
mkdir -p "$BASE"
for d in $BRAIN_DEPTS; do mkdir -p "$BASE/$d/Caricati"; done
ln -sfn "$BASE" "$HOME/Desktop/$AZIENDA Brain"

# config del watcher (600: contiene il token)
cat > "$BASE/.config" <<EOF
BRAIN_URL="$BRAIN_URL"
BRAIN_TOKEN="$BRAIN_TOKEN"
BRAIN_EMPLOYEE="$BRAIN_EMPLOYEE"
BRAIN_DEPTS="$BRAIN_DEPTS"
EOF
chmod 600 "$BASE/.config"

# watcher accanto alla config + LaunchAgent ogni 60s
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/watcher.sh" "$BASE/.watcher.sh"
chmod +x "$BASE/.watcher.sh"

PLIST="$HOME/Library/LaunchAgents/it.delera.brain-drop.plist"
mkdir -p "$(dirname "$PLIST")"
# WatchPaths: una entry per reparto → trigger all'istante del drop (il tick 60s resta come
# fallback). Tutte su UNA riga: BSD sed non espande \n nella replacement, e all'XML non importa.
WATCHPATHS=""
for d in $BRAIN_DEPTS; do WATCHPATHS="$WATCHPATHS<string>$BASE/$d</string>"; done
sed -e "s|__WATCHER__|$BASE/.watcher.sh|" -e "s|__WATCHPATHS__|    $WATCHPATHS|" \
    "$SCRIPT_DIR/it.delera.brain-drop.plist.tpl" > "$PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "✅ Fatto. Trascina i file in: Desktop/$AZIENDA Brain/<reparto>/"
echo "   Caricato con successo → finisce in Caricati/. Problema → appare <file>.errore.txt."
