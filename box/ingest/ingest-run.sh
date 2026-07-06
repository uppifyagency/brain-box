#!/bin/bash
# UN ciclo di ingest (dentro il container `ingest`): inbox → convert/transcribe → brain repo
# → sources/git → sync → embed → extract → doctor. Sequenza e muri ereditati da 09 (verificati).
set -uo pipefail

BRAIN=/data/brain
INBOX=/inbox
QUAR=/inbox/quarantena
DEPTS="${DELERA_DEPTS:-generale}"
DOCS_EXT="pdf docx xlsx pptx txt text html htm rtf csv json epub png jpg jpeg webp"
AV_EXT="mp3 wav m4a mp4 webm mov"

log() { echo "[ingest] $*"; }

# frontmatter provenance dal sidecar .meta.json del gate (se c'è)
frontmatter() { # $1=file originale $2=titolo
  local meta="$1.meta.json" emp="" up=""
  if [ -f "$meta" ]; then
    emp=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('employee') or '')" "$meta" 2>/dev/null || true)
    up=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('uploaded_at') or '')" "$meta" 2>/dev/null || true)
  fi
  printf -- '---\ntitle: "%s"\nimported_from: "%s"\n' "$2" "$(basename "$1")"
  # type note = eleggibile all'estrazione fatti (eligibility.ts: 'concept' NON lo è).
  # libri resta senza type (→ concept): i libri non devono generare pseudo-fatti.
  [ "${dept:-}" = "libri" ] || printf 'type: note\n'
  [ -n "$emp" ] && printf 'uploaded_by: "%s"\n' "$emp"
  [ -n "$up" ] && printf 'uploaded_at: "%s"\n' "$up"
  printf -- '---\n\n'
}

quarantine() { # $1=file $2=motivo
  local dept_dir; dept_dir="$QUAR/$(basename "$(dirname "$1")")"
  mkdir -p "$dept_dir"
  log "QUARANTENA $(basename "$1"): $2"
  echo "$(date -Iseconds) $2" >> "$dept_dir/$(basename "$1").motivo.txt"
  mv -f "$1" "$dept_dir/" 2>/dev/null || true
  rm -f "$1.meta.json"
}

# ── A. conversione: inbox/<reparto>/* → brain/<reparto>/imports/*.md ──────────────
NEW_MD=$(mktemp)   # file (non var): il loop A gira in subshell (pipe da find)
for dept in $DEPTS; do
  mkdir -p "$INBOX/$dept" "$BRAIN/$dept/imports"
  # corsia veloce: file col sidecar .meta.json = scritto dal gate (rename atomico) = già completo
  # → si processa SUBITO (trigger a evento). Senza sidecar (scp/admin) → attesa stabilità 60s.
  find "$INBOX/$dept" -maxdepth 1 -type f \
      ! -name '.*' ! -name '*.meta.json' ! -name '*.motivo.txt' -print0 2>/dev/null |
  while IFS= read -r -d '' f; do
    if [ ! -f "$f.meta.json" ] && [ -n "$(find "$f" -mmin -1 2>/dev/null)" ]; then
      continue   # file "a mano" ancora fresco: al prossimo giro
    fi
    name=$(basename "$f"); stem="${name%.*}"; ext="${name##*.}"; ext=$(echo "$ext" | tr 'A-Z' 'a-z')
    slug=$(echo "$stem" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')
    out="$BRAIN/$dept/imports/${slug}.md"
    tmp=$(mktemp)
    case " $ext " in
      " md "|" mdx ")
        { frontmatter "$f" "$stem"; cat "$f"; } > "$out" && { rm -f "$f" "$f.meta.json"; echo "$dept|$out" >> "$NEW_MD"; } \
          || quarantine "$f" "copia markdown fallita" ;;
      *)
        if echo " $DOCS_EXT " | grep -q " $ext "; then
          if python3 /ingest/convert-docs.py "$f" "$tmp"; then
            { frontmatter "$f" "$stem"; cat "$tmp"; } > "$out"; rm -f "$f" "$f.meta.json"
            echo "$dept|$out" >> "$NEW_MD"
            log "convertito: $dept/$name → imports/${slug}.md"
          else quarantine "$f" "conversione fallita ($ext)"; fi
        elif echo " $AV_EXT " | grep -q " $ext "; then
          if python3 /ingest/transcribe-av.py "$f" "$tmp"; then
            if [ -s "$tmp" ]; then
              { frontmatter "$f" "$stem (trascrizione)"; cat "$tmp"; } > "$out"; echo "$dept|$out" >> "$NEW_MD"; log "trascritto: $dept/$name"
            else log "skip pulito (nessun audio): $dept/$name"; fi
            rm -f "$f" "$f.meta.json"
          else quarantine "$f" "trascrizione fallita"; fi
        else
          quarantine "$f" "formato non supportato (.$ext) — vedi matrice PIANO §5"
        fi ;;
    esac
    rm -f "$tmp"
  done
done

# ── B. source + git per reparto (F5: reparti vuoti SALTATI — repo senza commit rompe sync --all)
GB=gbrain
for dept in $DEPTS; do
  dp="$BRAIN/$dept"
  [ -z "$(find "$dp" -type f ! -path '*/.git/*' ! -name '.gitkeep' 2>/dev/null | head -1)" ] && continue
  if ! $GB sources list --json 2>/dev/null | grep -q "\"$dept\""; then
    $GB sources add "$dept" --path "/data/brain/$dept" --name "$dept" --federated \
      || log "ATTENZIONE: sources add $dept fallito"
  fi
  [ -d "$dp/.git" ] || git -C "$dp" init -q
  git -C "$dp" add -A
  git -C "$dp" commit -q -m sync >/dev/null 2>&1 || true   # nothing-to-commit non è un errore
done

# ── C. sync → embed → extract (ordine e tolleranze verificati in 09) ─────────────
$GB sync --all || log "sync: una o più source saltate (continuo)"
$GB embed --stale || true                       # rete di sicurezza: il backfill async fa il grosso
$GB extract links --source db || log "extract links: warn"
$GB extract timeline --source db || log "extract timeline: warn"

# ── C2. fatti automatici sui file NUOVI (gemma, best-effort — F3 2026-07-03) ──────
# Il facts_backstop nativo del sync è fire-and-forget e MUORE quando il CLI esce
# (verificato: sync 0.8s, coda mai drenata) → estrazione ESPLICITA inline qui.
# libri escluso (pseudo-fatti), cap 5/ciclo (import massivi = skip), timeout 240s,
# mai bloccante. ponytail: resa variabile su doc lunghi accettata; upgrade quando
# upstream fixa la coda CLI o il formato per modelli piccoli (#2554-family).
FACTS_CAP=5; _fc=0
while IFS='|' read -r fdept fout; do
  [ "$fdept" = "libri" ] && continue
  [ -s "$fout" ] || continue
  _fc=$((_fc+1)); [ "$_fc" -gt "$FACTS_CAP" ] && { log "facts: cap $FACTS_CAP raggiunto, resto al dream"; break; }
  body=$(sed '1,/^---$/d' "$fout" | head -c 6000)
  [ "${#body}" -lt 80 ] && continue
  fjson=$(printf '%s' "$body" | python3 -c "import json,sys;print(json.dumps({'turn_text':sys.stdin.read(),'session_id':'ingest:'+sys.argv[1],'visibility':'world'}))" "$(basename "$fout")")
  fres=$(timeout 240 env GBRAIN_SOURCE="$fdept" $GB call extract_facts "$fjson" 2>/dev/null) \
    && log "facts $fdept/$(basename "$fout"): $(printf '%s' "$fres" | python3 -c "import json,sys;d=json.load(sys.stdin);print('inserted=%s dup=%s'%(d.get('inserted',0),d.get('duplicate',0)))" 2>/dev/null || echo ok)" \
    || log "facts: skip $fdept/$(basename "$fout") (timeout/errore, non bloccante)"
done < "$NEW_MD"
rm -f "$NEW_MD"

# ── D. verdetto per smoke-test/monitoring ─────────────────────────────────────────
$GB doctor --json > /data/gbrain/last-doctor.json 2>/dev/null || true
log "ciclo completato $(date -Iseconds)"
