#!/bin/bash
# Watcher della cartella drop (lanciato da launchd: WatchPaths = all'istante del drop,
# StartInterval 60s = rete di sicurezza/coda offline). Gira e esce — niente demoni.
# File stabile → upload al gate → Caricati/. 4xx → .errore.txt. Rete giù/5xx → resta lì,
# il prossimo giro ritenta da solo (coda offline gratis: il file È la coda).
set -u
BASE="$HOME/BrainDrop"
. "$BASE/.config" || exit 0

# lock: WatchPaths + tick possono sovrapporsi (upload grossi) → un'istanza sola.
LOCK="/tmp/brain-drop.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  # lock più vecchio di 15 min = istanza morta → lo rubo
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +15 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

for dept in $BRAIN_DEPTS; do
  dir="$BASE/$dept"
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 1 -type f ! -name '.*' ! -name '*.errore.txt' -print0 2>/dev/null |
  while IFS= read -r -d '' f; do
    name=$(basename "$f")
    # stabilità: file fresco (<60s) → dimensione ferma per 2s = copia finita, si carica SUBITO
    # (prima: attesa fissa 60s — avrebbe vanificato il trigger a evento di WatchPaths)
    if [ -n "$(find "$f" -mtime -1m 2>/dev/null)" ]; then
      s1=$(stat -f%z "$f" 2>/dev/null) || continue
      sleep 2
      s2=$(stat -f%z "$f" 2>/dev/null) || continue
      [ "$s1" = "$s2" ] || continue   # sta ancora crescendo: al prossimo evento/tick
    fi

    code=$(curl -sS -o /tmp/brain-drop-resp.$$ -w '%{http_code}' --max-time 600 \
      -X POST "$BRAIN_URL/upload?dept=$dept" \
      -H "Authorization: Bearer $BRAIN_TOKEN" \
      -H "X-Filename: $name" \
      -H "X-Employee: $BRAIN_EMPLOYEE" \
      --data-binary "@$f" 2>/dev/null) || code=000

    case "$code" in
      200)
        mv -f "$f" "$dir/Caricati/$name"
        rm -f "$f.errore.txt" ;;
      4*)
        { echo "Questo file NON è entrato nel brain ($(date '+%d/%m %H:%M'))."
          echo "Motivo: $(cat /tmp/brain-drop-resp.$$ 2>/dev/null)"
          echo "Se è un formato non supportato, convertilo in PDF e ritrascinalo."
        } > "$f.errore.txt" ;;
      *) : ;;  # rete giù / 5xx → silenzio, si ritenta al prossimo giro
    esac
    rm -f /tmp/brain-drop-resp.$$
  done
done
